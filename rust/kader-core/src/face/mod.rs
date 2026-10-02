//! Faces: detection (YuNet), alignment, recognition embeddings (SFace) and
//! clustering into people. Models are ONNX files run by [`crate::nn`].
//!
//! Images come in as packed 8-bit RGB with an explicit row stride. All
//! coordinates returned are in the input image's pixel space.

// Numeric kernels index several parallel arrays; index loops read clearer.
#![allow(clippy::needless_range_loop)]

pub mod cluster;
mod image;

use crate::nn::{Model, Tensor};
pub use image::RgbImage;

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Face {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub score: f32,
    /// right eye, left eye, nose tip, right / left mouth corner (x, y)
    pub landmarks: [f32; 10],
}

pub struct Detector {
    model: Model,
}

/// Length of a face embedding.
pub const EMBED_DIM: usize = 128;

/// Cosine similarity at or above which two SFace embeddings are taken to be
/// the same person (the model's published operating point).
pub const SAME_PERSON: f32 = 0.363;

impl Detector {
    pub fn load(onnx: &[u8]) -> Result<Self, String> {
        Ok(Detector {
            model: Model::load(onnx)?,
        })
    }

    /// Finds faces. The image is scaled so its longer side is at most
    /// `max_side` (detection cost is proportional to the pixel count).
    pub fn detect(
        &self,
        img: &RgbImage,
        max_side: usize,
        score_thr: f32,
        nms_thr: f32,
    ) -> Result<Vec<Face>, String> {
        if img.width == 0 || img.height == 0 {
            return Ok(Vec::new());
        }
        let scale = (max_side as f32 / img.width.max(img.height) as f32).min(1.0);
        let w = ((img.width as f32 * scale).round() as usize).max(1);
        let h = ((img.height as f32 * scale).round() as usize).max(1);
        // pad to a multiple of 32 (the coarsest feature stride)
        let pw = w.div_ceil(32) * 32;
        let ph = h.div_ceil(32) * 32;
        let small = img.resized(w, h);
        // BGR planes, raw 0..255 (the model was trained on OpenCV blobs)
        let mut data = vec![0.0f32; 3 * ph * pw];
        for y in 0..h {
            let row = small.row(y);
            for x in 0..w {
                let p = &row[x * 3..x * 3 + 3];
                data[y * pw + x] = f32::from(p[2]);
                data[ph * pw + y * pw + x] = f32::from(p[1]);
                data[2 * ph * pw + y * pw + x] = f32::from(p[0]);
            }
        }
        let out = self.model.run(Tensor::new(vec![1, 3, ph, pw], data))?;
        let get = |name: &str| {
            out.get(name)
                .map(|t| t.data.as_slice())
                .ok_or_else(|| format!("YuNet output {name} missing"))
        };

        let mut faces = Vec::new();
        for stride in [8usize, 16, 32] {
            let (cls, obj, bbox, kps) = (
                get(&format!("cls_{stride}"))?,
                get(&format!("obj_{stride}"))?,
                get(&format!("bbox_{stride}"))?,
                get(&format!("kps_{stride}"))?,
            );
            let cols = pw / stride;
            let rows = ph / stride;
            let n = rows * cols;
            if cls.len() < n || obj.len() < n || bbox.len() < n * 4 || kps.len() < n * 10 {
                return Err("YuNet output size mismatch".into());
            }
            let s = stride as f32;
            for r in 0..rows {
                for c in 0..cols {
                    let i = r * cols + c;
                    let score = (cls[i].clamp(0.0, 1.0) * obj[i].clamp(0.0, 1.0)).sqrt();
                    if score < score_thr {
                        continue;
                    }
                    let b = &bbox[i * 4..i * 4 + 4];
                    let cx = (c as f32 + b[0]) * s;
                    let cy = (r as f32 + b[1]) * s;
                    let bw = b[2].exp() * s;
                    let bh = b[3].exp() * s;
                    let mut lm = [0.0f32; 10];
                    for k in 0..5 {
                        lm[2 * k] = (kps[i * 10 + 2 * k] + c as f32) * s / scale;
                        lm[2 * k + 1] = (kps[i * 10 + 2 * k + 1] + r as f32) * s / scale;
                    }
                    faces.push(Face {
                        x: (cx - bw / 2.0) / scale,
                        y: (cy - bh / 2.0) / scale,
                        w: bw / scale,
                        h: bh / scale,
                        score,
                        landmarks: lm,
                    });
                }
            }
        }
        Ok(nms(faces, nms_thr))
    }
}

fn iou(a: &Face, b: &Face) -> f32 {
    let x1 = a.x.max(b.x);
    let y1 = a.y.max(b.y);
    let x2 = (a.x + a.w).min(b.x + b.w);
    let y2 = (a.y + a.h).min(b.y + b.h);
    let inter = (x2 - x1).max(0.0) * (y2 - y1).max(0.0);
    let uni = a.w * a.h + b.w * b.h - inter;
    if uni <= 0.0 {
        0.0
    } else {
        inter / uni
    }
}

