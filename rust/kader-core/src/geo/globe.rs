//! Orthographic globe camera + per-frame geometry builder.
//!
//! Everything is projected on the CPU in f64 and culled against the visible
//! cap and the viewport, so the output is just the handful of quads that are
//! actually on screen: land dots, coast/border/state polylines and city
//! markers (one indexed triangle list, one draw call), plus the placed labels
//! and photo pins for the QML overlay.

use std::collections::HashMap;
use std::f64::consts::{FRAC_PI_2, PI, TAU};

use super::math::{dot, f32v, from_lat_lon, lerp, normalize, smoothstep, to_lat_lon, wrap_pi, V3};
use super::pins::{PinInput, Pins};
use super::world::{LabelKind, LineKind, World};

/// Web-mercator zoom 0 ⇔ a globe radius of 256/2π px.
const ZOOM0_RADIUS: f64 = 256.0 / TAU;
/// Deepest zoom: roughly a 60–100 km wide window, where towns are labelled.
const MAX_RADIUS: f64 = 90_000.0;

/// Vertex of the shape batch. `uv` spans [-1, 1] across the shape and `w` is
/// the shape's half-extent in device pixels, which the fragment shader uses
/// for a 1-device-pixel antialiased edge. Colour is premultiplied RGBA8.
#[repr(C)]
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Vertex {
    pub x: f32,
    pub y: f32,
    pub u: f32,
    pub v: f32,
    pub w: f32,
    pub rgba: [u8; 4],
}

/// Label class — styled identically on the QML side (keep in sync with
/// `qml/views/GlobeView.qml`).
pub mod class {
    pub const OCEAN: u8 = 0;
    pub const COUNTRY: u8 = 1;
    pub const STATE: u8 = 2;
    pub const CITY_MAJOR: u8 = 3;
    pub const CITY: u8 = 4;
    pub const TOWN: u8 = 5;
}

/// (font px, average glyph width in em, letter spacing px) per class.
const LABEL_METRICS: [(f64, f64, f64); 6] = [
    (12.0, 0.56, 1.5), // ocean (italic, spaced)
    (12.5, 0.70, 1.6), // country (caps, spaced)
    (10.0, 0.68, 1.0), // state (caps, spaced)
    (13.5, 0.57, 0.0), // major city / capital
    (12.0, 0.56, 0.0), // city
    (11.0, 0.56, 0.0), // town
];

pub mod anchor {
    pub const CENTER: u8 = 0;
    pub const RIGHT: u8 = 1; // text right of the marker
    pub const LEFT: u8 = 2;
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct LabelOut {
    pub id: u32,
    pub x: f32,
    pub y: f32,
    pub alpha: f32,
    pub class: u8,
    pub anchor: u8,
    pub capital: u8,
    pub _pad: u8,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Default)]
pub struct PinOut {
    pub cluster: u32,
    pub lead: u32,
    pub count: u32,
    pub members: u32,
    pub x: f32,
    pub y: f32,
    pub depth: f32,
    pub alpha: f32,
}

/// Colours are straight (non-premultiplied) RGBA8.
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct Style {
    pub land: [u8; 4],
    pub coast: [u8; 4],
    pub border: [u8; 4],
    pub state: [u8; 4],
    pub city: [u8; 4],
    pub city_halo: [u8; 4],
    /// Dark casing drawn under coast and border lines for contrast.
    pub casing: [u8; 4],
    /// Target on-screen spacing of land dots, logical px.
    pub dot_spacing: f32,
    /// Dot radius as a fraction of the spacing.
    pub dot_size: f32,
    pub coast_width: f32,
    pub border_width: f32,
    pub state_width: f32,
    /// Shifts label thresholds: +1 shows labels one zoom level earlier.
    pub label_density: f32,
    /// Pin bubble footprint, logical px (anchored bottom-centre on the point).
    pub pin_width: f32,
    pub pin_height: f32,
    /// Pins closer than this many px are merged into one cluster.
    pub pin_merge: f32,
}

