//! A small, dependency-free ONNX inference engine (f32, batch 1, NCHW).
//!
//! It covers the operator set of the on-device vision models Kader runs —
//! YuNet face detection and SFace face recognition — not ONNX at large:
//! Conv (grouped/depthwise), BatchNormalization, Relu, PRelu, Sigmoid,
//! MaxPool, Resize (nearest), Add/Sub/Mul (same-shape or scalar), Transpose,
//! Reshape, Flatten, Gemm and Dropout (identity). An unsupported operator
//! fails at load time with its name, never at inference.
//!
//! Loading folds every BatchNormalization that directly follows a Conv into
//! the convolution's weights, resolves value names to slots and records each
//! value's last use so intermediate tensors are freed as soon as possible.

// Numeric kernels index several parallel arrays; index loops read clearer.
#![allow(clippy::needless_range_loop)]

mod ops;
pub mod proto;

pub use ops::set_threads;

use proto::{fields, push_f32s, push_i64s, Field};
use std::collections::HashMap;

#[derive(Clone, Debug, Default)]
pub struct Tensor {
    pub shape: Vec<usize>,
    pub data: Vec<f32>,
    /// int64 payload (shape constants); empty for float tensors
    pub ints: Vec<i64>,
}

impl Tensor {
    pub fn new(shape: Vec<usize>, data: Vec<f32>) -> Self {
        debug_assert_eq!(shape.iter().product::<usize>(), data.len());
        Tensor {
            shape,
            data,
            ints: Vec::new(),
        }
    }
    pub fn len(&self) -> usize {
        self.shape.iter().product()
    }
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

#[derive(Debug, Clone)]
enum Op {
    Conv {
        group: usize,
        stride: [usize; 2],
        pad: [usize; 4],
        dilation: [usize; 2],
    },
    BatchNorm {
        eps: f32,
    },
    Relu,
    PRelu,
    Sigmoid,
    MaxPool {
        kernel: [usize; 2],
        stride: [usize; 2],
        pad: [usize; 4],
    },
    ResizeNearest,
    Add,
    Sub,
    Mul,
    Transpose {
        perm: Vec<usize>,
    },
    Reshape,
    Flatten {
        axis: usize,
    },
    Gemm {
        alpha: f32,
        beta: f32,
        trans_a: bool,
        trans_b: bool,
    },
    Identity,
}

#[derive(Debug, Clone)]
struct Node {
    op: Op,
    inputs: Vec<Option<usize>>, // None = omitted optional input ("")
    outputs: Vec<usize>,
}

/// A loaded, ready-to-run model.
pub struct Model {
    nodes: Vec<Node>,
    n_slots: usize,
    consts: Vec<Option<Tensor>>, // initializers, by slot
    input: usize,
    outputs: Vec<(String, usize)>,
    /// for each node, the slots whose last reader it is
    frees: Vec<Vec<usize>>,
}

// ── ONNX parsing ────────────────────────────────────────────────────────────

#[derive(Default)]
struct Attr {
    i: Option<i64>,
    f: Option<f32>,
    s: Option<String>,
    ints: Vec<i64>,
}

#[derive(Default)]
struct RawNode {
    op_type: String,
    inputs: Vec<String>,
    outputs: Vec<String>,
    attrs: HashMap<String, Attr>,
}

fn parse_attr(buf: &[u8]) -> Option<(String, Attr)> {
    let mut name = String::new();
    let mut a = Attr::default();
    fields(buf, |n, f| {
        match n {
            1 => name = f.as_str()?.to_owned(),
            2 => a.f = f.as_f32(),
            3 => a.i = f.as_i64(),
            4 => a.s = Some(String::from_utf8_lossy(f.as_bytes()?).into_owned()),
            8 => push_i64s(f, &mut a.ints)?,
            _ => {}
        }
        Some(())
    })?;
    Some((name, a))
}

fn parse_node(buf: &[u8]) -> Option<RawNode> {
    let mut node = RawNode::default();
    fields(buf, |n, f| {
        match n {
            1 => node.inputs.push(f.as_str()?.to_owned()),
            2 => node.outputs.push(f.as_str()?.to_owned()),
            4 => node.op_type = f.as_str()?.to_owned(),
            5 => {
                let (k, v) = parse_attr(f.as_bytes()?)?;
                node.attrs.insert(k, v);
            }
            _ => {}
        }
        Some(())
    })?;
    Some(node)
}

const ONNX_FLOAT: i64 = 1;
const ONNX_INT64: i64 = 7;

fn parse_tensor(buf: &[u8]) -> Option<(String, Tensor)> {
    let mut name = String::new();
    let mut dims: Vec<i64> = Vec::new();
    let mut dtype = 0i64;
    let mut floats: Vec<f32> = Vec::new();
    let mut ints: Vec<i64> = Vec::new();
    let mut raw: &[u8] = &[];
    fields(buf, |n, f| {
        match n {
            1 => push_i64s(f, &mut dims)?,
            2 => dtype = f.as_i64()?,
            4 => push_f32s(f, &mut floats)?,
            7 => push_i64s(f, &mut ints)?,
            8 => name = f.as_str()?.to_owned(),
            9 => raw = f.as_bytes()?,
            _ => {}
        }
        Some(())
    })?;
    let shape: Vec<usize> = dims
        .iter()
        .map(|&d| usize::try_from(d).ok())
        .collect::<Option<_>>()?;
    let count: usize = shape.iter().product();
    let mut t = Tensor {
        shape,
        ..Default::default()
    };
    match dtype {
        ONNX_FLOAT => {
            if !raw.is_empty() {
                if raw.len() != count * 4 {
                    return None;
                }
                floats = raw
                    .chunks_exact(4)
                    .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
                    .collect();
            }
            if floats.len() != count {
                return None;
            }
            t.data = floats;
        }
        ONNX_INT64 => {
            if !raw.is_empty() {
                if raw.len() != count * 8 {
                    return None;
                }
                ints = raw
                    .chunks_exact(8)
                    .map(|c| i64::from_le_bytes(c.try_into().unwrap()))
                    .collect();
            }
            if ints.len() != count {
                return None;
            }
            t.data = ints.iter().map(|&v| v as f32).collect();
            t.ints = ints;
        }
        _ => return None,
    }
    Some((name, t))
}

fn value_name(buf: &[u8]) -> Option<String> {
    let mut name = String::new();
    fields(buf, |n, f| {
        if n == 1 {
            name = f.as_str()?.to_owned();
        }
        Some(())
    })?;
    Some(name)
}

fn usize_pair(v: &[i64], default: usize) -> Option<[usize; 2]> {
    match v {
        [] => Some([default; 2]),
        [a, b] => Some([usize::try_from(*a).ok()?, usize::try_from(*b).ok()?]),
        _ => None,
    }
}

fn pads4(v: &[i64]) -> Option<[usize; 4]> {
    match v {
        [] => Some([0; 4]),
        [t, l, b, r] => Some([
            usize::try_from(*t).ok()?,
            usize::try_from(*l).ok()?,
            usize::try_from(*b).ok()?,
            usize::try_from(*r).ok()?,
        ]),
        _ => None,
    }
}

impl Model {
    /// Parses an ONNX file. Fails with a message naming the problem.
    pub fn load(bytes: &[u8]) -> Result<Model, String> {
        let mut graph: &[u8] = &[];
        fields(bytes, |n, f| {
            if n == 7 {
                graph = f.as_bytes()?;
            }
            Some(())
        })
        .ok_or("not an ONNX model")?;
        if graph.is_empty() {
            return Err("ONNX model has no graph".into());
        }

        let mut raw_nodes = Vec::new();
        let mut inits: HashMap<String, Tensor> = HashMap::new();
        let mut inputs = Vec::new();
        let mut outputs = Vec::new();
        fields(graph, |n, f: Field| {
            match n {
                1 => raw_nodes.push(parse_node(f.as_bytes()?)?),
                5 => {
                    let (k, t) = parse_tensor(f.as_bytes()?)?;
                    inits.insert(k, t);
                }
                11 => inputs.push(value_name(f.as_bytes()?)?),
                12 => outputs.push(value_name(f.as_bytes()?)?),
                _ => {}
            }
            Some(())
        })
        .ok_or("malformed ONNX graph")?;

        let real_inputs: Vec<&String> = inputs.iter().filter(|i| !inits.contains_key(*i)).collect();
        let [input_name] = real_inputs.as_slice() else {
            return Err(format!(
                "expected one graph input, found {}",
                real_inputs.len()
            ));
        };

        // name → slot
        let mut slots: HashMap<String, usize> = HashMap::new();
        let slot_of = |name: &str, slots: &mut HashMap<String, usize>| -> usize {
            let n = slots.len();
            *slots.entry(name.to_owned()).or_insert(n)
        };
        let input = slot_of(input_name, &mut slots);

        let mut nodes = Vec::with_capacity(raw_nodes.len());
        for rn in &raw_nodes {
            let attr_i = |k: &str, d: i64| rn.attrs.get(k).and_then(|a| a.i).unwrap_or(d);
            let attr_f = |k: &str, d: f32| rn.attrs.get(k).and_then(|a| a.f).unwrap_or(d);
            let attr_ints = |k: &str| rn.attrs.get(k).map(|a| a.ints.clone()).unwrap_or_default();
            let bad = || format!("unsupported attributes on {}", rn.op_type);
            let op = match rn.op_type.as_str() {
                "Conv" => {
                    if rn
                        .attrs
                        .get("auto_pad")
                        .and_then(|a| a.s.as_deref())
                        .is_some_and(|s| s != "NOTSET")
                    {
                        return Err("Conv auto_pad is not supported".into());
                    }
                    Op::Conv {
                        group: usize::try_from(attr_i("group", 1)).map_err(|_| bad())?,
                        stride: usize_pair(&attr_ints("strides"), 1).ok_or_else(bad)?,
                        pad: pads4(&attr_ints("pads")).ok_or_else(bad)?,
                        dilation: usize_pair(&attr_ints("dilations"), 1).ok_or_else(bad)?,
                    }
                }
                "BatchNormalization" => Op::BatchNorm {
                    eps: attr_f("epsilon", 1e-5),
                },
                "Relu" => Op::Relu,
                "PRelu" => Op::PRelu,
                "Sigmoid" => Op::Sigmoid,
                "MaxPool" => {
                    if attr_i("ceil_mode", 0) != 0 {
                        return Err("MaxPool ceil_mode is not supported".into());
                    }
                    Op::MaxPool {
                        kernel: usize_pair(&attr_ints("kernel_shape"), 1).ok_or_else(bad)?,
                        stride: usize_pair(&attr_ints("strides"), 1).ok_or_else(bad)?,
                        pad: pads4(&attr_ints("pads")).ok_or_else(bad)?,
                    }
                }
                "Resize" | "Upsample" => {
                    let mode = rn
                        .attrs
                        .get("mode")
                        .and_then(|a| a.s.clone())
                        .unwrap_or_else(|| "nearest".into());
                    if mode != "nearest" {
                        return Err(format!("Resize mode {mode} is not supported"));
                    }
                    Op::ResizeNearest
                }
                "Add" => Op::Add,
                "Sub" => Op::Sub,
                "Mul" => Op::Mul,
                "Transpose" => Op::Transpose {
                    perm: attr_ints("perm").iter().map(|&p| p as usize).collect(),
                },
                "Reshape" => Op::Reshape,
                "Flatten" => Op::Flatten {
                    axis: usize::try_from(attr_i("axis", 1)).map_err(|_| bad())?,
                },
                "Gemm" => Op::Gemm {
                    alpha: attr_f("alpha", 1.0),
                    beta: attr_f("beta", 1.0),
                    trans_a: attr_i("transA", 0) != 0,
                    trans_b: attr_i("transB", 0) != 0,
                },
                "Dropout" | "Identity" => Op::Identity,
                other => return Err(format!("unsupported ONNX operator: {other}")),
            };
            let ins = rn
                .inputs
                .iter()
                .map(|n| (!n.is_empty()).then(|| slot_of(n, &mut slots)))
                .collect();
            // Dropout's optional mask output is never consumed; keep only the first
            let outs = rn
                .outputs
                .iter()
                .take(1)
                .map(|n| slot_of(n, &mut slots))
                .collect();
            nodes.push(Node {
                op,
                inputs: ins,
                outputs: outs,
            });
        }

        let n_slots = slots.len();
        let mut consts: Vec<Option<Tensor>> = vec![None; n_slots];
        for (name, t) in inits {
            if let Some(&s) = slots.get(&name) {
                consts[s] = Some(t);
            }
        }
        let outputs = outputs
            .into_iter()
            .map(|name| {
                let s = *slots
                    .get(&name)
                    .ok_or_else(|| format!("graph output {name} is never produced"))?;
                Ok((name, s))
            })
            .collect::<Result<Vec<_>, String>>()?;

        let mut m = Model {
            nodes,
            n_slots,
            consts,
            input,
            outputs,
            frees: Vec::new(),
        };
        m.fold_batchnorm();
        m.plan_frees();
        Ok(m)
    }

