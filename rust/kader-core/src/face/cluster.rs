//! Grouping face embeddings into people.
//!
//! Greedy centroid clustering: faces confirmed by the user seed their
//! person's cluster; every other face (in the caller's order — best quality
//! first) joins the most similar cluster centroid if it is at least
//! `threshold` similar, or starts a new cluster. A final pass merges clusters
//! whose centroids ended up within the threshold of each other, unless both
//! are distinct confirmed people.

use super::EMBED_DIM;

pub struct Input<'a> {
    pub embeddings: &'a [[f32; EMBED_DIM]],
    /// confirmed person id per face, or -1
    pub fixed: &'a [i64],
    /// person id this face must not join (the user removed it), or -1
    pub exclude: &'a [i64],
    pub threshold: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Output {
    /// cluster index per face
    pub labels: Vec<usize>,
    /// confirmed person id per cluster, or -1 for a new, unnamed group
    pub cluster_person: Vec<i64>,
}

struct Cluster {
    sum: [f32; EMBED_DIM],
    person: i64,
    alive: bool,
}

impl Cluster {
    fn centroid(&self) -> [f32; EMBED_DIM] {
        let n = self
            .sum
            .iter()
            .map(|v| v * v)
            .sum::<f32>()
            .sqrt()
            .max(1e-12);
        self.sum.map(|v| v / n)
    }
}

fn dot(a: &[f32; EMBED_DIM], b: &[f32; EMBED_DIM]) -> f32 {
    a.iter().zip(b).map(|(x, y)| x * y).sum()
}

pub fn cluster(inp: &Input<'_>) -> Output {
    let n = inp.embeddings.len();
    let fixed = |i: usize| inp.fixed.get(i).copied().unwrap_or(-1);
    let exclude = |i: usize| inp.exclude.get(i).copied().unwrap_or(-1);
    let mut clusters: Vec<Cluster> = Vec::new();
    let mut labels = vec![usize::MAX; n];

    // 1. confirmed faces seed their person's cluster
    for i in 0..n {
        let p = fixed(i);
        if p < 0 {
            continue;
        }
        let ci = match clusters.iter().position(|c| c.person == p) {
            Some(ci) => ci,
            None => {
                clusters.push(Cluster {
                    sum: [0.0; EMBED_DIM],
                    person: p,
                    alive: true,
                });
                clusters.len() - 1
            }
        };
        for (s, v) in clusters[ci].sum.iter_mut().zip(&inp.embeddings[i]) {
            *s += v;
        }
        labels[i] = ci;
    }

    // 2. everyone else joins the nearest centroid or starts a cluster
    let mut centroids: Vec<[f32; EMBED_DIM]> = clusters.iter().map(Cluster::centroid).collect();
    for i in 0..n {
        if labels[i] != usize::MAX {
            continue;
        }
        let e = &inp.embeddings[i];
        let ex = exclude(i);
        let best = centroids
            .iter()
            .enumerate()
            .filter(|(ci, _)| ex < 0 || clusters[*ci].person != ex)
            .map(|(ci, c)| (ci, dot(e, c)))
            .max_by(|a, b| a.1.total_cmp(&b.1));
        let ci = match best {
            Some((ci, sim)) if sim >= inp.threshold => ci,
            _ => {
                clusters.push(Cluster {
                    sum: [0.0; EMBED_DIM],
                    person: -1,
                    alive: true,
                });
                centroids.push([0.0; EMBED_DIM]);
                clusters.len() - 1
            }
        };
        for (s, v) in clusters[ci].sum.iter_mut().zip(e) {
            *s += v;
        }
        centroids[ci] = clusters[ci].centroid();
        labels[i] = ci;
    }

    // 3. merge clusters that converged onto the same person
    let mut redirect: Vec<usize> = (0..clusters.len()).collect();
    let mut blocked_pairs: std::collections::HashSet<(usize, usize)> = Default::default();
    loop {
        let mut best: Option<(usize, usize, f32)> = None;
        for a in 0..clusters.len() {
            if !clusters[a].alive {
                continue;
            }
            for b in a + 1..clusters.len() {
                if !clusters[b].alive
                    || (clusters[a].person >= 0 && clusters[b].person >= 0)
                    || blocked_pairs.contains(&(a, b))
                {
                    continue;
                }
                let s = dot(&centroids[a], &centroids[b]);
                if s >= inp.threshold && best.is_none_or(|(_, _, bs)| s > bs) {
                    best = Some((a, b, s));
                }
            }
        }
        let Some((a, b, _)) = best else { break };
        // keep the confirmed one (if any) as the survivor
        let (keep, gone) = if clusters[b].person >= 0 {
            (b, a)
        } else {
            (a, b)
        };
        // a face excluded from the survivor's person blocks the merge
        let blocked = clusters[keep].person >= 0
            && (0..n).any(|i| redirect[labels[i]] == gone && exclude(i) == clusters[keep].person);
        if blocked {
            blocked_pairs.insert((a, b));
            continue;
        }
        let gsum = clusters[gone].sum;
        for (s, v) in clusters[keep].sum.iter_mut().zip(&gsum) {
            *s += v;
        }
        clusters[gone].alive = false;
        centroids[keep] = clusters[keep].centroid();
        for r in redirect.iter_mut() {
            if *r == gone {
                *r = keep;
            }
        }
    }

    // compact cluster indices
    let mut remap = vec![usize::MAX; clusters.len()];
    let mut cluster_person = Vec::new();
    for (ci, c) in clusters.iter().enumerate() {
        if c.alive {
            remap[ci] = cluster_person.len();
            cluster_person.push(c.person);
        }
    }
    let labels = labels.iter().map(|&l| remap[redirect[l]]).collect();
    Output {
        labels,
        cluster_person,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn unit(dir: usize, noise: f32) -> [f32; EMBED_DIM] {
        let mut v = [0.0f32; EMBED_DIM];
        v[dir] = 1.0;
        v[(dir + 1) % EMBED_DIM] = noise;
        let n = (1.0 + noise * noise).sqrt();
        v.map(|x| x / n)
    }

    #[test]
    fn groups_people_and_respects_user_edits() {
        let e = [
            unit(0, 0.0),
            unit(0, 0.2),
            unit(5, 0.0),
            unit(5, 0.1),
            unit(9, 0.0),
        ];
        let out = cluster(&Input {
            embeddings: &e,
            fixed: &[-1; 5],
            exclude: &[-1; 5],
            threshold: 0.363,
        });
        assert_eq!(out.labels[0], out.labels[1]);
        assert_eq!(out.labels[2], out.labels[3]);
        assert_ne!(out.labels[0], out.labels[2]);
        assert_eq!(out.cluster_person.len(), 3);

        // face 1 confirmed as person 7; face 0 removed from person 7
        let out = cluster(&Input {
            embeddings: &e,
            fixed: &[-1, 7, -1, -1, -1],
            exclude: &[7, -1, -1, -1, -1],
            threshold: 0.363,
        });
        let p7 = out.labels[1];
        assert_eq!(out.cluster_person[p7], 7);
        assert_ne!(out.labels[0], p7);
    }
}
