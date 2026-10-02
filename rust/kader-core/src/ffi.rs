//! C ABI over the geo engine. Mirrored by `include/kader_core.h`.
//!
//! Ownership: every `*_new` returns an owned pointer that must be released
//! with the matching `*_free`. Pointers returned inside [`KgFrame`] and by the
//! accessor functions borrow from the globe/world and stay valid until the
//! next mutating call on the same object. Null handles are tolerated
//! everywhere and turn calls into no-ops.

use std::os::raw::c_char;
use std::slice;

use crate::geo::globe::{pin_input, LabelOut, PinOut, Style, Vertex};
use crate::geo::{Globe, World};

pub struct KgWorld(World);
pub struct KgGlobe(Globe);

#[repr(C)]
pub struct KgFrame {
    pub vertices: *const Vertex,
    pub vertex_count: u32,
    pub indices: *const u32,
    pub index_count: u32,
    pub labels: *const LabelOut,
    pub label_count: u32,
    pub pins: *const PinOut,
    pub pin_count: u32,
    pub pin_epoch: u32,
    /// Globe disc in item coordinates.
    pub center_x: f32,
    pub center_y: f32,
    pub radius: f32,
    /// Web-mercator-equivalent zoom.
    pub zoom: f32,
}

#[repr(C)]
pub struct KgPinIn {
    pub lat: f64,
    pub lon: f64,
    pub weight: u32,
}

#[repr(C)]
pub struct KgCamera {
    pub lat: f64,
    pub lon: f64,
    pub radius: f64,
    pub zoom: f64,
    pub fit_radius: f64,
}

/// Version string of the core library (NUL terminated, static).
#[no_mangle]
pub extern "C" fn kg_version() -> *const c_char {
    concat!(env!("CARGO_PKG_VERSION"), "\0").as_ptr().cast()
}

/// Decode a `.kgeo` dataset. Returns null on malformed input.
///
/// # Safety
/// `data` must point to `len` readable bytes (it is not retained).
#[no_mangle]
pub unsafe extern "C" fn kg_world_new(data: *const u8, len: usize) -> *mut KgWorld {
    if data.is_null() || len == 0 {
        return std::ptr::null_mut();
    }
    let bytes = slice::from_raw_parts(data, len);
    match World::decode(bytes) {
        Ok(w) => Box::into_raw(Box::new(KgWorld(w))),
        Err(_) => std::ptr::null_mut(),
    }
}

/// # Safety
/// `world` must come from [`kg_world_new`] (or be null) and not be used after.
#[no_mangle]
pub unsafe extern "C" fn kg_world_free(world: *mut KgWorld) {
    if !world.is_null() {
        drop(Box::from_raw(world));
    }
}

/// UTF-8 name of a label (not NUL terminated); length via `len`.
///
/// # Safety
/// `world` must be valid or null; `len` must be a valid pointer or null.
#[no_mangle]
pub unsafe extern "C" fn kg_world_label_name(world: *const KgWorld, id: u32, len: *mut usize) -> *const u8 {
    let name = world.as_ref().and_then(|w| w.0.label_name(id as usize)).unwrap_or("");
    if let Some(l) = len.as_mut() {
        *l = name.len();
    }
    name.as_ptr()
}

/// Offline place name ("City, Country") for a point, written as UTF-8 into
/// `buf` (truncated to `cap`, not NUL terminated). Returns the byte length, or
/// 0 when no town lies within `max_km`. `distance_km` receives the distance.
///
/// # Safety
/// `world` valid or null; `buf` must have `cap` writable bytes; `distance_km`
/// valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_world_place_name(
    world: *const KgWorld,
    lat: f64,
    lon: f64,
    max_km: f64,
    buf: *mut u8,
    cap: usize,
    distance_km: *mut f64,
) -> usize {
    let Some(w) = world.as_ref() else { return 0 };
    let Some(p) = w.0.place_name(lat, lon, max_km) else { return 0 };
    let text = match p.country {
        Some(c) if c != p.city => format!("{}, {}", p.city, c),
        _ => p.city.to_string(),
    };
    if let Some(d) = distance_km.as_mut() {
        *d = p.distance_km;
    }
    if buf.is_null() || cap == 0 {
        return text.len();
    }
    // never split a UTF-8 sequence when truncating
    let mut n = text.len().min(cap);
    while !text.is_char_boundary(n) {
        n -= 1;
    }
    std::ptr::copy_nonoverlapping(text.as_ptr(), buf, n);
    n
}

