//! Decoded world dataset (`assets/geo/world.kgeo`, produced by
//! `tools/geo/bake_world.py`).

use super::math::{dot, from_lat_lon, normalize, V3};
use super::reader::{DecodeError, Reader, Result};

const COORD_SCALE: f64 = 1e-5; // file units → degrees

/// Feature classes of polyline layers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum LineKind {
    Coast = 0,
    Country = 1,
    State = 2,
}

/// Feature classes of labels (matches the bake script).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum LabelKind {
    Country = 0,
    State = 1,
    City = 2,
    Ocean = 3,
}

/// Run-length encoded equirectangular land mask. Each row stores the x
/// positions where land/ocean toggles; rows start as ocean. Kept as runs
/// instead of a bitmap: ~0.6 MB in memory instead of 16 MB.
pub struct LandMask {
    pub width: u32,
    pub height: u32,
    row_start: Vec<u32>,
    toggles: Vec<u16>,
}

impl LandMask {
    fn decode(r: &mut Reader) -> Result<Self> {
        let width = r.varint_usize(65_535)? as u32;
        let height = r.varint_usize(65_535)? as u32;
        if width == 0 || height == 0 {
            return Err(DecodeError("empty land mask"));
        }
        let mut row_start = Vec::with_capacity(height as usize + 1);
        let mut toggles = Vec::new();
        for _ in 0..height {
            row_start.push(toggles.len() as u32);
            let n = r.varint_usize(width as usize + 1)?;
            let mut x = 0u32;
            for i in 0..n {
                x += r.varint_usize(width as usize)? as u32;
                if x > width {
                    return Err(DecodeError("land run overflows row"));
                }
                // The final boundary equals the row width; it never toggles a
                // pixel inside the row, so it is not stored.
                if !(i + 1 == n && x == width) {
                    toggles.push(x as u16);
                }
            }
        }
        row_start.push(toggles.len() as u32);
        Ok(Self {
            width,
            height,
            row_start,
            toggles,
        })
    }

    /// Is the pixel at (x, y) land?
    #[inline]
    pub fn at(&self, x: u32, y: u32) -> bool {
        let y = y.min(self.height - 1) as usize;
        let row = &self.toggles[self.row_start[y] as usize..self.row_start[y + 1] as usize];
        let x = x.min(self.width - 1) as u16;
        // number of toggles at or before x; odd → land
        row.partition_point(|&t| t <= x) % 2 == 1
    }

    /// Is the point (radians) on land?
    #[inline]
    pub fn is_land(&self, lat: f64, lon: f64) -> bool {
        let w = f64::from(self.width);
        let h = f64::from(self.height);
        let x = ((lon + std::f64::consts::PI) / std::f64::consts::TAU * w).floor();
        let y = ((std::f64::consts::FRAC_PI_2 - lat) / std::f64::consts::PI * h).floor();
        self.at(x.rem_euclid(w) as u32, y.clamp(0.0, h - 1.0) as u32)
    }

    /// Toggle positions of row `y` (row starts as ocean; land between
    /// toggles 0–1, 2–3, …, and from an unpaired last toggle to the end).
    #[inline]
    pub fn row(&self, y: u32) -> &[u16] {
        let y = y.min(self.height - 1) as usize;
        &self.toggles[self.row_start[y] as usize..self.row_start[y + 1] as usize]
    }

    /// Row index for a latitude in radians.
    #[inline]
    pub fn row_of(&self, lat: f64) -> u32 {
        let h = f64::from(self.height);
        ((std::f64::consts::FRAC_PI_2 - lat) / std::f64::consts::PI * h)
            .floor()
            .clamp(0.0, h - 1.0) as u32
    }

    /// Angular size of one mask pixel, in radians.
    pub fn texel(&self) -> f64 {
        std::f64::consts::TAU / f64::from(self.width)
    }
}

/// A contiguous run of points of one polyline, with a bounding cap used for
/// visibility culling.
#[derive(Debug, Clone, Copy)]
pub struct Chunk {
    pub start: u32,
    pub len: u32,
    pub center: [f32; 3],
    /// Angular radius of the bounding cap, radians.
    pub radius: f32,
    /// cos/sin of `radius`, so culling needs no inverse trig.
    pub cos_r: f32,
    pub sin_r: f32,
}

pub struct LineLayer {
    pub kind: LineKind,
    pub lod: u8,
    /// Unit vectors. f32 is ~0.4 m on Earth's surface — far below a pixel.
    pub points: Vec<[f32; 3]>,
    pub chunks: Vec<Chunk>,
}