fn nms(mut faces: Vec<Face>, thr: f32) -> Vec<Face> {
    faces.sort_by(|a, b| b.score.total_cmp(&a.score));
    let mut keep: Vec<Face> = Vec::new();
    for f in faces {
        if keep.iter().all(|k| iou(k, &f) <= thr) {
            keep.push(f);
        }
    }
    keep
}

/// Where the five landmarks sit in the 112×112 crop SFace was trained on.
const TEMPLATE: [[f32; 2]; 5] = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
];

/// Least-squares similarity transform (Umeyama) mapping `src` onto `dst`;
/// returns the 2×3 matrix [a -b tx; b a ty].
fn similarity(src: &[[f32; 2]; 5], dst: &[[f32; 2]; 5]) -> [f32; 6] {
    let n = 5.0f64;
    let mean = |p: &[[f32; 2]; 5]| {
        let (mut x, mut y) = (0.0f64, 0.0f64);
        for q in p {
            x += f64::from(q[0]);
            y += f64::from(q[1]);
        }
        (x / n, y / n)
    };
    let (sx, sy) = mean(src);
    let (dx, dy) = mean(dst);
    let (mut sxx, mut sxy_a, mut sxy_b) = (0.0f64, 0.0f64, 0.0f64);
    for (s, d) in src.iter().zip(dst) {
        let (ux, uy) = (f64::from(s[0]) - sx, f64::from(s[1]) - sy);
        let (vx, vy) = (f64::from(d[0]) - dx, f64::from(d[1]) - dy);
        sxx += ux * ux + uy * uy;
        sxy_a += ux * vx + uy * vy;
        sxy_b += ux * vy - uy * vx;
    }
    if sxx < 1e-9 {
        return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
    }
    let a = sxy_a / sxx;
    let b = sxy_b / sxx;
    let tx = dx - (a * sx - b * sy);
    let ty = dy - (b * sx + a * sy);
    [
        a as f32, -b as f32, tx as f32, b as f32, a as f32, ty as f32,
    ]
}

/// The 112×112 aligned face crop SFace expects.
pub fn align(img: &RgbImage, face: &Face) -> RgbImage {
    let mut src = [[0.0f32; 2]; 5];
    for (k, p) in src.iter_mut().enumerate() {
        *p = [face.landmarks[2 * k], face.landmarks[2 * k + 1]];
    }
    let m = similarity(&src, &TEMPLATE);
    img.warp_affine_inverse(&m, 112, 112)
}

pub struct Recognizer {
    model: Model,
}

impl Recognizer {
    pub fn load(onnx: &[u8]) -> Result<Self, String> {
        Ok(Recognizer {
            model: Model::load(onnx)?,
        })
    }

    /// L2-normalised embedding of an aligned 112×112 crop.
    pub fn embed(&self, aligned: &RgbImage) -> Result<[f32; EMBED_DIM], String> {
        if aligned.width != 112 || aligned.height != 112 {
            return Err("SFace needs a 112x112 aligned crop".into());
        }
        // RGB planes, raw 0..255 (the graph normalises itself)
        let mut data = vec![0.0f32; 3 * 112 * 112];
        for y in 0..112 {
            let row = aligned.row(y);
            for x in 0..112 {
                for c in 0..3 {
                    data[c * 112 * 112 + y * 112 + x] = f32::from(row[x * 3 + c]);
                }
            }
        }
        let out = self.model.run(Tensor::new(vec![1, 3, 112, 112], data))?;
        let t = out.into_values().next().ok_or("SFace produced no output")?;
        if t.data.len() != EMBED_DIM {
            return Err(format!("SFace output has {} values", t.data.len()));
        }
        let norm = t.data.iter().map(|v| v * v).sum::<f32>().sqrt().max(1e-12);
        let mut e = [0.0f32; EMBED_DIM];
        for (o, v) in e.iter_mut().zip(&t.data) {
            *o = v / norm;
        }
        Ok(e)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn similarity_recovers_known_transform() {
        // dst = rotate 30°, scale 1.5, translate (10, -4)
        let (c, s) = (
            1.5f32 * 30f32.to_radians().cos(),
            1.5f32 * 30f32.to_radians().sin(),
        );
        let src = [[1.0, 2.0], [5.0, 1.0], [3.0, 4.0], [0.0, 7.0], [6.0, 6.0]];
        let mut dst = [[0.0f32; 2]; 5];
        for (d, p) in dst.iter_mut().zip(&src) {
            *d = [c * p[0] - s * p[1] + 10.0, s * p[0] + c * p[1] - 4.0];
        }
        let m = similarity(&src, &dst);
        for (want, got) in [c, -s, 10.0, s, c, -4.0].iter().zip(&m) {
            assert!((want - got).abs() < 1e-4, "{want} vs {got}");
        }
    }

    #[test]
    fn nms_drops_overlaps() {
        let f = |x: f32, score: f32| Face {
            x,
            y: 0.0,
            w: 10.0,
            h: 10.0,
            score,
            landmarks: [0.0; 10],
        };
        let kept = nms(vec![f(0.0, 0.9), f(1.0, 0.8), f(30.0, 0.7)], 0.3);
        assert_eq!(kept.len(), 2);
        assert_eq!(kept[0].score, 0.9);
    }
}
