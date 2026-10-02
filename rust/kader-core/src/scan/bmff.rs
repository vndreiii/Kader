//! ISO base media file format (HEIC/AVIF stills, MP4/MOV video): a box walker
//! that reads only box headers and the few small leaf boxes it needs.

use super::exif::{parse_datetime, parse_tiff};
use super::source::{be16, be32, be64, Source};
use super::{DateTime, Meta};

#[derive(Clone, Copy, Debug)]
struct BoxHdr {
    typ: [u8; 4],
    /// Payload start and end (absolute file offsets).
    body: u64,
    end: u64,
}

fn read_box(src: &dyn Source, pos: u64, limit: u64) -> Option<BoxHdr> {
    if pos + 8 > limit {
        return None;
    }
    let h = src
        .read_exact_at(pos, 16)
        .or_else(|| src.read_exact_at(pos, 8))?;
    let size32 = be32(&h, 0)?;
    let typ: [u8; 4] = h[4..8].try_into().ok()?;
    let (size, hdr) = match size32 {
        0 => (limit - pos, 8),
        1 => (be64(&h, 8)?, 16),
        s => (u64::from(s), 8),
    };
    if size < hdr || pos.checked_add(size)? > limit {
        return None;
    }
    Some(BoxHdr {
        typ,
        body: pos + hdr,
        end: pos + size,
    })
}

/// Children of a container box (or the file when `start..end` is the file).
fn children(src: &dyn Source, start: u64, end: u64) -> Vec<BoxHdr> {
    let mut out = Vec::new();
    let mut pos = start;
    while out.len() < 4096 {
        match read_box(src, pos, end) {
            Some(b) => {
                pos = b.end;
                out.push(b);
            }
            None => break,
        }
    }
    out
}

fn find<'a>(boxes: &'a [BoxHdr], typ: &[u8; 4]) -> Option<&'a BoxHdr> {
    boxes.iter().find(|b| &b.typ == typ)
}

fn body(src: &dyn Source, b: &BoxHdr, max: usize) -> Option<Vec<u8>> {
    let len = usize::try_from(b.end - b.body).ok()?.min(max);
    src.read_exact_at(b.body, len)
}

fn uint(b: &[u8], o: usize, size: u8) -> Option<u64> {
    match size {
        0 => Some(0),
        2 => be16(b, o).map(u64::from),
        4 => be32(b, o).map(u64::from),
        8 => be64(b, o),
        _ => None,
    }
}

/// Brand of the `ftyp` box, if the file starts with one.
pub fn brand(src: &dyn Source) -> Option<[u8; 4]> {
    let h = src.read_exact_at(0, 12)?;
    (&h[4..8] == b"ftyp")
        .then(|| h[8..12].try_into().ok())
        .flatten()
}

pub fn is_bmff(src: &dyn Source) -> bool {
    src.read_exact_at(4, 4)
        .map(|t| {
            matches!(
                &t[..],
                b"ftyp" | b"moov" | b"mdat" | b"wide" | b"free" | b"skip"
            )
        })
        .unwrap_or(false)
}

// ── HEIC / AVIF ─────────────────────────────────────────────────────────────