const CHUNK_POINTS: usize = 48;

impl LineLayer {
    fn decode(r: &mut Reader) -> Result<Self> {
        let kind = match r.u8()? {
            0 => LineKind::Coast,
            1 => LineKind::Country,
            2 => LineKind::State,
            _ => return Err(DecodeError("unknown line kind")),
        };
        let lod = r.u8()?;
        let n_lines = r.varint_usize(10_000_000)?;
        let mut points: Vec<[f32; 3]> = Vec::new();
        let mut chunks = Vec::new();
        let mut line: Vec<V3> = Vec::new();
        for _ in 0..n_lines {
            let n = r.varint_usize(50_000_000)?;
            line.clear();
            let (mut qx, mut qy) = (0i64, 0i64);
            for i in 0..n {
                if i == 0 {
                    qx = r.zigzag()?;
                    qy = r.zigzag()?;
                } else {
                    qx += r.zigzag()?;
                    qy += r.zigzag()?;
                }
                let lon = (qx as f64 * COORD_SCALE).to_radians();
                let lat = (qy as f64 * COORD_SCALE).to_radians();
                line.push(from_lat_lon(lat, lon));
            }
            // Chunks overlap by one point so segments across chunk borders are kept.
            let mut s = 0usize;
            while s + 1 < line.len() {
                let e = (s + CHUNK_POINTS).min(line.len() - 1);
                let pts = &line[s..=e];
                let mut c = [0.0; 3];
                for p in pts {
                    c = [c[0] + p[0], c[1] + p[1], c[2] + p[2]];
                }
                let c = normalize(c);
                let min_cos = pts.iter().map(|p| dot(*p, c)).fold(1.0f64, f64::min);
                let start = points.len() as u32;
                points.extend(pts.iter().map(|p| [p[0] as f32, p[1] as f32, p[2] as f32]));
                chunks.push(Chunk {
                    start,
                    len: pts.len() as u32,
                    center: [c[0] as f32, c[1] as f32, c[2] as f32],
                    radius: (min_cos.clamp(-1.0, 1.0).acos() + 1e-4) as f32,
                    cos_r: (min_cos.clamp(-1.0, 1.0).acos() + 1e-4).cos() as f32,
                    sin_r: (min_cos.clamp(-1.0, 1.0).acos() + 1e-4).sin() as f32,
                });
                s = e;
            }
        }
        Ok(Self {
            kind,
            lod,
            points,
            chunks,
        })
    }
}

#[derive(Debug, Clone)]
pub struct Label {
    pub pos: [f32; 3],
    pub kind: LabelKind,
    pub capital: bool,
    /// Web-mercator-equivalent zoom from which the label may appear.
    pub min_zoom: f32,
    pub population: u32,
    /// 1-based index into [`World::countries`], 0 = unknown.
    pub country: u16,
    name_off: u32,
    name_len: u16,
    /// Number of characters (for width estimates without font metrics).
    pub chars: u16,
}

pub struct Country {
    pub iso: [u8; 2],
    pub name: String,
}

pub struct World {
    pub land: LandMask,
    pub lines: Vec<LineLayer>,
    pub labels: Vec<Label>,
    pub countries: Vec<Country>,
    names: String,
    /// Label indices sorted by priority: min_zoom ascending, population desc.
    pub label_order: Vec<u32>,
    /// City labels bucketed into 1°×1° cells for nearest-place queries.
    city_cells: std::collections::HashMap<(i16, i16), Vec<u32>>,
}

/// Result of [`World::place_name`].
#[derive(Debug, Clone, PartialEq)]
pub struct Place<'a> {
    pub city: &'a str,
    pub country: Option<&'a str>,
    pub distance_km: f64,
}

#[inline]
fn cell_of(lat_deg: f64, lon_deg: f64) -> (i16, i16) {
    (
        lat_deg.floor().clamp(-90.0, 89.0) as i16,
        lon_deg.floor().clamp(-180.0, 179.0) as i16,
    )
}