impl Default for Style {
    fn default() -> Self {
        Self {
            land: [235, 238, 245, 235],
            coast: [140, 170, 255, 200],
            border: [255, 255, 255, 220],
            state: [255, 255, 255, 110],
            city: [255, 255, 255, 255],
            city_halo: [10, 12, 20, 200],
            casing: [6, 8, 14, 200],
            dot_spacing: 7.0,
            dot_size: 0.30,
            coast_width: 0.9,
            border_width: 1.15,
            state_width: 0.75,
            label_density: 0.0,
            pin_width: 64.0,
            pin_height: 44.0,
            pin_merge: 46.0,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Camera {
    /// Radians.
    pub lat: f64,
    pub lon: f64,
    /// Globe radius in logical px.
    pub r: f64,
}

struct Basis {
    c: V3,
    e: V3,
    n: V3,
    cx: f64,
    cy: f64,
    r: f64,
}

impl Basis {
    #[inline]
    fn project(&self, p: V3) -> (f64, f64, f64) {
        (
            self.cx + self.r * dot(p, self.e),
            self.cy - self.r * dot(p, self.n),
            dot(p, self.c),
        )
    }
}

#[derive(Clone, Copy)]
struct LabelState {
    alpha: f32,
    placed: bool,
    anchor: u8,
}

pub struct Frame<'a> {
    pub vertices: &'a [Vertex],
    pub indices: &'a [u32],
    pub labels: &'a [LabelOut],
    pub pins: &'a [PinOut],
}

pub struct Globe {
    pub cam: Camera,
    width: f64,
    height: f64,
    dpr: f64,
    pub style: Style,

    dragging: bool,
    idle: f64,
    vel: (f64, f64),
    zoom_target: Option<(f64, f64, f64)>,
    fly: Option<Camera>,
    pub auto_rotate: bool,

    pub pins: Pins,
    label_state: HashMap<u32, LabelState>,
    dot_dim: f64,
    dot_shrink: f64,

    verts: Vec<Vertex>,
    idx: Vec<u32>,
    labels: Vec<LabelOut>,
    pin_out: Vec<PinOut>,
    // label collision grid scratch
    grid: Vec<Vec<u16>>,
    rects: Vec<[f64; 4]>,
}

impl Default for Globe {
    fn default() -> Self {
        Self::new()
    }
}

impl Globe {
    pub fn new() -> Self {
        Self {
            cam: Camera {
                lat: 22f64.to_radians(),
                lon: 10f64.to_radians(),
                r: 0.0,
            },
            width: 0.0,
            height: 0.0,
            dpr: 1.0,
            style: Style::default(),
            dragging: false,
            idle: 0.0,
            vel: (0.0, 0.0),
            zoom_target: None,
            fly: None,
            auto_rotate: true,
            pins: Pins::default(),
            label_state: HashMap::new(),
            dot_dim: 1.0,
            dot_shrink: 1.0,
            verts: Vec::new(),
            idx: Vec::new(),
            labels: Vec::new(),
            pin_out: Vec::new(),
            grid: Vec::new(),
            rects: Vec::new(),
        }
    }

    // ── camera ──────────────────────────────────────────────────────────────

    pub fn fit_radius(&self) -> f64 {
        0.40 * self.width.min(self.height).max(1.0)
    }

    fn min_radius(&self) -> f64 {
        0.18 * self.width.min(self.height).max(1.0)
    }

    fn clamp_r(&self, r: f64) -> f64 {
        r.clamp(self.min_radius(), MAX_RADIUS)
    }

    /// Web-mercator-equivalent zoom level of the current view.
    pub fn zoom(&self) -> f64 {
        (self.cam.r / ZOOM0_RADIUS).max(1e-6).log2()
    }

    pub fn set_viewport(&mut self, w: f64, h: f64, dpr: f64) {
        let first = self.cam.r <= 0.0 || self.width <= 0.0;
        self.width = w.max(1.0);
        self.height = h.max(1.0);
        self.dpr = dpr.clamp(0.5, 8.0);
        self.cam.r = if first {
            self.fit_radius()
        } else {
            self.clamp_r(self.cam.r)
        };
    }

    fn basis(&self) -> Basis {
        let (sl, cl) = self.cam.lat.sin_cos();
        let (so, co) = self.cam.lon.sin_cos();
        Basis {
            c: [cl * co, cl * so, sl],
            e: [-so, co, 0.0],
            n: [-sl * co, -sl * so, cl],
            cx: self.width * 0.5,
            cy: self.height * 0.5,
            r: self.cam.r,
        }
    }

    /// Screen position and depth (cos of angular distance from the view
    /// centre; < 0 means the far side) of a lat/lon in degrees.
    pub fn project_deg(&self, lat: f64, lon: f64) -> (f64, f64, f64) {
        self.basis()
            .project(from_lat_lon(lat.to_radians(), lon.to_radians()))
    }

    pub fn unproject(&self, x: f64, y: f64) -> Option<V3> {
        let b = self.basis();
        let dx = (x - b.cx) / b.r;
        let dy = (b.cy - y) / b.r;
        let rho2 = dx * dx + dy * dy;
        if rho2 > 1.0 {
            return None;
        }
        let z = (1.0 - rho2).sqrt();
        Some(normalize([
            dx * b.e[0] + dy * b.n[0] + z * b.c[0],
            dx * b.e[1] + dy * b.n[1] + z * b.c[1],
            dx * b.e[2] + dy * b.n[2] + z * b.c[2],
        ]))
    }

    /// Lat/lon (degrees) under a screen point.
    pub fn unproject_deg(&self, x: f64, y: f64) -> Option<(f64, f64)> {
        self.unproject(x, y).map(|p| {
            let (la, lo) = to_lat_lon(p);
            (la.to_degrees(), lo.to_degrees())
        })
    }

    /// Move the surface by (dx, dy) screen px ("grab" semantics: the point
    /// under the pointer follows it).
    fn pan(&mut self, dx: f64, dy: f64) {
        let r = self.cam.r.max(1.0);
        self.cam.lon = wrap_pi(self.cam.lon - dx / (r * self.cam.lat.cos().max(0.25)));
        self.cam.lat = (self.cam.lat + dy / r).clamp(-FRAC_PI_2 + 0.02, FRAC_PI_2 - 0.02);
    }

    /// Set the radius, keeping the surface point under (ax, ay) fixed.
    fn zoom_to(&mut self, r: f64, ax: f64, ay: f64) {
        let anchor = self.unproject(ax, ay);
        self.cam.r = self.clamp_r(r);
        if let Some(g) = anchor {
            for _ in 0..4 {
                let (px, py, d) = self.basis().project(g);
                if d <= 0.0 {
                    break;
                }
                let (ex, ey) = (ax - px, ay - py);
                if ex.abs() < 0.01 && ey.abs() < 0.01 {
                    break;
                }
                self.pan(ex, ey);
            }
        }
    }

    pub fn drag_begin(&mut self) {
        self.dragging = true;
        self.idle = 0.0;
        self.vel = (0.0, 0.0);
        self.fly = None;
        self.zoom_target = None;
    }

    pub fn drag(&mut self, dx: f64, dy: f64) {
        self.idle = 0.0;
        self.pan(dx, dy);
    }

    /// End of a drag with the pointer velocity (px/s) for inertia.
    pub fn drag_end(&mut self, vx: f64, vy: f64) {
        self.dragging = false;
        let s = (vx * vx + vy * vy).sqrt();
        let k = if s > 5000.0 { 5000.0 / s } else { 1.0 };
        self.vel = (vx * k, vy * k);
    }

    /// Multiply the zoom by `factor` around (ax, ay); smooth when `animate`.
    pub fn zoom_by(&mut self, factor: f64, ax: f64, ay: f64, animate: bool) {
        self.idle = 0.0;
        self.fly = None;
        let base = self.zoom_target.map_or(self.cam.r, |t| t.0);
        let target = self.clamp_r(base * factor);
        if animate {
            self.zoom_target = Some((target, ax, ay));
        } else {
            self.zoom_target = None;
            self.zoom_to(target, ax, ay);
        }
    }

    /// Animate to a location. `r <= 0` keeps the current zoom.
    pub fn fly_to(&mut self, lat_deg: f64, lon_deg: f64, r: f64) {
        self.idle = 0.0;
        self.vel = (0.0, 0.0);
        self.zoom_target = None;
        let r = if r > 0.0 { self.clamp_r(r) } else { self.cam.r };
        self.fly = Some(Camera {
            lat: lat_deg
                .to_radians()
                .clamp(-FRAC_PI_2 + 0.02, FRAC_PI_2 - 0.02),
            lon: lon_deg.to_radians(),
            r,
        });
    }

    /// Radius at which a feature `km` across fills about half the view.
    pub fn radius_for_km(&self, km: f64) -> f64 {
        let view = 0.5 * self.width.min(self.height);
        self.clamp_r(view * 6371.0 / km.max(0.5))
    }

    pub fn reset(&mut self) {
        let fit = self.fit_radius();
        self.fly = Some(Camera {
            lat: self.cam.lat.clamp(-0.6, 0.6),
            lon: self.cam.lon,
            r: fit,
        });
    }

    /// Advance animations by `dt` seconds; returns whether anything moves.
    pub fn tick(&mut self, dt: f64) -> bool {
        // Idle time uses the real gap (the caller may pause ticking while
        // nothing moves); motion steps are clamped for stability.
        let raw = dt.max(0.0);
        if !self.dragging {
            self.idle += raw;
        }
        let dt = raw.min(0.1);
        let mut active = false;

        if let Some(f) = self.fly {
            let k = 1.0 - (-dt * 5.5).exp();
            let dlon = wrap_pi(f.lon - self.cam.lon);
            self.cam.lat += (f.lat - self.cam.lat) * k;
            self.cam.lon = wrap_pi(self.cam.lon + dlon * k);
            let lr = self.cam.r.ln();
            self.cam.r = (lr + (f.r.ln() - lr) * k).exp();
            if (f.lat - self.cam.lat).abs() < 1e-5
                && dlon.abs() < 1e-5
                && (f.r / self.cam.r).ln().abs() < 1e-3
            {
                self.cam = f;
                self.fly = None;
            }
            self.idle = 0.0;
            return true;
        }

        let speed = (self.vel.0 * self.vel.0 + self.vel.1 * self.vel.1).sqrt();
        if !self.dragging && speed > 4.0 {
            self.pan(self.vel.0 * dt, self.vel.1 * dt);
            let decay = (-dt * 4.2).exp();
            self.vel = (self.vel.0 * decay, self.vel.1 * decay);
            self.idle = 0.0;
            active = true;
        } else if !self.dragging {
            self.vel = (0.0, 0.0);
        }

        if let Some((target, ax, ay)) = self.zoom_target {
            let k = 1.0 - (-dt * 14.0).exp();
            let lr = self.cam.r.ln();
            let nr = (lr + (target.ln() - lr) * k).exp();
            self.zoom_to(nr, ax, ay);
            if (target / self.cam.r).ln().abs() < 1e-3 {
                self.zoom_to(target, ax, ay);
                self.zoom_target = None;
            }
            self.idle = 0.0;
            active = true;
        }

        if self.auto_rotate
            && !self.dragging
            && self.idle > 2.5
            && self.cam.r < 1.7 * self.fit_radius()
        {
            // Eastward spin, like the real Earth seen with north up.
            let ease = smoothstep(2.5, 4.0, self.idle);
            self.cam.lon = wrap_pi(self.cam.lon - dt * 0.07 * ease);
            active = true;
        }
        active
    }

    pub fn is_interacting(&self) -> bool {
        self.dragging
    }

    // ── frame building ──────────────────────────────────────────────────────

    /// Builds this frame's geometry. Returns true while labels are still
    /// fading (the caller should keep requesting frames).
    pub fn build(&mut self, world: &World, dt: f64) -> bool {
        self.verts.clear();
        self.idx.clear();
        self.labels.clear();
        self.pin_out.clear();
        if self.width <= 1.0 || self.height <= 1.0 || self.cam.r <= 0.0 {
            return false;
        }
        let b = self.basis();
        // Angular radius of the view: the visible cap never exceeds a hemisphere.
        let half_diag = 0.5 * (self.width * self.width + self.height * self.height).sqrt() + 24.0;
        let rho = if half_diag >= b.r {
            FRAC_PI_2
        } else {
            (half_diag / b.r).asin()
        };

        self.build_dots(world, &b, rho);
        self.build_lines(world, &b, rho);
        self.build_pins(&b);
        self.build_labels(world, &b, dt)
    }

    pub fn frame(&self) -> Frame<'_> {
        Frame {
            vertices: &self.verts,
            indices: &self.idx,
            labels: &self.labels,
            pins: &self.pin_out,
        }
    }

    #[inline]
    fn push_quad(&mut self, corners: [(f64, f64); 4], uvs: [(f32, f32); 4], w: f32, rgba: [u8; 4]) {
        let base = self.verts.len() as u32;
        let v = |i: usize| Vertex {
            x: corners[i].0 as f32,
            y: corners[i].1 as f32,
            u: uvs[i].0,
            v: uvs[i].1,
            w,
            rgba,
        };
        self.verts.extend_from_slice(&[v(0), v(1), v(2), v(3)]);
        self.idx
            .extend_from_slice(&[base, base + 1, base + 2, base + 2, base + 1, base + 3]);
    }

    /// Antialiased ellipse: `ra` along the radial (foreshortened) axis `dir`,
    /// `rt` along the tangential axis.
    fn push_ellipse(&mut self, x: f64, y: f64, dir: (f64, f64), ra: f64, rt: f64, rgba: [u8; 4]) {
        let fr = 0.5 / self.dpr;
        let (a, t) = (ra + fr, rt + fr);
        let (dx, dy) = dir;
        let (tx, ty) = (-dy, dx);
        let w = (a.min(t) * self.dpr) as f32;
        self.push_quad(
            [
                (x - dx * a - tx * t, y - dy * a - ty * t),
                (x + dx * a - tx * t, y + dy * a - ty * t),
                (x - dx * a + tx * t, y - dy * a + ty * t),
                (x + dx * a + tx * t, y + dy * a + ty * t),
            ],
            [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)],
            w,
            rgba,
        );
    }

