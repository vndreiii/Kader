//! Operator kernels. Plain safe Rust, written so the inner loops vectorise.

use super::Tensor;
use std::sync::atomic::{AtomicUsize, Ordering};

static THREADS: AtomicUsize = AtomicUsize::new(1);

/// Worker threads for large convolutions/GEMMs (default 1).
pub fn set_threads(n: usize) {
    THREADS.store(n.clamp(1, 64), Ordering::Relaxed);
}

fn shape4(t: &Tensor, what: &str) -> Result<[usize; 4], String> {
    match t.shape.as_slice() {
        &[n, c, h, w] => Ok([n, c, h, w]),
        s => Err(format!("{what}: expected NCHW input, got {s:?}")),
    }
}

pub fn map(x: &Tensor, f: impl Fn(f32) -> f32) -> Tensor {
    Tensor::new(x.shape.clone(), x.data.iter().map(|&v| f(v)).collect())
}

/// C[m×n] += A[m×k] · B[k×n] for the columns of one part. Rows of A are
/// taken four at a time so each loaded run of B feeds four accumulators.
#[inline(always)]
fn gemm_part_body(a: &[f32], b: &[f32], rows: &mut [&mut [f32]], k: usize, n: usize, base: usize) {
    const TILE: usize = 256;
    let width = rows.first().map_or(0, |r| r.len());
    let m = rows.len();
    let mut t0 = 0;
    while t0 < width {
        let t1 = (t0 + TILE).min(width);
        let mut i = 0;
        while i + 4 <= m {
            let (r01, r23) = rows[i..i + 4].split_at_mut(2);
            let (r0, r1) = r01.split_at_mut(1);
            let (r2, r3) = r23.split_at_mut(1);
            let (c0, c1, c2, c3) = (
                &mut r0[0][t0..t1],
                &mut r1[0][t0..t1],
                &mut r2[0][t0..t1],
                &mut r3[0][t0..t1],
            );
            for kk in 0..k {
                let (a0, a1, a2, a3) = (
                    a[i * k + kk],
                    a[(i + 1) * k + kk],
                    a[(i + 2) * k + kk],
                    a[(i + 3) * k + kk],
                );
                let bs = &b[kk * n + base + t0..kk * n + base + t1];
                for j in 0..bs.len() {
                    let bv = bs[j];
                    c0[j] += a0 * bv;
                    c1[j] += a1 * bv;
                    c2[j] += a2 * bv;
                    c3[j] += a3 * bv;
                }
            }
            i += 4;
        }
        while i < m {
            let c = &mut rows[i][t0..t1];
            for kk in 0..k {
                let av = a[i * k + kk];
                let bs = &b[kk * n + base + t0..kk * n + base + t1];
                for (cv, &bv) in c.iter_mut().zip(bs) {
                    *cv += av * bv;
                }
            }
            i += 1;
        }
        t0 = t1;
    }
}

#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2,fma")]
unsafe fn gemm_part_avx2(
    a: &[f32],
    b: &[f32],
    rows: &mut [&mut [f32]],
    k: usize,
    n: usize,
    base: usize,
) {
    gemm_part_body(a, b, rows, k, n, base)
}

fn gemm_part(a: &[f32], b: &[f32], rows: &mut [&mut [f32]], k: usize, n: usize, base: usize) {
    #[cfg(target_arch = "x86_64")]
    if std::is_x86_feature_detected!("avx2") && std::is_x86_feature_detected!("fma") {
        // SAFETY: the CPU supports the features the function was compiled
        // for; the body is safe Rust (bounds-checked slices).
        unsafe { gemm_part_avx2(a, b, rows, k, n, base) };
        return;
    }
    gemm_part_body(a, b, rows, k, n, base)
}

