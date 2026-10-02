//! TIFF/EXIF reader: capture date, GPS position, orientation and pixel size.
//! Used for EXIF blocks embedded in JPEG/PNG/WebP/HEIC and for TIFF-based
//! RAW files (NEF, CR2, ARW, DNG, PEF, SRW, ORF, RW2), which are TIFF files.

use super::source::Source;
use super::Meta;

const MAX_ENTRIES: usize = 1024;

#[derive(Clone, Copy)]
struct Tiff<'a> {
    src: &'a dyn Source,
    base: u64,
    le: bool,
}

#[derive(Clone, Copy)]
struct Entry {
    tag: u16,
    typ: u16,
    count: u32,
    raw: [u8; 4],
}

fn type_size(typ: u16) -> usize {
    match typ {
        1 | 2 | 6 | 7 => 1,
        3 | 8 => 2,
        4 | 9 | 11 => 4,
        5 | 10 | 12 => 8,
        _ => 0,
    }
}

impl<'a> Tiff<'a> {
    fn u16(&self, b: &[u8], o: usize) -> Option<u16> {
        let v: [u8; 2] = b.get(o..o + 2)?.try_into().ok()?;
        Some(if self.le {
            u16::from_le_bytes(v)
        } else {
            u16::from_be_bytes(v)
        })
    }

    fn u32(&self, b: &[u8], o: usize) -> Option<u32> {
        let v: [u8; 4] = b.get(o..o + 4)?.try_into().ok()?;
        Some(if self.le {
            u32::from_le_bytes(v)
        } else {
            u32::from_be_bytes(v)
        })
    }

    fn ifd(&self, off: u32) -> Option<Vec<Entry>> {
        let head = self.src.read_exact_at(self.base + u64::from(off), 2)?;
        let n = usize::from(self.u16(&head, 0)?).min(MAX_ENTRIES);
        let body = self
            .src
            .read_exact_at(self.base + u64::from(off) + 2, n * 12)?;
        let mut out = Vec::with_capacity(n);
        for i in 0..n {
            let e = &body[i * 12..i * 12 + 12];
            out.push(Entry {
                tag: self.u16(e, 0)?,
                typ: self.u16(e, 2)?,
                count: self.u32(e, 4)?,
                raw: e[8..12].try_into().ok()?,
            });
        }
        Some(out)
    }

    /// Value bytes of an entry (inline or at its offset).
    fn bytes(&self, e: &Entry) -> Option<Vec<u8>> {
        let size = type_size(e.typ).checked_mul(e.count as usize)?;
        if size == 0 || size > 1 << 16 {
            return None;
        }
        if size <= 4 {
            return Some(e.raw[..size].to_vec());
        }
        let off = self.u32(&e.raw, 0)?;
        self.src.read_exact_at(self.base + u64::from(off), size)
    }

    fn uint(&self, e: &Entry) -> Option<u32> {
        match e.typ {
            3 => self.u16(&e.raw, 0).map(u32::from),
            4 | 9 => self.u32(&e.raw, 0),
            _ => None,
        }
    }

    fn ascii(&self, e: &Entry) -> Option<String> {
        if e.typ != 2 && e.typ != 7 {
            return None;
        }
        let b = self.bytes(e)?;
        let end = b.iter().position(|&c| c == 0).unwrap_or(b.len());
        Some(String::from_utf8_lossy(&b[..end]).trim().to_string())
    }

    fn rationals(&self, e: &Entry) -> Option<Vec<f64>> {
        if e.typ != 5 && e.typ != 10 {
            return None;
        }
        let b = self.bytes(e)?;
        (0..e.count as usize)
            .map(|i| {
                let n = self.u32(&b, i * 8)?;
                let d = self.u32(&b, i * 8 + 4)?;
                let (n, d) = if e.typ == 10 {
                    (f64::from(n as i32), f64::from(d as i32))
                } else {
                    (f64::from(n), f64::from(d))
                };
                (d != 0.0).then_some(n / d)
            })
            .collect()
    }
}