    fn push_circle(&mut self, x: f64, y: f64, r: f64, rgba: [u8; 4]) {
        self.push_ellipse(x, y, (1.0, 0.0), r, r, rgba);
    }

    fn push_segment(&mut self, a: (f64, f64), b: (f64, f64), half_width: f64, rgba: [u8; 4]) {
        let (dx, dy) = (b.0 - a.0, b.1 - a.1);
        let len = (dx * dx + dy * dy).sqrt();
        if len < 1e-6 {
            return;
        }
        let min_hw = 0.5 / self.dpr;
        let (hw, rgba) = if half_width < min_hw {
            (min_hw, premul_scale(rgba, (half_width / min_hw) as f32))
        } else {
            (half_width, rgba)
        };
        let he = hw + 0.5 / self.dpr;
        let (tx, ty) = (dx / len, dy / len);
        let (nx, ny) = (-ty * he, tx * he);
        // extend the ends a little so consecutive segments join without gaps
        let ext = hw * 0.5;
        let a = (a.0 - tx * ext, a.1 - ty * ext);
        let b = (b.0 + tx * ext, b.1 + ty * ext);
        let w = (he * self.dpr) as f32;
        self.push_quad(
            [
                (a.0 - nx, a.1 - ny),
                (b.0 - nx, b.1 - ny),
                (a.0 + nx, a.1 + ny),
                (b.0 + nx, b.1 + ny),
            ],
            [(0.0, -1.0), (0.0, -1.0), (0.0, 1.0), (0.0, 1.0)],
            w,
            rgba,
        );
    }