/// C[m×n] += A[m×k] · B[k×n], row-major; large products split their
/// columns across the worker threads.
fn gemm_acc(a: &[f32], b: &[f32], c: &mut [f32], m: usize, k: usize, n: usize) {
    if m == 0 || n == 0 {
        return;
    }
    let threads = THREADS.load(Ordering::Relaxed);
    let parts = if m * k * n < (1 << 22) {
        1
    } else {
        threads.min(n.div_ceil(64)).max(1)
    };
    if parts == 1 {
        let mut rows: Vec<&mut [f32]> = c.chunks_mut(n).collect();
        gemm_part(a, b, &mut rows, k, n, 0);
        return;
    }
    let per = n.div_ceil(parts);
    let mut split: Vec<(usize, Vec<&mut [f32]>)> = (0..parts)
        .map(|p| (p * per, Vec::with_capacity(m)))
        .collect();
    for row in c.chunks_mut(n) {
        let mut rest = row;
        for (p, (_, rows)) in split.iter_mut().enumerate() {
            let cols = ((p + 1) * per).min(n) - (p * per).min(n);
            let (head, tail) = rest.split_at_mut(cols);
            rows.push(head);
            rest = tail;
        }
    }
    std::thread::scope(|s| {
        for (base, mut rows) in split {
            if rows.first().is_some_and(|r| !r.is_empty()) {
                s.spawn(move || gemm_part(a, b, &mut rows, k, n, base));
            }
        }
    });
}

pub fn conv(
    x: &Tensor,
    w: &Tensor,
    bias: Option<&Tensor>,
    group: usize,
    stride: [usize; 2],
    pad: [usize; 4],
    dil: [usize; 2],
) -> Result<Tensor, String> {
    let [n, cin, h, wd] = shape4(x, "Conv")?;
    let [cout, cpg, kh, kw] = shape4(w, "Conv weight")?;
    if n != 1 {
        return Err("Conv: batch must be 1".into());
    }
    if group == 0 || cin % group != 0 || cout % group != 0 || cin / group != cpg {
        return Err(format!(
            "Conv: channel/group mismatch (cin {cin}, cpg {cpg}, group {group})"
        ));
    }
    if stride[0] == 0 || stride[1] == 0 {
        return Err("Conv: zero stride".into());
    }
    let ekh = dil[0] * (kh - 1) + 1;
    let ekw = dil[1] * (kw - 1) + 1;
    let (ph, pw) = (h + pad[0] + pad[2], wd + pad[1] + pad[3]);
    if ph < ekh || pw < ekw {
        return Err("Conv: kernel larger than input".into());
    }
    let oh = (ph - ekh) / stride[0] + 1;
    let ow = (pw - ekw) / stride[1] + 1;
    let ohw = oh * ow;
    let mut out = vec![0.0f32; cout * ohw];
    if let Some(b) = bias {
        if b.data.len() != cout {
            return Err("Conv: bias size mismatch".into());
        }
        for (c, chunk) in out.chunks_mut(ohw).enumerate() {
            chunk.fill(b.data[c]);
        }
    }

    let coutpg = cout / group;
    if cpg == 1 && coutpg == 1 {
        // depthwise: one filter per channel, accumulated tap by tap over
        // the output range where that tap is inside the image (no
        // per-pixel bounds checks; stride-1 runs are contiguous)
        for c in 0..cout {
            let src = &x.data[c * h * wd..(c + 1) * h * wd];
            let kern = &w.data[c * kh * kw..(c + 1) * kh * kw];
            let dst = &mut out[c * ohw..(c + 1) * ohw];
            // valid output x range per kx
            let xr: Vec<(usize, usize, isize)> = (0..kw)
                .map(|kx| {
                    let off = (kx * dil[1]) as isize - pad[1] as isize;
                    let lo = if off >= 0 {
                        0
                    } else {
                        ((-off) as usize).div_ceil(stride[1])
                    };
                    let hi = if (wd as isize - 1 - off) < 0 {
                        0
                    } else {
                        ((wd as isize - 1 - off) as usize) / stride[1] + 1
                    };
                    (lo, hi.min(ow), off)
                })
                .collect();
            for oy in 0..oh {
                let drow = &mut dst[oy * ow..(oy + 1) * ow];
                for ky in 0..kh {
                    let iy = (oy * stride[0] + ky * dil[0]) as isize - pad[0] as isize;
                    if iy < 0 || iy >= h as isize {
                        continue;
                    }
                    let srow = &src[iy as usize * wd..(iy as usize + 1) * wd];
                    for (kx, &(lo, hi, off)) in xr.iter().enumerate() {
                        if lo >= hi {
                            continue;
                        }
                        let kv = kern[ky * kw + kx];
                        if stride[1] == 1 {
                            let s0 = (lo as isize + off) as usize;
                            let sr = &srow[s0..s0 + (hi - lo)];
                            for (d, &sv) in drow[lo..hi].iter_mut().zip(sr) {
                                *d += kv * sv;
                            }
                        } else {
                            for (ox, d) in drow[lo..hi].iter_mut().enumerate() {
                                let ix = ((lo + ox) * stride[1]) as isize + off;
                                *d += kv * srow[ix as usize];
                            }
                        }
                    }
                }
            }
        }
        return Ok(Tensor::new(vec![1, cout, oh, ow], out));
    }

    let pointwise = kh == 1 && kw == 1 && stride == [1, 1] && pad == [0; 4];
    let kdim = cpg * kh * kw;
    let mut cols = if pointwise {
        Vec::new()
    } else {
        vec![0.0f32; kdim * ohw]
    };
    for g in 0..group {
        let xg = &x.data[g * cpg * h * wd..(g + 1) * cpg * h * wd];
        let b: &[f32] = if pointwise {
            xg
        } else {
            // im2col: row (ci, ky, kx) holds that tap for every output pixel
            for ci in 0..cpg {
                let src = &xg[ci * h * wd..(ci + 1) * h * wd];
                for ky in 0..kh {
                    for kx in 0..kw {
                        let row = &mut cols[((ci * kh + ky) * kw + kx) * ohw..][..ohw];
                        for oy in 0..oh {
                            let iy = (oy * stride[0] + ky * dil[0]) as isize - pad[0] as isize;
                            let dst = &mut row[oy * ow..(oy + 1) * ow];
                            if iy < 0 || iy >= h as isize {
                                dst.fill(0.0);
                                continue;
                            }
                            let srow = &src[iy as usize * wd..(iy as usize + 1) * wd];
                            for (ox, d) in dst.iter_mut().enumerate() {
                                let ix = (ox * stride[1] + kx * dil[1]) as isize - pad[1] as isize;
                                *d = if ix >= 0 && ix < wd as isize {
                                    srow[ix as usize]
                                } else {
                                    0.0
                                };
                            }
                        }
                    }
                }
            }
            &cols
        };
        let a = &w.data[g * coutpg * kdim..(g + 1) * coutpg * kdim];
        let c = &mut out[g * coutpg * ohw..(g + 1) * coutpg * ohw];
        gemm_acc(a, b, c, coutpg, kdim, ohw);
    }
    Ok(Tensor::new(vec![1, cout, oh, ow], out))
}

