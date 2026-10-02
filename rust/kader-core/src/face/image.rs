//! Minimal packed-RGB image with resampling and affine warping.

#[derive(Clone, Debug)]
pub struct RgbImage {
    pub width: usize,
    pub height: usize,
    /// packed rows, `width * 3` bytes each
    pub data: Vec<u8>,
}

impl RgbImage {
    pub fn new(width: usize, height: usize) -> Self {
        RgbImage {
            width,
            height,
            data: vec![0; width * height * 3],
        }
    }

    /// Copies an RGB buffer whose rows are `stride` bytes apart.
    pub fn from_strided(src: &[u8], width: usize, height: usize, stride: usize) -> Option<Self> {
        let row = width.checked_mul(3)?;
        if stride < row
            || src.len()
                < stride
                    .checked_mul(height.checked_sub(1)?)?
                    .checked_add(row)?
        {
            return None;
        }
        let mut img = RgbImage::new(width, height);
        for y in 0..height {
            img.data[y * row..(y + 1) * row].copy_from_slice(&src[y * stride..y * stride + row]);
        }
        Some(img)
    }

    #[inline]
    pub fn row(&self, y: usize) -> &[u8] {
        &self.data[y * self.width * 3..(y + 1) * self.width * 3]
    }

    #[inline]
    fn px(&self, x: usize, y: usize) -> [f32; 3] {
        let i = (y * self.width + x) * 3;
        [
            f32::from(self.data[i]),
            f32::from(self.data[i + 1]),
            f32::from(self.data[i + 2]),
        ]
    }

    fn bilinear(&self, fx: f32, fy: f32) -> Option<[f32; 3]> {
        if !(fx > -1.0 && fy > -1.0 && fx < self.width as f32 && fy < self.height as f32) {
            return None;
        }
        let x0 = fx.floor();
        let y0 = fy.floor();
        let (ax, ay) = (fx - x0, fy - y0);
        let (x0, y0) = (x0 as isize, y0 as isize);
        let sample = |x: isize, y: isize| -> [f32; 3] {
            if x < 0 || y < 0 || x >= self.width as isize || y >= self.height as isize {
                [0.0; 3] // constant black border, like OpenCV's warpAffine
            } else {
                self.px(x as usize, y as usize)
            }
        };
        let (p00, p10, p01, p11) = (
            sample(x0, y0),
            sample(x0 + 1, y0),
            sample(x0, y0 + 1),
            sample(x0 + 1, y0 + 1),
        );
        let mut out = [0.0f32; 3];
        for c in 0..3 {
            let top = p00[c] + (p10[c] - p00[c]) * ax;
            let bot = p01[c] + (p11[c] - p01[c]) * ax;
            out[c] = top + (bot - top) * ay;
        }
        Some(out)
    }

    /// Resampled copy: box-averaging when shrinking (no aliasing), bilinear
    /// when enlarging.
    pub fn resized(&self, w: usize, h: usize) -> RgbImage {
        if w == self.width && h == self.height {
            return self.clone();
        }
        let mut out = RgbImage::new(w, h);
        if w == 0 || h == 0 || self.width == 0 || self.height == 0 {
            return out;
        }
        let sx = self.width as f32 / w as f32;
        let sy = self.height as f32 / h as f32;
        for y in 0..h {
            for x in 0..w {
                let px = if sx > 1.0 || sy > 1.0 {
                    let x0 = (x as f32 * sx) as usize;
                    let y0 = (y as f32 * sy) as usize;
                    let x1 = (((x + 1) as f32 * sx).ceil() as usize).clamp(x0 + 1, self.width);
                    let y1 = (((y + 1) as f32 * sy).ceil() as usize).clamp(y0 + 1, self.height);
                    let mut acc = [0.0f32; 3];
                    for yy in y0..y1 {
                        for xx in x0..x1 {
                            let p = self.px(xx, yy);
                            for c in 0..3 {
                                acc[c] += p[c];
                            }
                        }
                    }
                    let n = ((x1 - x0) * (y1 - y0)) as f32;
                    acc.map(|v| v / n)
                } else {
                    let fx = ((x as f32 + 0.5) * sx - 0.5).clamp(0.0, (self.width - 1) as f32);
                    let fy = ((y as f32 + 0.5) * sy - 0.5).clamp(0.0, (self.height - 1) as f32);
                    self.bilinear(fx, fy).unwrap_or([0.0; 3])
                };
                let i = (y * w + x) * 3;
                for c in 0..3 {
                    out.data[i + c] = px[c].round().clamp(0.0, 255.0) as u8;
                }
            }
        }
        out
    }

    /// Output pixel (x, y) takes the input at M⁻¹·(x, y), where `m` is the
    /// forward 2×3 affine map from this image into the output.
    pub fn warp_affine_inverse(&self, m: &[f32; 6], w: usize, h: usize) -> RgbImage {
        let mut out = RgbImage::new(w, h);
        let det = m[0] * m[4] - m[1] * m[3];
        if det.abs() < 1e-12 {
            return out;
        }
        let ia = m[4] / det;
        let ib = -m[1] / det;
        let ic = -m[3] / det;
        let id = m[0] / det;
        let itx = -(ia * m[2] + ib * m[5]);
        let ity = -(ic * m[2] + id * m[5]);
        for y in 0..h {
            for x in 0..w {
                let (fx, fy) = (x as f32, y as f32);
                let sx = ia * fx + ib * fy + itx;
                let sy = ic * fx + id * fy + ity;
                if let Some(p) = self.bilinear(sx, sy) {
                    let i = (y * w + x) * 3;
                    for c in 0..3 {
                        out.data[i + c] = p[c].round().clamp(0.0, 255.0) as u8;
                    }
                }
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strided_resize_warp() {
        let src: Vec<u8> = (0..(4 * 8)).map(|v| v as u8).collect(); // 2x4 px, stride 8 (2 pad)
        let img = RgbImage::from_strided(&src, 2, 4, 8).unwrap();
        assert_eq!(img.row(1), &src[8..14]);
        assert!(RgbImage::from_strided(&src, 3, 4, 8).is_none());
        let flat = RgbImage {
            width: 4,
            height: 4,
            data: vec![100; 48],
        };
        assert!(flat.resized(2, 2).data.iter().all(|&v| v == 100));
        assert!(flat.resized(8, 8).data.iter().all(|&v| v == 100));
        // identity warp keeps the image
        let w = flat.warp_affine_inverse(&[1.0, 0.0, 0.0, 0.0, 1.0, 0.0], 4, 4);
        assert_eq!(w.data, flat.data);
    }
}