    fn build_dots(&mut self, world: &World, b: &Basis, rho: f64) {
        // Land dots are the hero at globe scale but recede to a texture once
        // borders and place names carry the map: sparser, smaller, dimmer.
        let z = self.zoom();
        let deep = smoothstep(4.5, 9.0, z);
        self.dot_dim = 1.0 - 0.5 * deep;
        self.dot_shrink = 1.0 - 0.25 * deep;
        let target = f64::from(self.style.dot_spacing).max(2.0) * (1.0 + 0.45 * deep);
        let s0 = TAU / 128.0;
        let texel = world.land.texel();
        let kmax = ((s0 / texel).log2().floor() as i32).max(0);
        let level = (b.r * s0 / target).log2();
        let k = (level.floor() as i32).clamp(0, kmax);
        let f = if k == kmax || level < 0.0 {
            0.0
        } else {
            level - f64::from(k)
        };
        let t = if k < kmax {
            smoothstep(0.78, 1.0, f)
        } else {
            0.0
        };
        if t < 0.999 {
            self.dot_level(world, b, rho, s0 / f64::from(1u32 << k), 1.0 - t);
        }
        if t > 0.001 {
            self.dot_level(world, b, rho, s0 / f64::from(1u32 << (k + 1)), t);
        }
    }

    fn dot_level(&mut self, world: &World, b: &Basis, rho: f64, s: f64, alpha: f64) {
        let rows = (PI / s).round().max(2.0) as i64;
        let dlat = PI / rows as f64;
        let spacing_px = s * b.r;
        // Spacing doubles across each zoom octave; capping the radius keeps the
        // halftone fine instead of turning into big blobs late in the octave.
        let target = f64::from(self.style.dot_spacing).max(2.0);
        let radius = (spacing_px * f64::from(self.style.dot_size))
            .min(target * f64::from(self.style.dot_size) * 1.3)
            .clamp(0.55, 5.0)
            * self.dot_shrink;
        let (sl0, cl0) = self.cam.lat.sin_cos();
        let cos_rho = (rho + 0.6 * s).min(PI).cos();
        let margin = radius + 2.0;
        let (w, h) = (self.width, self.height);
        let base = self.style.land;

        let lat_lo = (self.cam.lat - rho - s).max(-FRAC_PI_2);
        let lat_hi = (self.cam.lat + rho + s).min(FRAC_PI_2);
        let i0 = (((lat_lo + FRAC_PI_2) / dlat - 0.5).floor() as i64).max(0);
        let i1 = (((lat_hi + FRAC_PI_2) / dlat - 0.5).ceil() as i64).min(rows - 1);

        for i in i0..=i1 {
            let lat = -FRAC_PI_2 + (i as f64 + 0.5) * dlat;
            let (sl, cl) = lat.sin_cos();
            let n = ((TAU * cl / s).round() as i64).max(1);
            let dlon = TAU / n as f64;

            // longitude window of the visible cap on this row
            let denom = cl * cl0;
            let (j0, j1) = if denom.abs() < 1e-12 {
                if sl * sl0 >= cos_rho {
                    (0, n - 1)
                } else {
                    continue;
                }
            } else {
                let rhs = (cos_rho - sl * sl0) / denom;
                if rhs > 1.0 {
                    continue;
                }
                if rhs <= -1.0 {
                    (0, n - 1)
                } else {
                    let half = rhs.acos() + dlon;
                    let a = ((self.cam.lon - half + PI) / dlon - 0.5).floor() as i64;
                    let z = ((self.cam.lon + half + PI) / dlon - 0.5).ceil() as i64;
                    if z - a + 1 >= n {
                        (0, n - 1)
                    } else {
                        (a, z)
                    }
                }
            };

            // Walk only the land runs of this mask row that intersect the
            // window — ocean positions are never visited.
            let row = world.land.row(world.land.row_of(lat));
            let wmask = f64::from(world.land.width);
            let nf = n as f64;
            let ranges: [(i64, i64); 2] = if j1 - j0 + 1 >= n {
                [(0, n - 1), (1, 0)]
            } else {
                let a = j0.rem_euclid(n);
                let z = a + (j1 - j0);
                if z < n {
                    [(a, z), (1, 0)]
                } else {
                    [(a, n - 1), (0, z - n)]
                }
            };
            for (ra, rb) in ranges {
                if ra > rb {
                    continue;
                }
                let x_lo = ((ra as f64 + 0.5) * wmask / nf).floor() as u16;
                // Land spans start at even toggle indices. An odd count of
                // toggles ≤ x_lo means x_lo is inside the span opened at k-1.
                let mut k = row.partition_point(|&t| t <= x_lo);
                if k % 2 == 1 {
                    k -= 1;
                }
                while k < row.len() {
                    let xs = f64::from(row[k]);
                    let xe = if k + 1 < row.len() {
                        f64::from(row[k + 1])
                    } else {
                        wmask
                    };
                    let ja = ((xs * nf / wmask - 0.5).ceil() as i64).max(ra);
                    let jb = ((xe * nf / wmask - 0.5).ceil() as i64 - 1).min(rb);
                    if ja > rb {
                        break;
                    }
                    for j in ja..=jb {
                        let lon = -PI + (j as f64 + 0.5) * dlon;
                        let (so, co) = lon.sin_cos();
                        let p = [cl * co, cl * so, sl];
                        let (x, y, d) = b.project(p);
                        if d <= 0.0
                            || x < -margin
                            || y < -margin
                            || x > w + margin
                            || y > h + margin
                        {
                            continue;
                        }
                        let (rx, ry) = (x - b.cx, y - b.cy);
                        let rl = (rx * rx + ry * ry).sqrt();
                        let dir = if rl > 1e-3 {
                            (rx / rl, ry / rl)
                        } else {
                            (1.0, 0.0)
                        };
                        // gentle limb darkening sells the sphere
                        let shade = alpha
                            * self.dot_dim
                            * (0.38 + 0.62 * d.sqrt())
                            * smoothstep(0.0, 0.08, d);
                        let rgba = premul(base, shade as f32);
                        self.push_ellipse(x, y, dir, radius * d.max(0.06), radius, rgba);
                    }
                    k += 2;
                }
            }
        }
    }

