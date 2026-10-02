//! C ABI over the scanner (see `include/kader_core.h`).

use std::ffi::{c_char, c_void, CStr};
use std::path::PathBuf;
use std::slice;
use std::sync::atomic::{AtomicUsize, Ordering};

use crate::scan::paths::{from_bytes, to_bytes};
use crate::scan::walk::{walk, Entry, Options};
use crate::scan::{probe, Meta};

pub struct KsScan {
    entries: Vec<Entry>,
    dirs: usize,
    /// UTF-8, '/'-separated copies of the entry paths handed out by
    /// [`ks_scan_entry`] (on Unix the OS bytes are borrowed directly).
    #[cfg(not(unix))]
    names: Vec<Vec<u8>>,
}

pub type KsProgressFn = Option<unsafe extern "C" fn(user: *mut c_void, found: usize)>;

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct KsMeta {
    pub width: u32,
    pub height: u32,
    pub orientation: u16,
    pub flags: u8,
    pub _pad0: u8,
    pub year: u16,
    pub month: u8,
    pub day: u8,
    pub hour: u8,
    pub minute: u8,
    pub second: u8,
    pub _pad1: u8,
    pub lat: f64,
    pub lon: f64,
    pub duration: f64,
}

pub const KS_KNOWN: u8 = 1;
pub const KS_SIZE: u8 = 2;
pub const KS_DATE: u8 = 4;
pub const KS_DATE_UTC: u8 = 8;
pub const KS_GPS: u8 = 16;
pub const KS_VIDEO: u8 = 32;
pub const KS_DURATION: u8 = 64;

impl From<&Meta> for KsMeta {
    fn from(m: &Meta) -> Self {
        let (w, h) = m.display_size();
        let mut out = KsMeta {
            width: w,
            height: h,
            orientation: m.orientation,
            ..Default::default()
        };
        let mut f = 0;
        if m.format_known {
            f |= KS_KNOWN;
        }
        if w > 0 && h > 0 {
            f |= KS_SIZE;
        }
        if let Some(d) = m.date {
            f |= KS_DATE;
            if m.date_utc {
                f |= KS_DATE_UTC;
            }
            (
                out.year, out.month, out.day, out.hour, out.minute, out.second,
            ) = (d.year, d.month, d.day, d.hour, d.minute, d.second);
        }
        if let Some((la, lo)) = m.gps {
            f |= KS_GPS;
            out.lat = la;
            out.lon = lo;
        }
        if m.is_video {
            f |= KS_VIDEO;
        }
        if m.duration > 0.0 {
            f |= KS_DURATION;
            out.duration = m.duration;
        }
        out.flags = f;
        out
    }
}

unsafe fn c_list(ptr: *const *const c_char, n: usize, lower: bool) -> Vec<Vec<u8>> {
    if ptr.is_null() {
        return Vec::new();
    }
    slice::from_raw_parts(ptr, n)
        .iter()
        .filter(|p| !p.is_null())
        .map(|&p| {
            let b = CStr::from_ptr(p).to_bytes();
            if lower {
                b.to_ascii_lowercase()
            } else {
                b.to_vec()
            }
        })
        .collect()
}

/// Walks `root` on `threads` workers (0 = all cores) collecting files whose
/// extension (".jpg", case-insensitive) is in `exts`. `progress` is called
/// from worker threads. Free the result with [`ks_scan_free`].
///
/// # Safety
/// `root` and every string in the lists must be valid NUL-terminated strings;
/// list pointers may be null when their count is 0.
#[no_mangle]
pub unsafe extern "C" fn ks_scan_dir(
    root: *const c_char,
    exts: *const *const c_char,
    n_exts: usize,
    exclusions: *const *const c_char,
    n_exclusions: usize,
    threads: u32,
    progress: KsProgressFn,
    user: *mut c_void,
) -> *mut KsScan {
    if root.is_null() {
        return std::ptr::null_mut();
    }
    let root = from_bytes(CStr::from_ptr(root).to_bytes());
    let threads = if threads == 0 {
        std::thread::available_parallelism().map_or(4, |n| n.get())
    } else {
        threads as usize
    };
    let opts = Options {
        extensions: c_list(exts, n_exts, true),
        exclusions: c_list(exclusions, n_exclusions, false),
        threads,
        background: true,
    };
    let user = user as usize; // moved across threads; the caller guarantees validity
    let cb = move |n: usize| {
        if let Some(f) = progress {
            f(user as *mut c_void, n);
        }
    };
    let r = walk(&root, &opts, &cb);
    Box::into_raw(Box::new(KsScan {
        #[cfg(not(unix))]
        names: r
            .entries
            .iter()
            .map(|e| to_bytes(e.path.as_os_str()).into_owned())
            .collect(),
        entries: r.entries,
        dirs: r.dirs,
    }))
}

