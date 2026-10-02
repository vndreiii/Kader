//! Dominant colour of a photo, for "colour" groups in search.
//!
//! Pixels (sampled on a ≤64×64 grid) are sorted into named hue buckets in
//! HSV space. A photo's colour is its largest chromatic bucket when that
//! covers enough of the frame, otherwise "monochrome" buckets (black, white,
//! gray) when those dominate. The palette is the mean colour of the five
//! largest buckets — what the bucket looks like in this particular photo.

use crate::face::RgbImage;

pub const BUCKETS: [&str; 13] = [
    "none", "red", "orange", "yellow", "green", "teal", "blue", "purple", "pink", "brown", "black",
    "white", "gray",
];

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct ColorStats {
    pub average: [u8; 3],
    /// index into [`BUCKETS`]; 0 when no colour dominates
    pub bucket: u8,
    pub bucket_frac: f32,
    pub palette: [[u8; 3]; 5],
    pub palette_frac: [f32; 5],
}

fn bucket_of(r: f32, g: f32, b: f32) -> usize {
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let v = max;
    let s = if max > 0.0 { (max - min) / max } else { 0.0 };
    if v < 0.16 {
        return 10; // black
    }
    if s < 0.16 || (max - min) < 0.06 {
        return if v > 0.86 { 11 } else { 12 }; // white / gray
    }
    let d = max - min;
    let mut h = if max == r {
        60.0 * (((g - b) / d) % 6.0)
    } else if max == g {
        60.0 * ((b - r) / d + 2.0)
    } else {
        60.0 * ((r - g) / d + 4.0)
    };
    if h < 0.0 {
        h += 360.0;
    }
    // dark, moderately saturated reds/oranges read as brown
    if !(45.0..345.0).contains(&h) && v < 0.58 && s < 0.85 {
        return 9;
    }
    match h {
        h if !(15.0..345.0).contains(&h) => 1,
        h if h < 40.0 => 2,
        h if h < 68.0 => 3,
        h if h < 160.0 => 4,
        h if h < 195.0 => 5,
        h if h < 255.0 => 6,
        h if h < 290.0 => 7,
        _ => 8,
    }
}

pub fn analyze(img: &RgbImage) -> ColorStats {
    let mut st = ColorStats::default();
    if img.width == 0 || img.height == 0 {
        return st;
    }
    let step_x = img.width.div_ceil(64).max(1);
    let step_y = img.height.div_ceil(64).max(1);
    let mut count = [0u32; 13];
    let mut sums = [[0u64; 3]; 13];
    let mut total = 0u32;
    let mut avg = [0u64; 3];
    for y in (0..img.height).step_by(step_y) {
        let row = img.row(y);
        for x in (0..img.width).step_by(step_x) {
            let p = &row[x * 3..x * 3 + 3];
            let k = bucket_of(
                f32::from(p[0]) / 255.0,
                f32::from(p[1]) / 255.0,
                f32::from(p[2]) / 255.0,
            );
            count[k] += 1;
            for c in 0..3 {
                sums[k][c] += u64::from(p[c]);
                avg[c] += u64::from(p[c]);
            }
            total += 1;
        }
    }
    let t = f64::from(total.max(1));
    st.average = avg.map(|v| (v as f64 / t).round() as u8);
    let frac = |k: usize| count[k] as f32 / total.max(1) as f32;

    let mut chroma: Vec<usize> = (1..=9).collect();
    chroma.sort_by(|&a, &b| count[b].cmp(&count[a]));
    let (best_chroma, second) = (chroma[0], chroma[1]);
    let best_neutral = (10..=12)
        .max_by(|&a, &b| count[a].cmp(&count[b]))
        .unwrap_or(12);
    // brown is common in ordinary scenes; ask for more of it
    let chroma_need = if best_chroma == 9 { 0.45 } else { 0.28 };
    // …and a clear lead: a photo split between colours names none of them
    if frac(best_chroma) >= chroma_need && frac(best_chroma) >= 1.5 * frac(second) {
        st.bucket = best_chroma as u8;
        st.bucket_frac = frac(best_chroma);
    } else if frac(best_neutral) >= 0.55 {
        st.bucket = best_neutral as u8;
        st.bucket_frac = frac(best_neutral);
    }

    let mut order: Vec<usize> = (1..13).filter(|&k| count[k] > 0).collect();
    order.sort_by(|&a, &b| count[b].cmp(&count[a]));
    for (i, &k) in order.iter().take(5).enumerate() {
        let n = u64::from(count[k]);
        st.palette[i] = sums[k].map(|v| (v / n) as u8);
        st.palette_frac[i] = frac(k);
    }
    st
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(rgb: [u8; 3]) -> RgbImage {
        let mut img = RgbImage::new(20, 10);
        for p in img.data.chunks_exact_mut(3) {
            p.copy_from_slice(&rgb);
        }
        img
    }

    #[test]
    fn names_obvious_colours() {
        for (rgb, name) in [
            ([230, 30, 30], "red"),
            ([250, 140, 20], "orange"),
            ([240, 220, 40], "yellow"),
            ([40, 170, 60], "green"),
            ([30, 90, 220], "blue"),
            ([130, 40, 200], "purple"),
            ([240, 110, 190], "pink"),
            ([110, 70, 40], "brown"),
            ([8, 8, 10], "black"),
            ([250, 250, 250], "white"),
            ([128, 128, 128], "gray"),
        ] {
            let s = analyze(&solid(rgb));
            assert_eq!(BUCKETS[s.bucket as usize], name, "{rgb:?}");
            assert_eq!(s.palette[0], rgb);
            assert!((s.palette_frac[0] - 1.0).abs() < 1e-6);
        }
        // an image split evenly between colours names none of them
        let mut img = RgbImage::new(9, 1);
        for (i, p) in img.data.chunks_exact_mut(3).enumerate() {
            p.copy_from_slice(&[[230, 30, 30], [30, 90, 220], [40, 170, 60]][i % 3]);
        }
        assert_eq!(analyze(&img).bucket, 0);
    }
}