impl World {
    pub fn decode(data: &[u8]) -> Result<Self> {
        let mut r = Reader::new(data);
        if r.bytes(4)? != b"KGEO" {
            return Err(DecodeError("bad magic"));
        }
        let version = r.u16()?;
        if version != 1 {
            return Err(DecodeError("unsupported version"));
        }
        let n_sections = r.u16()?;
        let mut land = None;
        let mut lines = Vec::new();
        let mut labels = Vec::new();
        let mut countries = Vec::new();
        let mut names = String::new();
        for _ in 0..n_sections {
            let tag: [u8; 4] = r.bytes(4)?.try_into().map_err(|_| DecodeError("tag"))?;
            let len = r.u32()? as usize;
            let mut s = Reader::new(r.bytes(len)?);
            match &tag {
                b"LAND" => land = Some(LandMask::decode(&mut s)?),
                b"LINE" => lines.push(LineLayer::decode(&mut s)?),
                b"LABL" => Self::decode_labels(&mut s, &mut labels, &mut names)?,
                b"CTRY" => {
                    let n = s.varint_usize(4096)?;
                    for _ in 0..n {
                        let iso: [u8; 2] =
                            s.bytes(2)?.try_into().map_err(|_| DecodeError("iso"))?;
                        let len = s.varint_usize(512)?;
                        let name = std::str::from_utf8(s.bytes(len)?)
                            .map_err(|_| DecodeError("country utf-8"))?;
                        countries.push(Country {
                            iso,
                            name: name.to_owned(),
                        });
                    }
                }
                _ => {} // forward compatible: ignore unknown sections
            }
        }
        let land = land.ok_or(DecodeError("missing land mask"))?;
        let mut label_order: Vec<u32> = (0..labels.len() as u32).collect();
        label_order.sort_by(|&a, &b| {
            let (la, lb) = (&labels[a as usize], &labels[b as usize]);
            la.min_zoom
                .total_cmp(&lb.min_zoom)
                .then(lb.population.cmp(&la.population))
                .then(a.cmp(&b))
        });
        let mut city_cells: std::collections::HashMap<(i16, i16), Vec<u32>> = Default::default();
        for (i, l) in labels.iter().enumerate() {
            if l.kind == LabelKind::City {
                let (la, lo) = super::math::to_lat_lon(super::math::f32v(l.pos));
                city_cells
                    .entry(cell_of(la.to_degrees(), lo.to_degrees()))
                    .or_default()
                    .push(i as u32);
            }
        }
        Ok(Self {
            land,
            lines,
            labels,
            countries,
            names,
            label_order,
            city_cells,
        })
    }