    fn build_lines(&mut self, world: &World, b: &Basis, rho: f64) {
        let r = b.r;
        let lod = if r < 700.0 {
            0
        } else if r < 3500.0 {
            1
        } else {
            2
        };
        let st = self.style;
        let fade_states = smoothstep(950.0, 1700.0, r);
        // Borders gain weight as they become the main structure of the map.
        let zoom_w = 1.0 + 0.45 * smoothstep(900.0, 6000.0, r);
        let border_alpha = 0.75 + 0.25 * smoothstep(400.0, 900.0, r);
        let jobs: [(LineKind, u8, [u8; 4], f64, f64, bool); 3] = [
            (
                LineKind::State,
                lod.max(1),
                st.state,
                f64::from(st.state_width),
                fade_states,
                false,
            ),
            (
                LineKind::Coast,
                lod,
                st.coast,
                f64::from(st.coast_width) * zoom_w,
                1.0,
                true,
            ),
            (
                LineKind::Country,
                lod,
                st.border,
                f64::from(st.border_width) * zoom_w,
                border_alpha,
                true,
            ),
        ];
        // Pass 1: dark casings under coast and borders, so lines stay legible
        // over the dot field. Pass 2: the lines themselves.
        for casing in [true, false] {
            for &(kind, lod, color, width, alpha, cased) in &jobs {
                if alpha <= 0.01 || (casing && !cased) {
                    continue;
                }
                if let Some(layer) = world.layer(kind, lod) {
                    let (rgba, hw) = if casing {
                        (premul(st.casing, alpha as f32), width * 0.5 + 1.25)
                    } else {
                        (premul(color, alpha as f32), width * 0.5)
                    };
                    self.stroke_layer(layer, b, rho, hw, rgba);
                }
            }
        }
    }

    fn stroke_layer(
        &mut self,
        layer: &super::world::LineLayer,
        b: &Basis,
        rho: f64,
        hw: f64,
        rgba: [u8; 4],
    ) {
        const MIN_SEG2: f64 = 1.8 * 1.8;
        let (w, h) = (self.width, self.height);
        let m = 4.0;
        let outside = |a: (f64, f64), c: (f64, f64)| {
            (a.0 < -m && c.0 < -m)
                || (a.1 < -m && c.1 < -m)
                || (a.0 > w + m && c.0 > w + m)
                || (a.1 > h + m && c.1 > h + m)
        };
        // A chunk is visible iff angle(centre, view) <= rho + radius, i.e.
        // cos(angle) >= cos(rho + radius) = cos ρ·cos r − sin ρ·sin r.
        let (sr, cr) = (rho + 0.01).min(PI).sin_cos();
        for ci in 0..layer.chunks.len() {
            let ch = layer.chunks[ci];
            let cc = f32v(ch.center);
            let limit = if f64::from(ch.radius) + rho + 0.01 >= PI {
                -1.0
            } else {
                cr * f64::from(ch.cos_r) - sr * f64::from(ch.sin_r)
            };
            if dot(cc, b.c) < limit {
                continue;
            }
            let pts = &layer.points[ch.start as usize..(ch.start + ch.len) as usize];
            let mut prev = f32v(pts[0]);
            let (px, py, mut pd) = b.project(prev);
            let mut pen: Option<(f64, f64)> = if pd >= 0.0 { Some((px, py)) } else { None };
            let last = pts.len() - 1;
            for (k, q) in pts.iter().enumerate().skip(1) {
                let p = f32v(*q);
                let (x, y, d) = b.project(p);
                if pd >= 0.0 && d >= 0.0 {
                    if let Some(a) = pen {
                        let (dx, dy) = (x - a.0, y - a.1);
                        if dx * dx + dy * dy >= MIN_SEG2 || k == last {
                            if !outside(a, (x, y)) {
                                self.push_segment(a, (x, y), hw, rgba);
                            }
                            pen = Some((x, y));
                        }
                    } else {
                        pen = Some((x, y));
                    }
                } else if pd >= 0.0 && d < 0.0 {
                    let hp = b.project(normalize(lerp(prev, p, pd / (pd - d))));
                    if let Some(a) = pen {
                        if !outside(a, (hp.0, hp.1)) {
                            self.push_segment(a, (hp.0, hp.1), hw, rgba);
                        }
                    }
                    pen = None;
                } else if pd < 0.0 && d >= 0.0 {
                    let hp = b.project(normalize(lerp(prev, p, pd / (pd - d))));
                    if !outside((hp.0, hp.1), (x, y)) {
                        self.push_segment((hp.0, hp.1), (x, y), hw, rgba);
                    }
                    pen = Some((x, y));
                }
                prev = p;
                pd = d;
            }
        }
    }