/// "YYYY:MM:DD HH:MM:SS" (also accepts '-' date separators).
pub fn parse_datetime(s: &str) -> Option<super::DateTime> {
    let b = s.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let num = |r: std::ops::Range<usize>| -> Option<u32> {
        std::str::from_utf8(b.get(r)?).ok()?.parse().ok()
    };
    let dt = super::DateTime {
        year: num(0..4)? as u16,
        month: num(5..7)? as u8,
        day: num(8..10)? as u8,
        hour: num(11..13)? as u8,
        minute: num(14..16)? as u8,
        second: num(17..19)? as u8,
    };
    dt.is_valid().then_some(dt)
}

/// Parses a TIFF structure starting at `base` in `src` into `meta`.
/// Returns false if there is no valid TIFF header.
pub fn parse_tiff(src: &dyn Source, base: u64, meta: &mut Meta) -> bool {
    let Some(h) = src.read_exact_at(base, 8) else {
        return false;
    };
    let le = match &h[..2] {
        b"II" => true,
        b"MM" => false,
        _ => return false,
    };
    let t = Tiff { src, base, le };
    // 42 = TIFF; 0x4F52/0x5352 = Olympus ORF; 0x55 = Panasonic RW2
    if !matches!(t.u16(&h, 2), Some(42 | 0x4F52 | 0x5352 | 0x55)) {
        return false;
    }
    let Some(ifd0_off) = t.u32(&h, 4) else {
        return false;
    };
    let Some(ifd0) = t.ifd(ifd0_off) else {
        return true;
    };

    let (mut exif_ptr, mut gps_ptr) = (None, None);
    let (mut tw, mut th) = (0u32, 0u32);
    let mut date_ifd0 = None;
    for e in &ifd0 {
        match e.tag {
            0x0100 => tw = t.uint(e).unwrap_or(0),
            0x0101 => th = t.uint(e).unwrap_or(0),
            0x0112 => meta.orientation = t.uint(e).unwrap_or(0) as u16,
            0x0132 => date_ifd0 = t.ascii(e).and_then(|s| parse_datetime(&s)),
            0x8769 => exif_ptr = t.uint(e),
            0x8825 => gps_ptr = t.uint(e),
            _ => {}
        }
    }

    let (mut dto, mut dtd, mut px, mut py) = (None, None, 0u32, 0u32);
    if let Some(ifd) = exif_ptr.filter(|&p| p != ifd0_off).and_then(|p| t.ifd(p)) {
        for e in &ifd {
            match e.tag {
                0x9003 => dto = t.ascii(e).and_then(|s| parse_datetime(&s)),
                0x9004 => dtd = t.ascii(e).and_then(|s| parse_datetime(&s)),
                0xA002 => px = t.uint(e).unwrap_or(0),
                0xA003 => py = t.uint(e).unwrap_or(0),
                _ => {}
            }
        }
    }
    if meta.date.is_none() {
        meta.date = dto.or(dtd).or(date_ifd0);
    }
    if meta.width == 0 || meta.height == 0 {
        if px > 0 && py > 0 {
            meta.width = px;
            meta.height = py;
        } else if tw > 64 && th > 64 {
            meta.tiff_width = tw;
            meta.tiff_height = th;
        }
    }

    if let Some(ifd) = gps_ptr.filter(|&p| p != ifd0_off).and_then(|p| t.ifd(p)) {
        let (mut lat, mut lon, mut lat_ref, mut lon_ref) = (None, None, b'N', b'E');
        for e in &ifd {
            match e.tag {
                1 => lat_ref = t.ascii(e).and_then(|s| s.bytes().next()).unwrap_or(b'N'),
                2 => lat = t.rationals(e),
                3 => lon_ref = t.ascii(e).and_then(|s| s.bytes().next()).unwrap_or(b'E'),
                4 => lon = t.rationals(e),
                _ => {}
            }
        }
        let dms = |v: Vec<f64>| -> Option<f64> {
            let d = *v.first()?;
            Some(
                d + v.get(1).copied().unwrap_or(0.0) / 60.0
                    + v.get(2).copied().unwrap_or(0.0) / 3600.0,
            )
        };
        if let (Some(la), Some(lo)) = (lat.and_then(dms), lon.and_then(dms)) {
            let la = if lat_ref == b'S' { -la } else { la };
            let lo = if lon_ref == b'W' { -lo } else { lo };
            meta.set_gps(la, lo);
        }
    }
    true
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::scan::source::Mem;

    /// Minimal little-endian TIFF: IFD0 → Exif IFD (date, size) + GPS IFD.
    pub fn sample_tiff() -> Vec<u8> {
        let mut b = Vec::new();
        b.extend_from_slice(b"II\x2a\x00\x08\x00\x00\x00");
        let ifd0 = 8u32;
        let exif = ifd0 + 2 + 3 * 12 + 4; // after IFD0
        let gps = exif + 2 + 3 * 12 + 4;
        let date = gps + 2 + 4 * 12 + 4;
        let rats = date + 20;
        let push_entry = |b: &mut Vec<u8>, tag: u16, typ: u16, count: u32, val: u32| {
            b.extend_from_slice(&tag.to_le_bytes());
            b.extend_from_slice(&typ.to_le_bytes());
            b.extend_from_slice(&count.to_le_bytes());
            b.extend_from_slice(&val.to_le_bytes());
        };
        b.extend_from_slice(&3u16.to_le_bytes());
        push_entry(&mut b, 0x0112, 3, 1, 6);
        push_entry(&mut b, 0x8769, 4, 1, exif);
        push_entry(&mut b, 0x8825, 4, 1, gps);
        b.extend_from_slice(&0u32.to_le_bytes());
        b.extend_from_slice(&3u16.to_le_bytes());
        push_entry(&mut b, 0x9003, 2, 20, date);
        push_entry(&mut b, 0xA002, 4, 1, 4000);
        push_entry(&mut b, 0xA003, 4, 1, 3000);
        b.extend_from_slice(&0u32.to_le_bytes());
        b.extend_from_slice(&4u16.to_le_bytes());
        push_entry(&mut b, 1, 2, 2, u32::from(b'S'));
        push_entry(&mut b, 2, 5, 3, rats);
        push_entry(&mut b, 3, 2, 2, u32::from(b'E'));
        push_entry(&mut b, 4, 5, 3, rats + 24);
        b.extend_from_slice(&0u32.to_le_bytes());
        b.extend_from_slice(b"2024:07:09 14:05:33\0");
        for (n, d) in [
            (33u32, 1u32),
            (55, 1),
            (2970, 100),
            (18, 1),
            (25, 1),
            (2676, 100),
        ] {
            b.extend_from_slice(&n.to_le_bytes());
            b.extend_from_slice(&d.to_le_bytes());
        }
        b
    }

    #[test]
    fn reads_date_size_gps_orientation() {
        let tiff = sample_tiff();
        let mut m = Meta::default();
        assert!(parse_tiff(&Mem(&tiff), 0, &mut m));
        assert_eq!(m.orientation, 6);
        assert_eq!((m.width, m.height), (4000, 3000));
        let d = m.date.unwrap();
        assert_eq!(
            (d.year, d.month, d.day, d.hour, d.minute, d.second),
            (2024, 7, 9, 14, 5, 33)
        );
        let (la, lo) = m.gps.unwrap();
        assert!(
            (la + 33.9249).abs() < 1e-3 && (lo - 18.4241).abs() < 1e-3,
            "{la} {lo}"
        );
    }

    #[test]
    fn survives_garbage() {
        let mut m = Meta::default();
        assert!(!parse_tiff(&Mem(b"nope"), 0, &mut m));
        // valid header pointing nowhere
        assert!(parse_tiff(&Mem(b"II\x2a\x00\xff\xff\xff\x7f"), 0, &mut m));
        // self-referencing exif pointer is ignored
        let mut t = sample_tiff();
        t[22..26].copy_from_slice(&8u32.to_le_bytes());
        let mut m = Meta::default();
        assert!(parse_tiff(&Mem(&t), 0, &mut m));
        // truncated at every length: never panics
        let full = sample_tiff();
        for n in 0..full.len() {
            let mut m = Meta::default();
            let _ = parse_tiff(&Mem(&full[..n]), 0, &mut m);
        }
    }

    #[test]
    fn datetime_validation() {
        assert!(parse_datetime("0000:00:00 00:00:00").is_none());
        assert!(parse_datetime("2023-05-18 10:00:00").is_some());
        assert!(parse_datetime("2023:13:18 10:00:00").is_none());
    }
}