pub fn heif(src: &dyn Source, meta: &mut Meta) -> bool {
    let top = children(src, 0, src.len());
    let Some(m) = find(&top, b"meta") else {
        return false;
    };
    let kids = children(src, m.body + 4, m.end); // FullBox: skip version/flags

    // largest `ispe` = the primary image (thumbnails are smaller)
    if let Some(iprp) = find(&kids, b"iprp") {
        let props = children(src, iprp.body, iprp.end);
        if let Some(ipco) = find(&props, b"ipco") {
            let mut rotate = false;
            for p in children(src, ipco.body, ipco.end) {
                match &p.typ {
                    b"ispe" => {
                        if let Some(b) = body(src, &p, 12) {
                            let (w, h) = (be32(&b, 4).unwrap_or(0), be32(&b, 8).unwrap_or(0));
                            if u64::from(w) * u64::from(h)
                                > u64::from(meta.width) * u64::from(meta.height)
                            {
                                meta.width = w;
                                meta.height = h;
                            }
                        }
                    }
                    b"irot" => {
                        if let Some(b) = body(src, &p, 1) {
                            rotate = b[0] & 1 == 1;
                        }
                    }
                    _ => {}
                }
            }
            if rotate {
                std::mem::swap(&mut meta.width, &mut meta.height);
            }
        }
    }

    // Exif item: iinf gives its id, iloc its bytes
    let exif_id = find(&kids, b"iinf").and_then(|iinf| {
        let b = body(src, iinf, 8)?;
        let first = if b[0] == 0 {
            iinf.body + 6
        } else {
            iinf.body + 8
        };
        children(src, first, iinf.end).into_iter().find_map(|infe| {
            let e = body(src, &infe, 16)?;
            let (id, typ_at) = match e[0] {
                2 => (u32::from(be16(&e, 4)?), 8),
                3 => (be32(&e, 4)?, 10),
                _ => return None,
            };
            (e.get(typ_at..typ_at + 4)? == b"Exif").then_some(id)
        })
    });
    if let (Some(id), Some(iloc)) = (exif_id, find(&kids, b"iloc")) {
        if let Some((off, len)) = iloc_extent(src, iloc, id) {
            if let Some(hdr) = src.read_exact_at(off, 4) {
                let skip = u64::from(be32(&hdr, 0).unwrap_or(0));
                if skip < len {
                    parse_tiff(src, off + 4 + skip, meta);
                }
            }
        }
    }
    true
}

/// First extent (absolute offset, length) of item `want` in an `iloc` box.
fn iloc_extent(src: &dyn Source, iloc: &BoxHdr, want: u32) -> Option<(u64, u64)> {
    let b = body(src, iloc, 1 << 16)?;
    let v = b[0];
    let (off_sz, len_sz) = (b.get(4)? >> 4, b.get(4)? & 0xF);
    let (base_sz, idx_sz) = (b.get(5)? >> 4, if v >= 1 { b.get(5)? & 0xF } else { 0 });
    let (count, mut p) = if v < 2 {
        (u32::from(be16(&b, 6)?), 8usize)
    } else {
        (be32(&b, 6)?, 10usize)
    };
    for _ in 0..count.min(4096) {
        let id = if v < 2 {
            let x = u32::from(be16(&b, p)?);
            p += 2;
            x
        } else {
            let x = be32(&b, p)?;
            p += 4;
            x
        };
        let method = if v >= 1 {
            let m = be16(&b, p)? & 0xF;
            p += 2;
            m
        } else {
            0
        };
        p += 2; // data_reference_index
        let base = uint(&b, p, base_sz)?;
        p += usize::from(base_sz);
        let extents = be16(&b, p)?;
        p += 2;
        let mut first = None;
        for _ in 0..extents {
            p += usize::from(idx_sz);
            let off = uint(&b, p, off_sz)?;
            p += usize::from(off_sz);
            let len = uint(&b, p, len_sz)?;
            p += usize::from(len_sz);
            first.get_or_insert((base + off, len));
        }
        if id == want {
            return if method == 0 { first } else { None };
        }
    }
    None
}

// ── MP4 / MOV ───────────────────────────────────────────────────────────────

/// Seconds between 1904-01-01 (QuickTime epoch) and 1970-01-01.
const MAC_EPOCH: i64 = 2_082_844_800;