    /// Conv → BatchNormalization (the BN being the conv output's only reader)
    /// becomes one Conv with scaled weights and a shifted bias.
    fn fold_batchnorm(&mut self) {
        let mut readers = vec![0usize; self.n_slots];
        for n in &self.nodes {
            for s in n.inputs.iter().flatten() {
                readers[*s] += 1;
            }
        }
        for &(_, s) in &self.outputs {
            readers[s] += 1;
        }
        let producer: HashMap<usize, usize> = self
            .nodes
            .iter()
            .enumerate()
            .flat_map(|(i, n)| n.outputs.iter().map(move |&s| (s, i)))
            .collect();

        let mut removed = vec![false; self.nodes.len()];
        for bi in 0..self.nodes.len() {
            let Op::BatchNorm { eps } = self.nodes[bi].op else {
                continue;
            };
            let bn_in = &self.nodes[bi].inputs;
            let (Some(x), Some(gs), Some(bs), Some(ms), Some(vs)) = (
                bn_in.first().copied().flatten(),
                bn_in.get(1).copied().flatten(),
                bn_in.get(2).copied().flatten(),
                bn_in.get(3).copied().flatten(),
                bn_in.get(4).copied().flatten(),
            ) else {
                continue;
            };
            let Some(&ci) = producer.get(&x) else {
                continue;
            };
            if readers[x] != 1 || !matches!(self.nodes[ci].op, Op::Conv { .. }) {
                continue;
            }
            let (Some(g), Some(b), Some(m), Some(v)) = (
                &self.consts[gs],
                &self.consts[bs],
                &self.consts[ms],
                &self.consts[vs],
            ) else {
                continue;
            };
            let Some(w_slot) = self.nodes[ci].inputs.get(1).copied().flatten() else {
                continue;
            };
            let Some(w) = self.consts[w_slot].clone() else {
                continue;
            };
            let cout = w.shape[0];
            if g.data.len() != cout
                || b.data.len() != cout
                || m.data.len() != cout
                || v.data.len() != cout
            {
                continue;
            }
            let per = w.data.len() / cout;
            let old_bias = self.nodes[ci]
                .inputs
                .get(2)
                .copied()
                .flatten()
                .and_then(|s| self.consts[s].as_ref())
                .map(|t| t.data.clone())
                .unwrap_or_else(|| vec![0.0; cout]);
            let mut nw = w.data;
            let mut nb = vec![0.0f32; cout];
            for c in 0..cout {
                let scale = g.data[c] / (v.data[c] + eps).sqrt();
                for x in &mut nw[c * per..(c + 1) * per] {
                    *x *= scale;
                }
                nb[c] = (old_bias[c] - m.data[c]) * scale + b.data[c];
            }
            // fresh slots for the folded constants (weights may be shared)
            let ws = self.n_slots;
            let bsl = self.n_slots + 1;
            self.n_slots += 2;
            self.consts.push(Some(Tensor::new(w.shape.clone(), nw)));
            self.consts.push(Some(Tensor::new(vec![cout], nb)));
            let bn_out = self.nodes[bi].outputs[0];
            let conv = &mut self.nodes[ci];
            conv.inputs.truncate(1);
            conv.inputs.push(Some(ws));
            conv.inputs.push(Some(bsl));
            conv.outputs = vec![bn_out];
            removed[bi] = true;
        }
        let mut i = 0;
        self.nodes.retain(|_| {
            let keep = !removed[i];
            i += 1;
            keep
        });
    }

