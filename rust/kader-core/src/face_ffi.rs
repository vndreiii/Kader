//! C ABI for faces, clustering and colour analysis (see `include/kader_core.h`).
//!
//! Handles are opaque boxes; every pointer argument is checked for null and
//! every buffer length is validated before a slice is formed.

use crate::color;
use crate::face::{self, cluster, Detector, Face, Recognizer, RgbImage, EMBED_DIM};
use std::ffi::c_char;

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct KfFace {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub score: f32,
    pub landmarks: [f32; 10],
}

impl From<Face> for KfFace {
    fn from(f: Face) -> Self {
        KfFace {
            x: f.x,
            y: f.y,
            w: f.w,
            h: f.h,
            score: f.score,
            landmarks: f.landmarks,
        }
    }
}

impl From<&KfFace> for Face {
    fn from(f: &KfFace) -> Self {
        Face {
            x: f.x,
            y: f.y,
            w: f.w,
            h: f.h,
            score: f.score,
            landmarks: f.landmarks,
        }
    }
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct KcStats {
    pub average: [u8; 3],
    pub bucket: u8,
    pub bucket_frac: f32,
    pub palette: [[u8; 3]; 5],
    pub palette_frac: [f32; 5],
}

/// Copies `msg` into the caller's NUL-terminated buffer, truncating.
unsafe fn write_err(err: *mut c_char, len: usize, msg: &str) {
    if err.is_null() || len == 0 {
        return;
    }
    let n = msg.len().min(len - 1);
    // SAFETY: the caller guarantees `err` points to `len` writable bytes.
    let dst = unsafe { std::slice::from_raw_parts_mut(err.cast::<u8>(), len) };
    dst[..n].copy_from_slice(&msg.as_bytes()[..n]);
    dst[n] = 0;
}

unsafe fn bytes<'a>(p: *const u8, len: usize) -> Option<&'a [u8]> {
    // SAFETY: caller guarantees `p` points to `len` readable bytes.
    (!p.is_null()).then(|| unsafe { std::slice::from_raw_parts(p, len) })
}

unsafe fn image(rgb: *const u8, w: u32, h: u32, stride: u32) -> Option<RgbImage> {
    let (w, h, stride) = (w as usize, h as usize, stride as usize);
    if w == 0 || h == 0 {
        return None;
    }
    let len = stride.checked_mul(h - 1)?.checked_add(w.checked_mul(3)?)?;
    // SAFETY: caller guarantees an RGB image of `h` rows `stride` bytes apart.
    let src = unsafe { bytes(rgb, len)? };
    RgbImage::from_strided(src, w, h, stride)
}

/// Worker threads for large convolutions (default 1).
#[no_mangle]
pub extern "C" fn kn_set_threads(n: u32) {
    crate::nn::set_threads(n as usize);
}

/// # Safety
/// `onnx` must point to `len` readable bytes; `err` (optional) to `err_len`
/// writable bytes.
#[no_mangle]
pub unsafe extern "C" fn kf_detector_load(
    onnx: *const u8,
    len: usize,
    err: *mut c_char,
    err_len: usize,
) -> *mut Detector {
    let Some(b) = (unsafe { bytes(onnx, len) }) else {
        unsafe { write_err(err, err_len, "null model buffer") };
        return std::ptr::null_mut();
    };
    match Detector::load(b) {
        Ok(d) => Box::into_raw(Box::new(d)),
        Err(e) => {
            unsafe { write_err(err, err_len, &e) };
            std::ptr::null_mut()
        }
    }
}

/// # Safety
/// `d` must come from `kf_detector_load` (or be null) and not be used after.
#[no_mangle]
pub unsafe extern "C" fn kf_detector_free(d: *mut Detector) {
    if !d.is_null() {
        // SAFETY: produced by Box::into_raw in kf_detector_load.
        drop(unsafe { Box::from_raw(d) });
    }
}

/// Detects faces; writes up to `max_out` into `out`, best first. Returns the
/// number written, or -1 on error.
///
/// # Safety
/// `rgb` must hold `h` rows of `stride` bytes (≥ 3·w); `out` must have room
/// for `max_out` faces.
#[no_mangle]
pub unsafe extern "C" fn kf_detect(
    d: *const Detector,
    rgb: *const u8,
    w: u32,
    h: u32,
    stride: u32,
    max_side: u32,
    score_thr: f32,
    out: *mut KfFace,
    max_out: i32,
) -> i32 {
    // SAFETY: caller passes a live detector or null.
    let (Some(d), Some(img)) = (unsafe { d.as_ref() }, unsafe { image(rgb, w, h, stride) }) else {
        return -1;
    };
    if out.is_null() || max_out < 0 {
        return -1;
    }
    let Ok(faces) = d.detect(&img, max_side.max(32) as usize, score_thr, 0.3) else {
        return -1;
    };
    let n = faces.len().min(max_out as usize);
    // SAFETY: `out` has room for `max_out` faces.
    let dst = unsafe { std::slice::from_raw_parts_mut(out, n) };
    for (o, f) in dst.iter_mut().zip(faces) {
        *o = f.into();
    }
    n as i32
}

/// # Safety
/// As for `kf_detector_load`.
#[no_mangle]
pub unsafe extern "C" fn kf_recognizer_load(
    onnx: *const u8,
    len: usize,
    err: *mut c_char,
    err_len: usize,
) -> *mut Recognizer {
    let Some(b) = (unsafe { bytes(onnx, len) }) else {
        unsafe { write_err(err, err_len, "null model buffer") };
        return std::ptr::null_mut();
    };
    match Recognizer::load(b) {
        Ok(r) => Box::into_raw(Box::new(r)),
        Err(e) => {
            unsafe { write_err(err, err_len, &e) };
            std::ptr::null_mut()
        }
    }
}

/// # Safety
/// `r` must come from `kf_recognizer_load` (or be null) and not be used after.
#[no_mangle]
pub unsafe extern "C" fn kf_recognizer_free(r: *mut Recognizer) {
    if !r.is_null() {
        // SAFETY: produced by Box::into_raw in kf_recognizer_load.
        drop(unsafe { Box::from_raw(r) });
    }
}

/// Aligns `face` and writes its 128-float L2-normalised embedding to `out`.
/// Returns 0 on success.
///
/// # Safety
/// Image as for `kf_detect`; `face` must point to one face; `out` to 128 floats.
#[no_mangle]
pub unsafe extern "C" fn kf_embed(
    r: *const Recognizer,
    rgb: *const u8,
    w: u32,
    h: u32,
    stride: u32,
    face: *const KfFace,
    out: *mut f32,
) -> i32 {
    // SAFETY: caller passes valid pointers or null.
    let (Some(r), Some(img), Some(f)) = (
        unsafe { r.as_ref() },
        unsafe { image(rgb, w, h, stride) },
        unsafe { face.as_ref() },
    ) else {
        return -1;
    };
    if out.is_null() {
        return -1;
    }
    let Ok(e) = r.embed(&face::align(&img, &f.into())) else {
        return -1;
    };
    // SAFETY: `out` has room for 128 floats.
    unsafe { std::slice::from_raw_parts_mut(out, EMBED_DIM) }.copy_from_slice(&e);
    0
}

/// Clusters `n` embeddings (n×128 floats). `fixed`/`exclude` give a person id
/// per face or -1 (see `face::cluster`). Writes a cluster index per face to
/// `labels` and the confirmed person id (or -1) per cluster to
/// `cluster_person` (room for `n`). Returns the cluster count, or -1.
///
/// # Safety
/// All arrays must have the stated lengths.
#[no_mangle]
pub unsafe extern "C" fn kf_cluster(
    embeddings: *const f32,
    n: usize,
    fixed: *const i64,
    exclude: *const i64,
    threshold: f32,
    labels: *mut u32,
    cluster_person: *mut i64,
) -> i64 {
    if n == 0 {
        return 0;
    }
    if embeddings.is_null()
        || fixed.is_null()
        || exclude.is_null()
        || labels.is_null()
        || cluster_person.is_null()
    {
        return -1;
    }
    let Some(total) = n.checked_mul(EMBED_DIM) else {
        return -1;
    };
    // SAFETY: lengths as documented above.
    let flat = unsafe { std::slice::from_raw_parts(embeddings, total) };
    let embs: Vec<[f32; EMBED_DIM]> = flat.as_chunks::<EMBED_DIM>().0.to_vec();
    let (fixed, exclude) = unsafe {
        (
            std::slice::from_raw_parts(fixed, n),
            std::slice::from_raw_parts(exclude, n),
        )
    };
    let out = cluster::cluster(&cluster::Input {
        embeddings: &embs,
        fixed,
        exclude,
        threshold,
    });
    let (labels, persons) = unsafe {
        (
            std::slice::from_raw_parts_mut(labels, n),
            std::slice::from_raw_parts_mut(cluster_person, n),
        )
    };
    for (o, &l) in labels.iter_mut().zip(&out.labels) {
        *o = l as u32;
    }
    for (o, &p) in persons.iter_mut().zip(&out.cluster_person) {
        *o = p;
    }
    out.cluster_person.len() as i64
}

/// Dominant colour and palette of an RGB image. Returns 0 on success.
///
/// # Safety
/// Image as for `kf_detect`; `out` must point to one `KcStats`.
#[no_mangle]
pub unsafe extern "C" fn kc_color_stats(
    rgb: *const u8,
    w: u32,
    h: u32,
    stride: u32,
    out: *mut KcStats,
) -> i32 {
    let Some(img) = (unsafe { image(rgb, w, h, stride) }) else {
        return -1;
    };
    // SAFETY: caller passes a valid out pointer or null.
    let Some(out) = (unsafe { out.as_mut() }) else {
        return -1;
    };
    let s = color::analyze(&img);
    *out = KcStats {
        average: s.average,
        bucket: s.bucket,
        bucket_frac: s.bucket_frac,
        palette: s.palette,
        palette_frac: s.palette_frac,
    };
    0
}

/// Name of colour bucket `i` ("red", …), or null. Static string.
#[no_mangle]
pub extern "C" fn kc_bucket_name(i: u32) -> *const c_char {
    const NAMES: [&[u8]; 13] = [
        b"none\0",
        b"red\0",
        b"orange\0",
        b"yellow\0",
        b"green\0",
        b"teal\0",
        b"blue\0",
        b"purple\0",
        b"pink\0",
        b"brown\0",
        b"black\0",
        b"white\0",
        b"gray\0",
    ];
    debug_assert_eq!(NAMES.len(), color::BUCKETS.len());
    NAMES
        .get(i as usize)
        .map_or(std::ptr::null(), |n| n.as_ptr().cast())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layouts_and_null_safety() {
        assert_eq!(std::mem::size_of::<KfFace>(), 15 * 4);
        assert_eq!(std::mem::size_of::<KcStats>(), 3 + 1 + 4 + 15 + 1 + 20);
        unsafe {
            assert!(kf_detector_load(std::ptr::null(), 0, std::ptr::null_mut(), 0).is_null());
            let mut err = [0 as c_char; 64];
            assert!(kf_detector_load(b"junk".as_ptr(), 4, err.as_mut_ptr(), err.len()).is_null());
            assert_ne!(err[0], 0);
            assert_eq!(
                kf_detect(
                    std::ptr::null(),
                    std::ptr::null(),
                    0,
                    0,
                    0,
                    640,
                    0.5,
                    std::ptr::null_mut(),
                    0
                ),
                -1
            );
            let rgb = [200u8, 30, 30].repeat(16);
            let mut st = KcStats::default();
            assert_eq!(kc_color_stats(rgb.as_ptr(), 4, 4, 12, &mut st), 0);
            assert_eq!(
                std::ffi::CStr::from_ptr(kc_bucket_name(st.bucket as u32))
                    .to_str()
                    .unwrap(),
                "red"
            );
            assert!(kc_bucket_name(99).is_null());
        }
    }
}