pub fn video(src: &dyn Source, meta: &mut Meta) -> bool {
    meta.is_video = true;
    let top = children(src, 0, src.len());
    let Some(moov) = find(&top, b"moov") else {
        return false;
    };
    let kids = children(src, moov.body, moov.end);

    if let Some(b) = find(&kids, b"mvhd").and_then(|m| body(src, m, 32)) {
        let (created, scale, dur) = if b[0] == 1 {
            (
                be64(&b, 4).unwrap_or(0),
                be32(&b, 20).unwrap_or(0),
                be64(&b, 24).unwrap_or(0),
            )
        } else {
            (
                u64::from(be32(&b, 4).unwrap_or(0)),
                be32(&b, 12).unwrap_or(0),
                u64::from(be32(&b, 16).unwrap_or(0)),
            )
        };
        if scale > 0 {
            meta.duration = dur as f64 / f64::from(scale);
        }
        let unix = created as i64 - MAC_EPOCH;
        if unix > 631_152_000 {
            // after 1990: a real timestamp, not an unset field
            meta.date = Some(DateTime::from_unix(unix));
            meta.date_utc = true;
        }
    }

    for trak in kids.iter().filter(|b| &b.typ == b"trak") {
        let t = children(src, trak.body, trak.end);
        let is_video = find(&t, b"mdia")
            .map(|m| children(src, m.body, m.end))
            .and_then(|m| find(&m, b"hdlr").and_then(|h| body(src, h, 12)))
            .map(|h| &h[8..12] == b"vide")
            .unwrap_or(false);
        if !is_video {
            continue;
        }
        if let Some(b) = find(&t, b"tkhd").and_then(|h| body(src, h, 96)) {
            let base = if b[0] == 1 { 4 + 32 } else { 4 + 20 }; // after the timing fields
            let matrix = base + 16; // reserved(8) + layer/alt/vol/res (8)
            let wh = matrix + 36;
            let a = be32(&b, matrix).unwrap_or(0) as i32;
            let w = be32(&b, wh).unwrap_or(0) >> 16;
            let h = be32(&b, wh + 4).unwrap_or(0) >> 16;
            if w > 0 && h > 0 {
                // a == 0 means a 90°/270° rotation matrix
                let (w, h) = if a == 0 { (h, w) } else { (w, h) };
                meta.width = w;
                meta.height = h;
            }
        }
        break;
    }

    // QuickTime user data: ©xyz location
    if let Some(udta) = find(&kids, b"udta") {
        for b in children(src, udta.body, udta.end) {
            if b.typ == [0xA9, b'x', b'y', b'z'] {
                if let Some(v) = body(src, &b, 64) {
                    if let Some(s) = v.get(4..).and_then(|s| std::str::from_utf8(s).ok()) {
                        if let Some((la, lo)) = parse_iso6709(s) {
                            meta.set_gps(la, lo);
                        }
                    }
                }
            }
        }
    }
    // keys/ilst metadata: Apple (moov/meta) and ffmpeg/Android (udta/meta)
    if let Some(m) = find(&kids, b"meta") {
        quicktime_keys(src, m, meta);
    }
    if let Some(udta) = find(&kids, b"udta") {
        if let Some(m) = find(&children(src, udta.body, udta.end), b"meta") {
            quicktime_keys(src, m, meta);
        }
    }
    true
}

fn quicktime_keys(src: &dyn Source, m: &BoxHdr, meta: &mut Meta) {
    // QuickTime's `meta` is a plain box, ISO's a FullBox with 4 extra bytes:
    // a plain one starts directly with its first child (`hdlr`).
    let plain = src.read_exact_at(m.body + 4, 4).as_deref() == Some(b"hdlr");
    let kids = children(src, if plain { m.body } else { m.body + 4 }, m.end);
    let (Some(keys), Some(ilst)) = (find(&kids, b"keys"), find(&kids, b"ilst")) else {
        return;
    };
    let Some(k) = body(src, keys, 1 << 16) else {
        return;
    };
    let mut names = Vec::new();
    let mut p = 8usize; // version/flags + entry count
    while let Some(size) = be32(&k, p) {
        let size = size as usize;
        if size < 8 || names.len() > 256 {
            break;
        }
        let Some(name) = k.get(p + 8..p + size) else {
            break;
        };
        names.push(String::from_utf8_lossy(name).into_owned());
        p += size;
    }
    for item in children(src, ilst.body, ilst.end) {
        let idx = u32::from_be_bytes(item.typ) as usize;
        let Some(name) = idx.checked_sub(1).and_then(|i| names.get(i)) else {
            continue;
        };
        let Some(data) = children(src, item.body, item.end)
            .into_iter()
            .find(|b| &b.typ == b"data")
        else {
            continue;
        };
        let Some(v) = body(src, &data, 256) else {
            continue;
        };
        let Some(text) = v.get(8..).and_then(|s| std::str::from_utf8(s).ok()) else {
            continue;
        };
        match name.as_str() {
            "com.apple.quicktime.location.ISO6709" | "location" => {
                if let Some((la, lo)) = parse_iso6709(text) {
                    meta.set_gps(la, lo);
                }
            }
            "com.apple.quicktime.creationdate" => {
                // "2023-05-18T10:00:00+0200": local wall-clock time wins over
                // the UTC mvhd timestamp
                if let Some(dt) = text
                    .get(..19)
                    .and_then(|s| parse_datetime(&s.replace('T', " ")))
                {
                    meta.date = Some(dt);
                    meta.date_utc = false;
                }
            }
            _ => {}
        }
    }
}