    fn plan_frees(&mut self) {
        let mut last = vec![usize::MAX; self.n_slots];
        for (i, n) in self.nodes.iter().enumerate() {
            for s in n.inputs.iter().flatten() {
                last[*s] = i;
            }
        }
        let keep: Vec<usize> = self.outputs.iter().map(|o| o.1).collect();
        self.frees = vec![Vec::new(); self.nodes.len()];
        for (s, &i) in last.iter().enumerate() {
            if i != usize::MAX && self.consts[s].is_none() && !keep.contains(&s) {
                self.frees[i].push(s);
            }
        }
    }

    /// Runs the model on one input tensor; returns the graph outputs by name.
    pub fn run(&self, input: Tensor) -> Result<HashMap<String, Tensor>, String> {
        let mut vals: Vec<Option<Tensor>> = vec![None; self.n_slots];
        vals[self.input] = Some(input);
        let profile = std::env::var_os("KADER_NN_PROFILE").is_some();
        for (ni, node) in self.nodes.iter().enumerate() {
            let t0 = profile.then(std::time::Instant::now);
            let get = |k: usize| -> Result<&Tensor, String> {
                let s = node
                    .inputs
                    .get(k)
                    .copied()
                    .flatten()
                    .ok_or_else(|| format!("{:?}: missing input {k}", node.op))?;
                vals[s]
                    .as_ref()
                    .or(self.consts[s].as_ref())
                    .ok_or_else(|| format!("{:?}: input {k} not computed", node.op))
            };
            let opt = |k: usize| -> Option<&Tensor> {
                let s = node.inputs.get(k).copied().flatten()?;
                vals[s].as_ref().or(self.consts[s].as_ref())
            };
            let out = match &node.op {
                Op::Conv {
                    group,
                    stride,
                    pad,
                    dilation,
                } => ops::conv(get(0)?, get(1)?, opt(2), *group, *stride, *pad, *dilation)?,
                Op::BatchNorm { eps } => {
                    ops::batchnorm(get(0)?, get(1)?, get(2)?, get(3)?, get(4)?, *eps)?
                }
                Op::Relu => ops::map(get(0)?, |x| x.max(0.0)),
                Op::Sigmoid => ops::map(get(0)?, |x| 1.0 / (1.0 + (-x).exp())),
                Op::PRelu => ops::prelu(get(0)?, get(1)?)?,
                Op::MaxPool {
                    kernel,
                    stride,
                    pad,
                } => ops::maxpool(get(0)?, *kernel, *stride, *pad)?,
                Op::ResizeNearest => {
                    // inputs: X, roi, scales[, sizes] (opset 11+), or X, scales (Upsample)
                    let x = get(0)?;
                    let scales = if node.inputs.len() == 2 {
                        opt(1)
                    } else {
                        opt(2)
                    }
                    .filter(|t| !t.is_empty());
                    let sizes = opt(3).filter(|t| !t.is_empty());
                    ops::resize_nearest(x, scales, sizes)?
                }
                Op::Add => ops::binary(get(0)?, get(1)?, |a, b| a + b)?,
                Op::Sub => ops::binary(get(0)?, get(1)?, |a, b| a - b)?,
                Op::Mul => ops::binary(get(0)?, get(1)?, |a, b| a * b)?,
                Op::Transpose { perm } => ops::transpose(get(0)?, perm)?,
                Op::Reshape => ops::reshape(get(0)?, get(1)?)?,
                Op::Flatten { axis } => {
                    let x = get(0)?;
                    let a = (*axis).min(x.shape.len());
                    let outer = x.shape[..a].iter().product();
                    Tensor::new(vec![outer, x.len() / outer.max(1)], x.data.clone())
                }
                Op::Gemm {
                    alpha,
                    beta,
                    trans_a,
                    trans_b,
                } => ops::gemm(get(0)?, get(1)?, opt(2), *alpha, *beta, *trans_a, *trans_b)?,
                Op::Identity => get(0)?.clone(),
            };
            if let Some(t0) = t0 {
                eprintln!(
                    "nn {:>8.3} ms {:?} -> {:?}",
                    t0.elapsed().as_secs_f64() * 1e3,
                    node.op,
                    out.shape
                );
            }
            vals[node.outputs[0]] = Some(out);
            for &s in &self.frees[ni] {
                vals[s] = None;
            }
        }
        self.outputs
            .iter()
            .map(|(name, s)| {
                let t = vals[*s]
                    .take()
                    .ok_or_else(|| format!("output {name} not computed"))?;
                Ok((name.clone(), t))
            })
            .collect()
    }
}