    fn build_pins(&mut self, b: &Basis) {
        if self.pins.is_empty() {
            return;
        }
        self.pins.update(b.r, f64::from(self.style.pin_merge));
        for (i, c) in self.pins.clusters.iter().enumerate() {
            let (x, y, d) = b.project(c.pos);
            if d <= 0.0 {
                continue;
            }
            let alpha = smoothstep(0.0, 0.18, d);
            self.pin_out.push(PinOut {
                cluster: i as u32,
                lead: c.lead,
                count: c.weight,
                members: c.members.len() as u32,
                x: x as f32,
                y: y as f32,
                depth: d as f32,
                alpha: alpha as f32,
            });
        }
        // front-most first: hit testing walks this order
        self.pin_out.sort_by(|a, b| b.depth.total_cmp(&a.depth));
    }

    /// Front-most pin cluster whose bubble contains (x, y).
    pub fn pin_at(&self, x: f64, y: f64) -> Option<u32> {
        let (pw, ph) = (
            f64::from(self.style.pin_width),
            f64::from(self.style.pin_height),
        );
        self.pin_out
            .iter()
            .find(|p| {
                p.alpha > 0.3
                    && (x - f64::from(p.x)).abs() <= pw * 0.5 + 4.0
                    && y <= f64::from(p.y) + 6.0
                    && y >= f64::from(p.y) - ph - 4.0
            })
            .map(|p| p.cluster)
    }

    fn label_class(l: &super::world::Label) -> u8 {
        match l.kind {
            LabelKind::Ocean => class::OCEAN,
            LabelKind::Country => class::COUNTRY,
            LabelKind::State => class::STATE,
            LabelKind::City if l.capital || l.population >= 1_000_000 => class::CITY_MAJOR,
            LabelKind::City if l.population >= 100_000 => class::CITY,
            LabelKind::City => class::TOWN,
        }
    }

    fn label_size(l: &super::world::Label, cls: u8) -> (f64, f64) {
        let (px, em, ls) = LABEL_METRICS[cls as usize];
        let n = f64::from(l.chars);
        (n * px * em + (n - 1.0).max(0.0) * ls, px * 1.25)
    }

    fn grid_dims(&self) -> (usize, usize) {
        const CELL: f64 = 48.0;
        (
            ((self.width / CELL).ceil() as usize).max(1),
            ((self.height / CELL).ceil() as usize).max(1),
        )
    }

    fn rect_cells(&self, r: [f64; 4]) -> (usize, usize, usize, usize) {
        const CELL: f64 = 48.0;
        let (gw, gh) = self.grid_dims();
        let c = |v: f64, n: usize| ((v / CELL).floor().max(0.0) as usize).min(n - 1);
        (c(r[0], gw), c(r[1], gh), c(r[2], gw), c(r[3], gh))
    }

    fn try_place(&mut self, r: [f64; 4]) -> bool {
        const PAD: f64 = 5.0;
        let (x0, y0, x1, y1) = self.rect_cells(r);
        let gw = self.grid_dims().0;
        for gy in y0..=y1 {
            for gx in x0..=x1 {
                for &o in &self.grid[gy * gw + gx] {
                    let q = self.rects[o as usize];
                    if r[0] < q[2] + PAD
                        && r[2] + PAD > q[0]
                        && r[1] < q[3] + PAD
                        && r[3] + PAD > q[1]
                    {
                        return false;
                    }
                }
            }
        }
        self.occupy(r);
        true
    }

    fn occupy(&mut self, r: [f64; 4]) {
        let id = self.rects.len() as u16;
        self.rects.push(r);
        let (x0, y0, x1, y1) = self.rect_cells(r);
        let gw = self.grid_dims().0;
        for gy in y0..=y1 {
            for gx in x0..=x1 {
                self.grid[gy * gw + gx].push(id);
            }
        }
    }