fn per_channel(x: &Tensor) -> Result<(usize, usize), String> {
    // (channels, elements per channel) for NCHW or NC tensors with N == 1
    match x.shape.as_slice() {
        &[1, c, h, w] => Ok((c, h * w)),
        &[1, c] => Ok((c, 1)),
        s => Err(format!("expected N=1 NCHW/NC tensor, got {s:?}")),
    }
}

pub fn batchnorm(
    x: &Tensor,
    g: &Tensor,
    b: &Tensor,
    m: &Tensor,
    v: &Tensor,
    eps: f32,
) -> Result<Tensor, String> {
    let (c, per) = per_channel(x)?;
    if [g, b, m, v].iter().any(|t| t.data.len() != c) {
        return Err("BatchNormalization: parameter size mismatch".into());
    }
    let mut out = x.data.clone();
    for ch in 0..c {
        let scale = g.data[ch] / (v.data[ch] + eps).sqrt();
        let shift = b.data[ch] - m.data[ch] * scale;
        for o in &mut out[ch * per..(ch + 1) * per] {
            *o = *o * scale + shift;
        }
    }
    Ok(Tensor::new(x.shape.clone(), out))
}

pub fn prelu(x: &Tensor, slope: &Tensor) -> Result<Tensor, String> {
    let (c, per) = per_channel(x)?;
    let mut out = x.data.clone();
    match slope.data.len() {
        1 => {
            let s = slope.data[0];
            out.iter_mut()
                .for_each(|v| *v = v.max(0.0) + s * v.min(0.0));
        }
        n if n == c => {
            for ch in 0..c {
                let s = slope.data[ch];
                // branchless so it vectorises
                out[ch * per..(ch + 1) * per]
                    .iter_mut()
                    .for_each(|v| *v = v.max(0.0) + s * v.min(0.0));
            }
        }
        _ => return Err("PRelu: slope must be scalar or per-channel".into()),
    }
    Ok(Tensor::new(x.shape.clone(), out))
}