#[no_mangle]
pub extern "C" fn kg_globe_new() -> *mut KgGlobe {
    Box::into_raw(Box::new(KgGlobe(Globe::new())))
}

/// # Safety
/// `g` must come from [`kg_globe_new`] (or be null) and not be used after.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_free(g: *mut KgGlobe) {
    if !g.is_null() {
        drop(Box::from_raw(g));
    }
}

macro_rules! globe {
    ($g:expr, $default:expr) => {
        match $g.as_mut() {
            Some(g) => &mut g.0,
            None => return $default,
        }
    };
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_set_viewport(g: *mut KgGlobe, width: f64, height: f64, dpr: f64) {
    globe!(g, ()).set_viewport(width, height, dpr);
}

/// # Safety
/// `g` must be valid or null; `style` must point to a `KgStyle` or be null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_set_style(g: *mut KgGlobe, style: *const Style) {
    if let Some(s) = style.as_ref() {
        globe!(g, ()).style = *s;
    }
}

/// # Safety
/// `g` must be valid or null; `pins` must point to `count` items (or be null).
#[no_mangle]
pub unsafe extern "C" fn kg_globe_set_pins(g: *mut KgGlobe, pins: *const KgPinIn, count: usize) {
    let g = globe!(g, ());
    let input = if pins.is_null() || count == 0 {
        Vec::new()
    } else {
        slice::from_raw_parts(pins, count)
            .iter()
            .filter(|p| p.lat.is_finite() && p.lon.is_finite())
            .map(|p| pin_input(p.lat, p.lon, p.weight))
            .collect()
    };
    g.pins.set(input);
}

/// Member indices (into the pins passed to `kg_globe_set_pins`) of a cluster.
///
/// # Safety
/// `g` must be valid or null; `count` must be a valid pointer or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_pin_members(g: *mut KgGlobe, cluster: u32, count: *mut usize) -> *const u32 {
    let members: &[u32] = match g.as_ref().and_then(|g| g.0.pins.clusters.get(cluster as usize)) {
        Some(c) => &c.members,
        None => &[],
    };
    if let Some(c) = count.as_mut() {
        *c = members.len();
    }
    members.as_ptr()
}

/// Number of pin clusters at the current zoom.
///
/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_cluster_count(g: *mut KgGlobe) -> u32 {
    globe!(g, 0).pins.clusters.len() as u32
}