/// "+48.8584+002.2945+035.000/" → (48.8584, 2.2945)
pub fn parse_iso6709(s: &str) -> Option<(f64, f64)> {
    let s = s.trim_end_matches(['/', '\0']).trim();
    let b = s.as_bytes();
    let mut parts = Vec::new();
    let mut start = 0;
    for i in 1..=b.len() {
        if i == b.len() || b[i] == b'+' || b[i] == b'-' {
            parts.push(&s[start..i]);
            start = i;
        }
    }
    let la: f64 = parts.first()?.parse().ok()?;
    let lo: f64 = parts.get(1)?.parse().ok()?;
    Some((la, lo))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scan::source::Mem;

    fn bx(typ: &[u8; 4], body: &[u8]) -> Vec<u8> {
        let mut v = ((body.len() + 8) as u32).to_be_bytes().to_vec();
        v.extend_from_slice(typ);
        v.extend_from_slice(body);
        v
    }

    #[test]
    fn iso6709() {
        assert_eq!(
            parse_iso6709("+48.8584+002.2945+035.000/"),
            Some((48.8584, 2.2945))
        );
        assert_eq!(
            parse_iso6709("-33.8568+151.2153/"),
            Some((-33.8568, 151.2153))
        );
        assert_eq!(parse_iso6709("garbage"), None);
    }

    #[test]
    fn mp4_duration_size_rotation_location() {
        let mut mvhd = vec![0u8; 100];
        let created = (1_700_000_000i64 + MAC_EPOCH) as u32;
        mvhd[4..8].copy_from_slice(&created.to_be_bytes());
        mvhd[12..16].copy_from_slice(&600u32.to_be_bytes());
        mvhd[16..20].copy_from_slice(&(600u32 * 12).to_be_bytes());
        let mut tkhd = vec![0u8; 84];
        // rotation matrix (90°): a = 0
        tkhd[76..80].copy_from_slice(&(1920u32 << 16).to_be_bytes());
        tkhd[80..84].copy_from_slice(&(1080u32 << 16).to_be_bytes());
        let mut hdlr = vec![0u8; 24];
        hdlr[8..12].copy_from_slice(b"vide");
        let mdia = bx(b"mdia", &bx(b"hdlr", &hdlr));
        let trak = bx(b"trak", &[bx(b"tkhd", &tkhd), mdia].concat());
        let mut xyz = vec![0u8, 18, 0x15, 0xc7];
        xyz.extend_from_slice(b"+48.8584+002.2945/");
        let udta = bx(b"udta", &bx(&[0xA9, b'x', b'y', b'z'], &xyz));
        let moov = bx(b"moov", &[bx(b"mvhd", &mvhd), trak, udta].concat());
        let file = [
            bx(b"ftyp", b"isom\0\0\x02\0isom"),
            moov,
            bx(b"mdat", &[0; 16]),
        ]
        .concat();

        let mut m = Meta::default();
        assert!(is_bmff(&Mem(&file)));
        assert!(video(&Mem(&file), &mut m));
        assert!((m.duration - 12.0).abs() < 1e-9);
        assert_eq!((m.width, m.height), (1080, 1920));
        assert_eq!(m.gps, Some((48.8584, 2.2945)));
        assert!(m.date_utc && m.date.unwrap().year == 2023);
        for n in 0..file.len() {
            let mut m = Meta::default();
            let _ = video(&Mem(&file[..n]), &mut m);
            let _ = heif(&Mem(&file[..n]), &mut m);
        }
    }
}