pub fn maxpool(
    x: &Tensor,
    k: [usize; 2],
    s: [usize; 2],
    pad: [usize; 4],
) -> Result<Tensor, String> {
    let [n, c, h, w] = shape4(x, "MaxPool")?;
    if n != 1 || s[0] == 0 || s[1] == 0 {
        return Err("MaxPool: unsupported shape".into());
    }
    let (ph, pw) = (h + pad[0] + pad[2], w + pad[1] + pad[3]);
    if ph < k[0] || pw < k[1] {
        return Err("MaxPool: kernel larger than input".into());
    }
    let oh = (ph - k[0]) / s[0] + 1;
    let ow = (pw - k[1]) / s[1] + 1;
    let mut out = vec![f32::NEG_INFINITY; c * oh * ow];
    for ch in 0..c {
        let src = &x.data[ch * h * w..(ch + 1) * h * w];
        for oy in 0..oh {
            for ox in 0..ow {
                let mut m = f32::NEG_INFINITY;
                for ky in 0..k[0] {
                    let iy = (oy * s[0] + ky) as isize - pad[0] as isize;
                    if iy < 0 || iy >= h as isize {
                        continue;
                    }
                    for kx in 0..k[1] {
                        let ix = (ox * s[1] + kx) as isize - pad[1] as isize;
                        if ix >= 0 && ix < w as isize {
                            m = m.max(src[iy as usize * w + ix as usize]);
                        }
                    }
                }
                out[(ch * oh + oy) * ow + ox] = m;
            }
        }
    }
    Ok(Tensor::new(vec![1, c, oh, ow], out))
}

/// Nearest-neighbour resize, asymmetric coordinates with floor rounding
/// (the mode exported detection necks use for 2× upsampling).
pub fn resize_nearest(
    x: &Tensor,
    scales: Option<&Tensor>,
    sizes: Option<&Tensor>,
) -> Result<Tensor, String> {
    let [n, c, h, w] = shape4(x, "Resize")?;
    let (oh, ow) = if let Some(sz) = sizes {
        match sz.ints.as_slice() {
            [_, _, oh, ow] => (*oh as usize, *ow as usize),
            _ => return Err("Resize: sizes must have 4 entries".into()),
        }
    } else if let Some(sc) = scales {
        match sc.data.as_slice() {
            [sn, sc_, sh, sw] if *sn == 1.0 && *sc_ == 1.0 => (
                (h as f32 * sh).floor() as usize,
                (w as f32 * sw).floor() as usize,
            ),
            _ => return Err("Resize: only spatial scales are supported".into()),
        }
    } else {
        return Err("Resize: needs scales or sizes".into());
    };
    if n != 1 || oh == 0 || ow == 0 {
        return Err("Resize: bad output size".into());
    }
    let mut out = vec![0.0f32; c * oh * ow];
    let ys: Vec<usize> = (0..oh).map(|y| ((y * h) / oh).min(h - 1)).collect();
    let xs: Vec<usize> = (0..ow).map(|x| ((x * w) / ow).min(w - 1)).collect();
    for ch in 0..c {
        let src = &x.data[ch * h * w..(ch + 1) * h * w];
        let dst = &mut out[ch * oh * ow..(ch + 1) * oh * ow];
        for (oy, &iy) in ys.iter().enumerate() {
            for (ox, &ix) in xs.iter().enumerate() {
                dst[oy * ow + ox] = src[iy * w + ix];
            }
        }
    }
    Ok(Tensor::new(vec![1, c, oh, ow], out))
}

/// Element-wise op for equal shapes, or with a single-element operand.
pub fn binary(a: &Tensor, b: &Tensor, f: impl Fn(f32, f32) -> f32) -> Result<Tensor, String> {
    if a.shape == b.shape {
        return Ok(Tensor::new(
            a.shape.clone(),
            a.data.iter().zip(&b.data).map(|(&x, &y)| f(x, y)).collect(),
        ));
    }
    if b.data.len() == 1 {
        let y = b.data[0];
        return Ok(map(a, |x| f(x, y)));
    }
    if a.data.len() == 1 {
        let x = a.data[0];
        return Ok(map(b, |y| f(x, y)));
    }
    Err(format!(
        "broadcast {:?} vs {:?} is not supported",
        a.shape, b.shape
    ))
}