    fn build_labels(&mut self, world: &World, b: &Basis, dt: f64) -> bool {
        const MAX_LABELS: usize = 240;
        let (gw, gh) = self.grid_dims();
        self.grid.resize_with(gw * gh, Vec::new);
        self.grid.truncate(gw * gh);
        for c in &mut self.grid {
            c.clear();
        }
        self.rects.clear();

        // Photo pins are obstacles: labels never hide under them.
        let (pw, ph) = (
            f64::from(self.style.pin_width),
            f64::from(self.style.pin_height),
        );
        for i in 0..self.pin_out.len() {
            let p = self.pin_out[i];
            if p.alpha > 0.3 {
                let (x, y) = (f64::from(p.x), f64::from(p.y));
                self.occupy([x - pw * 0.5, y - ph, x + pw * 0.5, y + 2.0]);
            }
        }

        let z = self.zoom() + f64::from(self.style.label_density);
        let (w, h) = (self.width, self.height);
        for st in self.label_state.values_mut() {
            st.placed = false;
        }
        let mut placed = 0usize;
        for oi in 0..world.label_order.len() {
            let id = world.label_order[oi];
            let l = &world.labels[id as usize];
            if f64::from(l.min_zoom) > z {
                break; // sorted ascending — nothing further qualifies
            }
            if placed >= MAX_LABELS {
                break;
            }
            let span = match l.kind {
                LabelKind::Ocean => 3.2,
                LabelKind::Country => 5.5,
                LabelKind::State => 5.0,
                LabelKind::City => 99.0,
            };
            if z > f64::from(l.min_zoom) + span {
                continue;
            }
            let p = f32v(l.pos);
            let d = dot(p, b.c);
            if d < 0.12 {
                continue;
            }
            let (x, y, _) = b.project(p);
            if x < 0.0 || y < 0.0 || x > w || y > h {
                continue;
            }
            let cls = Self::label_class(l);
            let (tw, th) = Self::label_size(l, cls);
            let prev_anchor = self.label_state.get(&id).map(|s| s.anchor);
            let placed_anchor = if cls >= class::CITY_MAJOR {
                let right = [x - 4.0, y - th * 0.5, x + 7.0 + tw, y + th * 0.5];
                let left = [x - 7.0 - tw, y - th * 0.5, x + 4.0, y + th * 0.5];
                let inside =
                    |r: [f64; 4]| r[0] >= 2.0 && r[2] <= w - 2.0 && r[1] >= 2.0 && r[3] <= h - 2.0;
                // keep a label on the side it already sits on to avoid flicker
                let order = if prev_anchor == Some(anchor::LEFT) {
                    [(left, anchor::LEFT), (right, anchor::RIGHT)]
                } else {
                    [(right, anchor::RIGHT), (left, anchor::LEFT)]
                };
                order
                    .into_iter()
                    .find(|&(r, _)| inside(r) && self.try_place(r))
                    .map(|(_, a)| a)
            } else {
                let r = [x - tw * 0.5, y - th * 0.5, x + tw * 0.5, y + th * 0.5];
                let inside = r[0] >= 2.0 && r[2] <= w - 2.0 && r[1] >= 2.0 && r[3] <= h - 2.0;
                (inside && self.try_place(r)).then_some(anchor::CENTER)
            };
            if let Some(a) = placed_anchor {
                placed += 1;
                let st = self.label_state.entry(id).or_insert(LabelState {
                    alpha: 0.0,
                    placed: true,
                    anchor: a,
                });
                st.placed = true;
                st.anchor = a;
            }
        }

        // fade towards the placement state; emit everything still visible
        let step = (dt * 6.0) as f32;
        let mut fading = false;
        let mut emit: Vec<(u32, LabelState)> = Vec::new();
        self.label_state.retain(|&id, st| {
            if st.placed {
                st.alpha = (st.alpha + step).min(1.0);
                fading |= st.alpha < 1.0;
            } else {
                st.alpha -= step;
                if st.alpha <= 0.0 {
                    return false; // fully faded out
                }
                fading = true;
            }
            emit.push((id, *st));
            true
        });

        for (id, st) in emit {
            let l = &world.labels[id as usize];
            let p = f32v(l.pos);
            let (x, y, d) = b.project(p);
            if d < 0.02 {
                continue;
            }
            let cls = Self::label_class(l);
            let alpha = st.alpha * smoothstep(0.12, 0.3, d) as f32;
            if cls >= class::CITY_MAJOR {
                let rad = if l.capital {
                    3.0
                } else if cls == class::TOWN {
                    2.0
                } else {
                    2.5
                };
                let halo = premul(self.style.city_halo, alpha);
                let dotc = premul(self.style.city, alpha);
                self.push_circle(x, y, rad + 1.6, halo);
                self.push_circle(x, y, rad, dotc);
                if l.capital {
                    self.push_circle(x, y, rad * 0.45, halo);
                }
            }
            self.labels.push(LabelOut {
                id,
                x: x as f32,
                y: y as f32,
                alpha,
                class: cls,
                anchor: st.anchor,
                capital: u8::from(l.capital),
                _pad: 0,
            });
        }
        fading
    }
}

