//! Small vector helpers. Positions on the globe are unit vectors in an
//! Earth-centred frame: +x = (0°N, 0°E), +y = (0°N, 90°E), +z = north pole.

pub type V3 = [f64; 3];

#[inline]
pub fn dot(a: V3, b: V3) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

#[inline]
pub fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

#[inline]
pub fn scale(a: V3, s: f64) -> V3 {
    [a[0] * s, a[1] * s, a[2] * s]
}

#[inline]
pub fn lerp(a: V3, b: V3, t: f64) -> V3 {
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    ]
}

#[inline]
pub fn normalize(a: V3) -> V3 {
    let l = dot(a, a).sqrt();
    if l > 0.0 {
        scale(a, 1.0 / l)
    } else {
        [1.0, 0.0, 0.0]
    }
}

/// Latitude/longitude in radians → unit vector.
#[inline]
pub fn from_lat_lon(lat: f64, lon: f64) -> V3 {
    let (sl, cl) = lat.sin_cos();
    let (so, co) = lon.sin_cos();
    [cl * co, cl * so, sl]
}

/// Unit vector → (lat, lon) in radians.
#[inline]
pub fn to_lat_lon(p: V3) -> (f64, f64) {
    (p[2].clamp(-1.0, 1.0).asin(), p[1].atan2(p[0]))
}

#[inline]
pub fn f32v(p: [f32; 3]) -> V3 {
    [f64::from(p[0]), f64::from(p[1]), f64::from(p[2])]
}

/// Wrap an angle to (-π, π].
#[inline]
pub fn wrap_pi(a: f64) -> f64 {
    let t = std::f64::consts::TAU;
    let mut a = (a + std::f64::consts::PI).rem_euclid(t) - std::f64::consts::PI;
    if a <= -std::f64::consts::PI {
        a += t;
    }
    a
}

#[inline]
pub fn smoothstep(e0: f64, e1: f64, x: f64) -> f64 {
    let t = ((x - e0) / (e1 - e0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        for &(lat, lon) in &[(0.0, 0.0), (45.0, 120.0), (-33.9, 151.2), (89.0, -179.0)] {
            let (la, lo) = to_lat_lon(from_lat_lon(f64::to_radians(lat), f64::to_radians(lon)));
            assert!((la.to_degrees() - lat).abs() < 1e-9);
            assert!((lo.to_degrees() - lon).abs() < 1e-9);
        }
    }

    #[test]
    fn wrap() {
        assert!((wrap_pi(3.0 * std::f64::consts::PI) - std::f64::consts::PI).abs() < 1e-12);
        assert!((wrap_pi(-0.5) + 0.5).abs() < 1e-12);
    }
}