pub fn transpose(x: &Tensor, perm: &[usize]) -> Result<Tensor, String> {
    let r = x.shape.len();
    let perm: Vec<usize> = if perm.is_empty() {
        (0..r).rev().collect()
    } else {
        perm.to_vec()
    };
    if perm.len() != r || {
        let mut s = perm.clone();
        s.sort_unstable();
        s != (0..r).collect::<Vec<_>>()
    } {
        return Err("Transpose: invalid perm".into());
    }
    let out_shape: Vec<usize> = perm.iter().map(|&p| x.shape[p]).collect();
    let mut in_strides = vec![1usize; r];
    for i in (0..r.saturating_sub(1)).rev() {
        in_strides[i] = in_strides[i + 1] * x.shape[i + 1];
    }
    let strides: Vec<usize> = perm.iter().map(|&p| in_strides[p]).collect();
    let total = x.len();
    let mut out = Vec::with_capacity(total);
    let mut idx = vec![0usize; r];
    for _ in 0..total {
        let off: usize = idx.iter().zip(&strides).map(|(i, s)| i * s).sum();
        out.push(x.data[off]);
        for d in (0..r).rev() {
            idx[d] += 1;
            if idx[d] < out_shape[d] {
                break;
            }
            idx[d] = 0;
        }
    }
    Ok(Tensor::new(out_shape, out))
}

pub fn reshape(x: &Tensor, shape: &Tensor) -> Result<Tensor, String> {
    let spec = &shape.ints;
    let mut out: Vec<usize> = Vec::with_capacity(spec.len());
    let mut infer = None;
    for (i, &d) in spec.iter().enumerate() {
        match d {
            -1 if infer.is_none() => {
                infer = Some(i);
                out.push(1);
            }
            0 => out.push(*x.shape.get(i).ok_or("Reshape: 0 past input rank")?),
            d if d > 0 => out.push(d as usize),
            _ => return Err("Reshape: invalid shape".into()),
        }
    }
    let known: usize = out.iter().product();
    if let Some(i) = infer {
        if known == 0 || !x.len().is_multiple_of(known) {
            return Err("Reshape: cannot infer dimension".into());
        }
        out[i] = x.len() / known;
    }
    if out.iter().product::<usize>() != x.len() {
        return Err(format!("Reshape: {:?} -> {:?} changes size", x.shape, out));
    }
    Ok(Tensor::new(out, x.data.clone()))
}