#[inline]
fn premul(c: [u8; 4], alpha: f32) -> [u8; 4] {
    let a = (f32::from(c[3]) / 255.0 * alpha.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    [
        (f32::from(c[0]) * a).round() as u8,
        (f32::from(c[1]) * a).round() as u8,
        (f32::from(c[2]) * a).round() as u8,
        (a * 255.0).round() as u8,
    ]
}

#[inline]
fn premul_scale(c: [u8; 4], s: f32) -> [u8; 4] {
    let s = s.clamp(0.0, 1.0);
    [
        (f32::from(c[0]) * s) as u8,
        (f32::from(c[1]) * s) as u8,
        (f32::from(c[2]) * s) as u8,
        (f32::from(c[3]) * s) as u8,
    ]
}

/// Convert pin inputs in degrees.
pub fn pin_input(lat: f64, lon: f64, weight: u32) -> PinInput {
    PinInput {
        pos: from_lat_lon(lat.to_radians(), lon.to_radians()),
        weight,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::geo::world::tests::load;

    fn globe(w: f64, h: f64) -> Globe {
        let mut g = Globe::new();
        g.set_viewport(w, h, 1.0);
        g
    }

    #[test]
    fn projection_roundtrip_and_center() {
        let mut g = globe(1200.0, 800.0);
        g.cam.lat = 0.7;
        g.cam.lon = -1.2;
        let (x, y, d) = g.project_deg(g.cam.lat.to_degrees(), g.cam.lon.to_degrees());
        assert!((x - 600.0).abs() < 1e-6 && (y - 400.0).abs() < 1e-6 && (d - 1.0).abs() < 1e-9);
        let (la, lo) = g.unproject_deg(700.0, 300.0).unwrap();
        let (x2, y2, _) = g.project_deg(la, lo);
        assert!((x2 - 700.0).abs() < 1e-6 && (y2 - 300.0).abs() < 1e-6);
        // north is up, east is right
        let (_, yn, _) = g.project_deg(g.cam.lat.to_degrees() + 1.0, g.cam.lon.to_degrees());
        assert!(yn < 400.0);
        let (xe, _, _) = g.project_deg(g.cam.lat.to_degrees(), g.cam.lon.to_degrees() + 1.0);
        assert!(xe > 600.0);
    }

    #[test]
    fn zoom_keeps_anchor_fixed() {
        let mut g = globe(1000.0, 800.0);
        let before = g.unproject_deg(650.0, 330.0).unwrap();
        g.zoom_by(8.0, 650.0, 330.0, false);
        let (x, y, _) = g.project_deg(before.0, before.1);
        assert!(
            (x - 650.0).abs() < 0.5 && (y - 330.0).abs() < 0.5,
            "{x},{y}"
        );
    }

    #[test]
    fn drag_grabs_the_surface() {
        let mut g = globe(1000.0, 800.0);
        g.zoom_by(30.0, 500.0, 400.0, false);
        let p = g.unproject_deg(500.0, 400.0).unwrap();
        g.drag_begin();
        g.drag(40.0, -25.0);
        let (x, y, _) = g.project_deg(p.0, p.1);
        assert!(
            (x - 540.0).abs() < 1.5 && (y - 375.0).abs() < 1.5,
            "{x},{y}"
        );
    }

    #[test]
    fn fly_to_converges() {
        let mut g = globe(1000.0, 800.0);
        g.fly_to(-33.86, 151.21, 5000.0);
        for _ in 0..400 {
            g.tick(1.0 / 60.0);
        }
        let (x, y, _) = g.project_deg(-33.86, 151.21);
        assert!((x - 500.0).abs() < 0.5 && (y - 400.0).abs() < 0.5);
        assert!((g.cam.r - 5000.0).abs() < 1.0);
    }

    #[test]
    fn builds_frames_at_every_zoom() {
        let world = load();
        let mut g = globe(1400.0, 900.0);
        g.cam.lat = 48f64.to_radians();
        g.cam.lon = 8f64.to_radians();
        g.pins
            .set(vec![pin_input(48.85, 2.35, 12), pin_input(52.52, 13.40, 4)]);
        let mut r = g.fit_radius();
        while r < MAX_RADIUS {
            g.cam.r = r;
            let t = std::time::Instant::now();
            for _ in 0..12 {
                g.build(&world, 1.0 / 60.0);
            }
            let f = g.frame();
            assert!(
                f.vertices.len().is_multiple_of(4) && f.indices.len() == f.vertices.len() / 4 * 6
            );
            assert!(!f.vertices.is_empty(), "nothing drawn at r={r}");
            assert!(f.labels.len() <= 240 + 64);
            for v in f.vertices {
                assert!(v.x.is_finite() && v.y.is_finite() && v.w > 0.0);
            }
            eprintln!(
                "r={r:>8.0} z={:>5.2} verts={:>6} labels={:>3} pins={} {:>6.2} ms/frame",
                g.zoom(),
                f.vertices.len(),
                f.labels.len(),
                f.pins.len(),
                t.elapsed().as_secs_f64() * 1000.0 / 12.0
            );
            r *= 2.0;
        }
    }

    #[test]
    fn labels_progress_from_countries_to_towns() {
        let world = load();
        let mut g = globe(1400.0, 900.0);
        g.cam.lat = 50f64.to_radians();
        g.cam.lon = 10f64.to_radians();
        let classes_at = |g: &mut Globe, r: f64| {
            g.cam.r = r;
            for _ in 0..30 {
                g.build(&world, 0.05);
            }
            g.frame()
                .labels
                .iter()
                .filter(|l| l.alpha > 0.5)
                .map(|l| l.class)
                .collect::<Vec<_>>()
        };
        let far = classes_at(&mut g, 420.0);
        assert!(far.contains(&class::COUNTRY), "{far:?}");
        assert!(!far.contains(&class::TOWN));
        let near = classes_at(&mut g, 40_000.0);
        assert!(
            near.contains(&class::TOWN) || near.contains(&class::CITY),
            "{near:?}"
        );
        assert!(!near.contains(&class::COUNTRY));
    }

    #[test]
    fn pin_hit_testing() {
        let world = load();
        let mut g = globe(1000.0, 800.0);
        g.pins.set(vec![pin_input(10.0, 20.0, 3)]);
        g.fly_to(10.0, 20.0, 0.0);
        for _ in 0..300 {
            g.tick(1.0 / 60.0);
        }
        g.build(&world, 0.0);
        assert_eq!(g.pin_at(500.0, 380.0), Some(0));
        assert_eq!(g.pin_at(100.0, 100.0), None);
    }
}

#[cfg(test)]
mod phase_bench {
    use super::*;
    use crate::geo::world::tests::load;
    #[test]
    fn phases() {
        let world = load();
        let mut g = Globe::new();
        g.set_viewport(1400.0, 900.0, 1.0);
        g.cam.lat = 48f64.to_radians();
        g.cam.lon = 8f64.to_radians();
        for r in [720.0, 5760.0, 23040.0] {
            g.cam.r = r;
            let b = g.basis();
            let half_diag = 0.5 * (1400f64.powi(2) + 900f64.powi(2)).sqrt() + 24.0;
            let rho = if half_diag >= r {
                FRAC_PI_2
            } else {
                (half_diag / r).asin()
            };
            let n = 20;
            let t = std::time::Instant::now();
            for _ in 0..n {
                g.verts.clear();
                g.idx.clear();
                g.build_dots(&world, &b, rho);
            }
            let dots = t.elapsed().as_secs_f64() * 1e3 / n as f64;
            let nd = g.verts.len();
            let t = std::time::Instant::now();
            for _ in 0..n {
                g.verts.clear();
                g.idx.clear();
                g.build_lines(&world, &b, rho);
            }
            let lines = t.elapsed().as_secs_f64() * 1e3 / n as f64;
            let nl = g.verts.len();
            let t = std::time::Instant::now();
            for _ in 0..n {
                g.verts.clear();
                g.idx.clear();
                g.labels.clear();
                g.build_labels(&world, &b, 0.016);
            }
            let labels = t.elapsed().as_secs_f64() * 1e3 / n as f64;
            eprintln!(
                "r={r}: dots {dots:.2}ms ({nd}) lines {lines:.2}ms ({nl}) labels {labels:.2}ms"
            );
        }
    }
}
