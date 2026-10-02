//! Photo-location pins and their zoom-dependent clustering.

use super::math::{add, dot, normalize, scale, V3};

#[derive(Debug, Clone, Copy)]
pub struct PinInput {
    pub pos: V3,
    pub weight: u32,
}

#[derive(Debug, Clone)]
pub struct Cluster {
    pub pos: V3,
    /// Sum of member weights (photo count).
    pub weight: u32,
    /// Heaviest member — supplies the thumbnail.
    pub lead: u32,
    pub members: Vec<u32>,
}

#[derive(Default)]
pub struct Pins {
    inputs: Vec<PinInput>,
    pub clusters: Vec<Cluster>,
    clustered_at: f64,
    /// Bumped whenever cluster membership changes (UI models reset on it).
    pub epoch: u32,
}

impl Pins {
    pub fn set(&mut self, inputs: Vec<PinInput>) {
        self.inputs = inputs;
        self.clustered_at = 0.0;
    }

    pub fn is_empty(&self) -> bool {
        self.inputs.is_empty()
    }

    /// Re-cluster when the globe radius moved by more than ~7 % since the last
    /// clustering. `merge_px` is the screen distance below which pins merge.
    pub fn update(&mut self, radius: f64, merge_px: f64) {
        if self.clustered_at > 0.0 && (radius / self.clustered_at).ln().abs() < 0.07 {
            return;
        }
        self.clustered_at = radius;
        let cos_thr = (merge_px / radius.max(1.0)).min(std::f64::consts::PI).cos();

        let mut order: Vec<u32> = (0..self.inputs.len() as u32).collect();
        order.sort_by(|&a, &b| {
            self.inputs[b as usize]
                .weight
                .cmp(&self.inputs[a as usize].weight)
        });

        let mut clusters: Vec<Cluster> = Vec::new();
        let mut sums: Vec<V3> = Vec::new();
        for i in order {
            let p = self.inputs[i as usize];
            let w = p.weight.max(1);
            match clusters.iter().position(|c| dot(c.pos, p.pos) >= cos_thr) {
                Some(ci) => {
                    let c = &mut clusters[ci];
                    c.weight += w;
                    c.members.push(i);
                    sums[ci] = add(sums[ci], scale(p.pos, f64::from(w)));
                    c.pos = normalize(sums[ci]);
                }
                None => {
                    sums.push(scale(p.pos, f64::from(w)));
                    clusters.push(Cluster {
                        pos: p.pos,
                        weight: w,
                        lead: i,
                        members: vec![i],
                    });
                }
            }
        }

        let changed = clusters.len() != self.clusters.len()
            || clusters
                .iter()
                .zip(&self.clusters)
                .any(|(a, b)| a.members != b.members);
        self.clusters = clusters;
        if changed {
            self.epoch = self.epoch.wrapping_add(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::math::from_lat_lon;

    fn pin(lat: f64, lon: f64, w: u32) -> PinInput {
        PinInput {
            pos: from_lat_lon(lat.to_radians(), lon.to_radians()),
            weight: w,
        }
    }

    #[test]
    fn merges_when_zoomed_out_and_splits_when_zoomed_in() {
        let mut p = Pins::default();
        // Paris + Versailles (~17 km apart) and Tokyo
        p.set(vec![
            pin(48.85, 2.35, 10),
            pin(48.80, 2.13, 3),
            pin(35.68, 139.69, 5),
        ]);
        p.update(300.0, 40.0);
        assert_eq!(p.clusters.len(), 2);
        assert_eq!(p.clusters[0].weight, 13);
        assert_eq!(p.clusters[0].lead, 0);
        let e = p.epoch;
        p.update(100_000.0, 40.0);
        assert_eq!(p.clusters.len(), 3);
        assert_ne!(p.epoch, e);
    }
}