pub fn gemm(
    a: &Tensor,
    b: &Tensor,
    c: Option<&Tensor>,
    alpha: f32,
    beta: f32,
    trans_a: bool,
    trans_b: bool,
) -> Result<Tensor, String> {
    let (&[ar, ac], &[br, bc]) = (a.shape.as_slice(), b.shape.as_slice()) else {
        return Err("Gemm: 2-D inputs expected".into());
    };
    let (m, k) = if trans_a { (ac, ar) } else { (ar, ac) };
    let (k2, n) = if trans_b { (bc, br) } else { (br, bc) };
    if k != k2 {
        return Err("Gemm: inner dimensions differ".into());
    }
    let a_rows: Vec<f32> = if trans_a {
        // materialise Aᵀ so every row is contiguous
        let mut t = vec![0.0f32; m * k];
        for kk in 0..k {
            for i in 0..m {
                t[i * k + kk] = a.data[kk * ac + i];
            }
        }
        t
    } else {
        a.data.clone()
    };
    let mut out = vec![0.0f32; m * n];
    if trans_b {
        // rows of B are contiguous: one dot product per output, eight
        // independent accumulators so the reduction vectorises
        for i in 0..m {
            let ar = &a_rows[i * k..(i + 1) * k];
            for j in 0..n {
                let br = &b.data[j * bc..(j + 1) * bc];
                let mut acc = [0.0f32; 8];
                let (ac8, at) = ar.split_at(k - k % 8);
                let (bc8, bt) = br.split_at(k - k % 8);
                for (x, y) in ac8.chunks_exact(8).zip(bc8.chunks_exact(8)) {
                    for l in 0..8 {
                        acc[l] += x[l] * y[l];
                    }
                }
                let mut sum: f32 = acc.iter().sum();
                for (x, y) in at.iter().zip(bt) {
                    sum += x * y;
                }
                out[i * n + j] = alpha * sum;
            }
        }
    } else {
        gemm_acc(&a_rows, &b.data, &mut out, m, k, n);
        if alpha != 1.0 {
            out.iter_mut().for_each(|v| *v *= alpha);
        }
    }
    if let Some(c) = c {
        let cv = |i: usize, j: usize| match c.data.len() {
            1 => c.data[0],
            l if l == n => c.data[j],
            l if l == m * n => c.data[i * n + j],
            _ => 0.0,
        };
        for i in 0..m {
            for j in 0..n {
                out[i * n + j] += beta * cv(i, j);
            }
        }
    }
    Ok(Tensor::new(vec![m, n], out))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn naive_conv(x: &Tensor, w: &Tensor, group: usize, s: usize, p: usize) -> Vec<f32> {
        let [_, cin, h, wd] = shape4(x, "").unwrap();
        let [cout, cpg, kh, kw] = shape4(w, "").unwrap();
        let oh = (h + 2 * p - kh) / s + 1;
        let ow = (wd + 2 * p - kw) / s + 1;
        let coutpg = cout / group;
        let mut out = vec![0.0; cout * oh * ow];
        for co in 0..cout {
            let g = co / coutpg;
            for oy in 0..oh {
                for ox in 0..ow {
                    let mut acc = 0.0;
                    for ci in 0..cpg {
                        for ky in 0..kh {
                            for kx in 0..kw {
                                let iy = (oy * s + ky) as isize - p as isize;
                                let ix = (ox * s + kx) as isize - p as isize;
                                if iy >= 0 && ix >= 0 && (iy as usize) < h && (ix as usize) < wd {
                                    let c = g * cpg + ci;
                                    acc += x.data[(c * h + iy as usize) * wd + ix as usize]
                                        * w.data[((co * cpg + ci) * kh + ky) * kw + kx];
                                }
                            }
                        }
                    }
                    out[(co * oh + oy) * ow + ox] = acc;
                }
            }
        }
        let _ = cin;
        out
    }

    fn pseudo(n: usize, seed: u32) -> Vec<f32> {
        let mut s = seed;
        (0..n)
            .map(|_| {
                s = s.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
                ((s >> 8) as f32 / (1u32 << 24) as f32) - 0.5
            })
            .collect()
    }

    #[test]
    fn conv_matches_naive() {
        for &(cin, cout, group, k, s, p, threads) in &[
            (3, 8, 1, 3, 2, 1, 1),
            (8, 8, 8, 3, 1, 1, 1),
            (8, 16, 1, 1, 1, 0, 1),
            (4, 4, 2, 3, 1, 1, 1),
            (16, 32, 1, 3, 1, 1, 4),
        ] {
            set_threads(threads);
            let x = Tensor::new(vec![1, cin, 37, 41], pseudo(cin * 37 * 41, 7));
            let w = Tensor::new(
                vec![cout, cin / group, k, k],
                pseudo(cout * (cin / group) * k * k, 11),
            );
            let got = conv(&x, &w, None, group, [s, s], [p; 4], [1, 1]).unwrap();
            let want = naive_conv(&x, &w, group, s, p);
            assert_eq!(got.data.len(), want.len());
            for (a, b) in got.data.iter().zip(&want) {
                assert!((a - b).abs() < 1e-4, "{a} vs {b}");
            }
        }
        set_threads(1);
    }

    #[test]
    fn transpose_reshape_resize() {
        let x = Tensor::new(vec![1, 2, 2, 3], (0..12).map(|v| v as f32).collect());
        let t = transpose(&x, &[0, 2, 3, 1]).unwrap();
        assert_eq!(t.shape, [1, 2, 3, 2]);
        assert_eq!(&t.data[..4], &[0.0, 6.0, 1.0, 7.0]);
        let shape = Tensor {
            shape: vec![3],
            data: vec![],
            ints: vec![1, -1, 2],
        };
        assert_eq!(reshape(&t, &shape).unwrap().shape, [1, 6, 2]);
        let scales = Tensor::new(vec![4], vec![1.0, 1.0, 2.0, 2.0]);
        let r = resize_nearest(&x, Some(&scales), None).unwrap();
        assert_eq!(r.shape, [1, 2, 4, 6]);
        assert_eq!(&r.data[..6], &[0.0, 0.0, 1.0, 1.0, 2.0, 2.0]);
    }
}