/// # Safety
/// `scan` must come from [`ks_scan_dir`] or be null.
#[no_mangle]
pub unsafe extern "C" fn ks_scan_count(scan: *const KsScan) -> usize {
    scan.as_ref().map_or(0, |s| s.entries.len())
}

/// # Safety
/// `scan` must come from [`ks_scan_dir`] or be null.
#[no_mangle]
pub unsafe extern "C" fn ks_scan_dirs(scan: *const KsScan) -> usize {
    scan.as_ref().map_or(0, |s| s.dirs)
}

/// Entry `i`: path bytes (not NUL-terminated, valid until free), size, mtime.
///
/// # Safety
/// `scan` valid or null; out pointers valid or null.
#[no_mangle]
pub unsafe extern "C" fn ks_scan_entry(
    scan: *const KsScan,
    i: usize,
    path: *mut *const u8,
    path_len: *mut usize,
    size: *mut u64,
    mtime: *mut i64,
) -> bool {
    let Some(s) = scan.as_ref() else {
        return false;
    };
    let Some(e) = s.entries.get(i) else {
        return false;
    };
    #[cfg(unix)]
    let b: &[u8] = &to_bytes(e.path.as_os_str());
    #[cfg(not(unix))]
    let b: &[u8] = &s.names[i];
    if let Some(p) = path.as_mut() {
        *p = b.as_ptr();
    }
    if let Some(p) = path_len.as_mut() {
        *p = b.len();
    }
    if let Some(p) = size.as_mut() {
        *p = e.size;
    }
    if let Some(p) = mtime.as_mut() {
        *p = e.mtime;
    }
    true
}

/// # Safety
/// `scan` must come from [`ks_scan_dir`] (or be null) and not be used after.
#[no_mangle]
pub unsafe extern "C" fn ks_scan_free(scan: *mut KsScan) {
    if !scan.is_null() {
        drop(Box::from_raw(scan));
    }
}

/// Probes `n` files in parallel (`threads` 0 = all cores) into `out[n]`.
///
/// # Safety
/// `paths[i]` must point to `lens[i]` readable bytes; `out` must have room for
/// `n` entries.
#[no_mangle]
pub unsafe extern "C" fn ks_probe_batch(
    paths: *const *const u8,
    lens: *const usize,
    n: usize,
    threads: u32,
    out: *mut KsMeta,
) {
    if n == 0 || paths.is_null() || lens.is_null() || out.is_null() {
        return;
    }
    let paths: Vec<PathBuf> = slice::from_raw_parts(paths, n)
        .iter()
        .zip(slice::from_raw_parts(lens, n))
        .map(|(&p, &l)| from_bytes(slice::from_raw_parts(p, l)))
        .collect();
    let out = slice::from_raw_parts_mut(out, n);
    let threads = if threads == 0 {
        std::thread::available_parallelism().map_or(4, |n| n.get())
    } else {
        threads as usize
    }
    .clamp(1, 64)
    .min(n);
    let next = AtomicUsize::new(0);
    // hand each worker disjoint indices through the atomic counter; results
    // are collected and written back on this thread
    let results: Vec<Vec<(usize, KsMeta)>> = std::thread::scope(|s| {
        let hs: Vec<_> = (0..threads)
            .map(|_| {
                s.spawn(|| {
                    let mut local = Vec::new();
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= paths.len() {
                            break;
                        }
                        local.push((i, KsMeta::from(&probe(&paths[i]))));
                    }
                    local
                })
            })
            .collect();
        hs.into_iter()
            .map(|h| h.join().unwrap_or_default())
            .collect()
    });
    for (i, m) in results.into_iter().flatten() {
        out[i] = m;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn meta_layout() {
        assert_eq!(std::mem::size_of::<KsMeta>(), 48);
        assert_eq!(std::mem::offset_of!(KsMeta, lat), 24);
    }
}