    /// Nearest town (5000+ inhabitants) to a point, within `max_km`. Prefers
    /// bigger places when they are almost as close, so a suburb resolves to
    /// its city.
    pub fn place_name(&self, lat_deg: f64, lon_deg: f64, max_km: f64) -> Option<Place<'_>> {
        const EARTH_KM: f64 = 6371.0;
        let p = from_lat_lon(lat_deg.to_radians(), lon_deg.to_radians());
        let reach = (max_km / 111.0).ceil().clamp(1.0, 5.0) as i16;
        let (cla, clo) = cell_of(lat_deg, lon_deg);
        // Two passes: find the nearest town, then let bigger places win only
        // when they are almost as close (a suburb resolves to its city, but a
        // village 30 km from a capital keeps its own name).
        let mut cands: Vec<(f64, u32)> = Vec::new();
        for dla in -reach..=reach {
            for dlo in -reach..=reach {
                let mut lo = clo + dlo;
                if lo < -180 {
                    lo += 360;
                } else if lo > 179 {
                    lo -= 360;
                }
                let Some(ids) = self.city_cells.get(&(cla + dla, lo)) else {
                    continue;
                };
                for &id in ids {
                    let l = &self.labels[id as usize];
                    let km = dot(p, super::math::f32v(l.pos)).clamp(-1.0, 1.0).acos() * EARTH_KM;
                    if km <= max_km {
                        cands.push((km, id));
                    }
                }
            }
        }
        let nearest = cands.iter().map(|c| c.0).fold(f64::INFINITY, f64::min);
        let window = (nearest * 1.8).max(nearest + 4.0);
        let mut best: Option<(f64, f64, u32)> = None; // (score, km, id)
        for &(km, id) in cands.iter().filter(|c| c.0 <= window) {
            let pop = f64::from(self.labels[id as usize].population.max(5000));
            let score = (km + 1.0) / (1.0 + (pop / 5000.0).log10() * 0.8);
            if best.is_none_or(|b| score < b.0) {
                best = Some((score, km, id));
            }
        }
        let (_, km, id) = best?;
        let l = &self.labels[id as usize];
        Some(Place {
            city: self.label_name(id as usize)?,
            country: (l.country > 0)
                .then(|| self.countries.get(l.country as usize - 1))
                .flatten()
                .map(|c| c.name.as_str()),
            distance_km: km,
        })
    }

    fn decode_labels(r: &mut Reader, labels: &mut Vec<Label>, names: &mut String) -> Result<()> {
        let n = r.varint_usize(5_000_000)?;
        labels.reserve(n);
        for _ in 0..n {
            let kind = match r.u8()? {
                0 => LabelKind::Country,
                1 => LabelKind::State,
                2 => LabelKind::City,
                3 => LabelKind::Ocean,
                _ => return Err(DecodeError("unknown label kind")),
            };
            let flags = r.u8()?;
            let lon = (r.zigzag()? as f64 * COORD_SCALE).to_radians();
            let lat = (r.zigzag()? as f64 * COORD_SCALE).to_radians();
            let min_zoom = f32::from(r.u8()?) / 16.0;
            let population = r.varint()?.min(u64::from(u32::MAX)) as u32;
            let country = r.varint()?.min(u64::from(u16::MAX)) as u16;
            let len = r.varint_usize(4096)?;
            let name =
                std::str::from_utf8(r.bytes(len)?).map_err(|_| DecodeError("label utf-8"))?;
            let p = from_lat_lon(lat, lon);
            labels.push(Label {
                pos: [p[0] as f32, p[1] as f32, p[2] as f32],
                kind,
                capital: flags & 1 != 0,
                min_zoom,
                population,
                country,
                name_off: names.len() as u32,
                name_len: name.len() as u16,
                chars: name.chars().count().min(u16::MAX as usize) as u16,
            });
            names.push_str(name);
        }
        Ok(())
    }

    pub fn label_name(&self, id: usize) -> Option<&str> {
        let l = self.labels.get(id)?;
        let s = l.name_off as usize;
        self.names.get(s..s + l.name_len as usize)
    }

    pub fn layer(&self, kind: LineKind, lod: u8) -> Option<&LineLayer> {
        self.lines.iter().find(|l| l.kind == kind && l.lod == lod)
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub fn load() -> World {
        let path = concat!(env!("CARGO_MANIFEST_DIR"), "/../../assets/geo/world.kgeo");
        let data = std::fs::read(path).expect("world.kgeo present");
        World::decode(&data).expect("decodes")
    }

    #[test]
    fn decodes_bundled_world() {
        let w = load();
        assert!(w.lines.len() >= 6);
        assert!(w.labels.len() > 1000);
        assert!(w.layer(LineKind::Coast, 2).unwrap().points.len() > 100_000);
        // spot-check the land mask
        let land = |lat: f64, lon: f64| w.land.is_land(lat.to_radians(), lon.to_radians());
        assert!(land(48.85, 2.35), "Paris");
        assert!(land(-23.55, -46.63), "São Paulo");
        assert!(land(35.68, 139.69), "Tokyo");
        assert!(land(-25.0, 134.0), "central Australia");
        assert!(!land(0.0, -150.0), "Pacific");
        assert!(!land(30.0, -40.0), "Atlantic");
        assert!(!land(-30.0, 80.0), "Indian ocean");
        assert!(!land(44.0, -87.0), "Lake Michigan");
        // labels resolve and the priority order puts big things first
        let first = w.label_order[..20]
            .iter()
            .map(|&i| w.label_name(i as usize).unwrap().to_string())
            .collect::<Vec<_>>();
        assert!(first.iter().any(|n| n.contains("Ocean")), "{first:?}");
        assert!(w
            .labels
            .iter()
            .enumerate()
            .any(|(i, l)| l.capital && w.label_name(i) == Some("Paris")));
    }

    #[test]
    fn offline_place_names() {
        let w = load();
        let p = w.place_name(48.8566, 2.3522, 30.0).unwrap();
        assert_eq!((p.city, p.country), ("Paris", Some("France")));
        let p = w.place_name(40.7128, -74.0060, 30.0).unwrap();
        assert_eq!(p.country, Some("United States"));
        assert!(
            w.place_name(0.0, -140.0, 30.0).is_none(),
            "middle of the Pacific"
        );
        // Muizenberg (a town in its own right) must not become "Cape Town"
        let p = w.place_name(-34.07, 18.45, 250.0).unwrap();
        assert!(p.distance_km < 10.0, "{p:?}");
    }

    #[test]
    fn rejects_garbage() {
        assert!(World::decode(b"nope").is_err());
        assert!(World::decode(b"KGEO\x01\x00\x01\x00LAND\xff\xff\xff\xff").is_err());
    }
}