/// Weighted centre (degrees), summed weight and lead pin of a cluster.
///
/// # Safety
/// `g` must be valid or null; out pointers valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_cluster_info(
    g: *mut KgGlobe,
    cluster: u32,
    lat: *mut f64,
    lon: *mut f64,
    weight: *mut u32,
    lead: *mut u32,
) -> bool {
    let g = globe!(g, false);
    let Some(c) = g.pins.clusters.get(cluster as usize) else { return false };
    let (la, lo) = crate::geo::math::to_lat_lon(c.pos);
    if let Some(p) = lat.as_mut() {
        *p = la.to_degrees();
    }
    if let Some(p) = lon.as_mut() {
        *p = lo.to_degrees();
    }
    if let Some(p) = weight.as_mut() {
        *p = c.weight;
    }
    if let Some(p) = lead.as_mut() {
        *p = c.lead;
    }
    true
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_pin_at(g: *mut KgGlobe, x: f64, y: f64) -> i64 {
    globe!(g, -1).pin_at(x, y).map_or(-1, i64::from)
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_drag_begin(g: *mut KgGlobe) {
    globe!(g, ()).drag_begin();
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_drag(g: *mut KgGlobe, dx: f64, dy: f64) {
    globe!(g, ()).drag(dx, dy);
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_drag_end(g: *mut KgGlobe, vx: f64, vy: f64) {
    globe!(g, ()).drag_end(vx, vy);
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_zoom_by(g: *mut KgGlobe, factor: f64, x: f64, y: f64, animate: bool) {
    if factor.is_finite() && factor > 0.0 {
        globe!(g, ()).zoom_by(factor, x, y, animate);
    }
}

/// Fly to a place; `radius <= 0` keeps the zoom.
///
/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_fly_to(g: *mut KgGlobe, lat: f64, lon: f64, radius: f64) {
    if lat.is_finite() && lon.is_finite() {
        globe!(g, ()).fly_to(lat, lon, radius);
    }
}

/// Radius that frames a region `km` across.
///
/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_radius_for_km(g: *mut KgGlobe, km: f64) -> f64 {
    globe!(g, 0.0).radius_for_km(km)
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_reset(g: *mut KgGlobe) {
    globe!(g, ()).reset();
}

/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_set_auto_rotate(g: *mut KgGlobe, on: bool) {
    globe!(g, ()).auto_rotate = on;
}

/// Advance animations; returns true while the camera is moving.
///
/// # Safety
/// `g` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_tick(g: *mut KgGlobe, dt: f64) -> bool {
    globe!(g, false).tick(dt)
}

/// # Safety
/// `g` must be valid or null; `out` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_camera(g: *mut KgGlobe, out: *mut KgCamera) {
    let g = globe!(g, ());
    if let Some(o) = out.as_mut() {
        *o = KgCamera {
            lat: g.cam.lat.to_degrees(),
            lon: g.cam.lon.to_degrees(),
            radius: g.cam.r,
            zoom: g.zoom(),
            fit_radius: g.fit_radius(),
        };
    }
}

/// Project lat/lon (degrees) to item coordinates; returns the depth
/// (> 0 on the visible hemisphere).
///
/// # Safety
/// `g` must be valid or null; `x`/`y` valid pointers or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_project(g: *mut KgGlobe, lat: f64, lon: f64, x: *mut f64, y: *mut f64) -> f64 {
    let (px, py, d) = globe!(g, -1.0).project_deg(lat, lon);
    if let Some(x) = x.as_mut() {
        *x = px;
    }
    if let Some(y) = y.as_mut() {
        *y = py;
    }
    d
}

/// Lat/lon (degrees) under an item point; false when off the globe.
///
/// # Safety
/// `g` must be valid or null; `lat`/`lon` valid pointers or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_unproject(g: *mut KgGlobe, x: f64, y: f64, lat: *mut f64, lon: *mut f64) -> bool {
    match globe!(g, false).unproject_deg(x, y) {
        Some((la, lo)) => {
            if let Some(p) = lat.as_mut() {
                *p = la;
            }
            if let Some(p) = lon.as_mut() {
                *p = lo;
            }
            true
        }
        None => false,
    }
}

/// Build the frame. Returns whether labels are still fading (keep animating).
/// `out` receives borrowed views valid until the next call on `g`.
///
/// # Safety
/// `g` and `world` must be valid or null; `out` must be valid or null.
#[no_mangle]
pub unsafe extern "C" fn kg_globe_build(g: *mut KgGlobe, world: *const KgWorld, dt: f64, out: *mut KgFrame) -> bool {
    let g = globe!(g, false);
    let fading = match world.as_ref() {
        Some(w) => g.build(&w.0, dt),
        None => false,
    };
    if let Some(o) = out.as_mut() {
        let f = g.frame();
        let r = g.cam.r;
        *o = KgFrame {
            vertices: f.vertices.as_ptr(),
            vertex_count: f.vertices.len() as u32,
            indices: f.indices.as_ptr(),
            index_count: f.indices.len() as u32,
            labels: f.labels.as_ptr(),
            label_count: f.labels.len() as u32,
            pins: f.pins.as_ptr(),
            pin_count: f.pins.len() as u32,
            pin_epoch: g.pins.epoch,
            center_x: 0.0, // the globe is always centred in the item
            center_y: 0.0,
            radius: r as f32,
            zoom: g.zoom() as f32,
        };
    }
    fading
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layout_matches_header() {
        assert_eq!(std::mem::size_of::<Vertex>(), 24);
        assert_eq!(std::mem::size_of::<LabelOut>(), 20);
        assert_eq!(std::mem::size_of::<PinOut>(), 32);
        assert_eq!(std::mem::size_of::<KgPinIn>(), 24);
        assert_eq!(std::mem::size_of::<Style>(), 28 + 9 * 4);
    }

    #[test]
    fn null_handles_are_harmless() {
        unsafe {
            assert!(kg_world_new(std::ptr::null(), 0).is_null());
            kg_world_free(std::ptr::null_mut());
            kg_globe_free(std::ptr::null_mut());
            assert!(!kg_globe_tick(std::ptr::null_mut(), 0.1));
            assert_eq!(kg_globe_pin_at(std::ptr::null_mut(), 0.0, 0.0), -1);
            let mut n = 7usize;
            kg_world_label_name(std::ptr::null(), 3, &mut n);
            assert_eq!(n, 0);
        }
    }
}
