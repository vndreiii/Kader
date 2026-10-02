//! Header-only readers for still-image containers. Each reads just enough of
//! the file to find the pixel size and the embedded EXIF block.

use super::exif::parse_tiff;
use super::source::{be16, be32, le16, le32, Mem, Source};
use super::Meta;

/// JPEG: walk the marker segments up to the start of scan.
pub fn jpeg(src: &dyn Source, meta: &mut Meta) -> bool {
    let Some(soi) = src.read_exact_at(0, 2) else {
        return false;
    };
    if soi != [0xFF, 0xD8] {
        return false;
    }
    let mut pos = 2u64;
    for _ in 0..512 {
        let Some(h) = src.read_exact_at(pos, 4) else {
            break;
        };
        if h[0] != 0xFF {
            break;
        }
        let marker = h[1];
        if marker == 0xFF {
            pos += 1; // fill byte
            continue;
        }
        if marker == 0xD8 || marker == 0x01 || (0xD0..=0xD7).contains(&marker) {
            pos += 2;
            continue;
        }
        if marker == 0xDA || marker == 0xD9 {
            break; // start of scan / end of image
        }
        let Some(len) = be16(&h, 2) else { break };
        if len < 2 {
            break;
        }
        let data_off = pos + 4;
        let data_len = usize::from(len) - 2;
        match marker {
            0xE1 if data_len > 14 => {
                if src.read_exact_at(data_off, 6).as_deref() == Some(b"Exif\0\0") {
                    if let Some(block) = src.read_exact_at(data_off + 6, data_len - 6) {
                        parse_tiff(&Mem(&block), 0, meta);
                    }
                }
            }
            0xC0..=0xCF if !matches!(marker, 0xC4 | 0xC8 | 0xCC) => {
                if let Some(sof) = src.read_exact_at(data_off, 5) {
                    let (h, w) = (be16(&sof, 1).unwrap_or(0), be16(&sof, 3).unwrap_or(0));
                    if w > 0 && h > 0 {
                        meta.width = u32::from(w);
                        meta.height = u32::from(h);
                    }
                }
            }
            _ => {}
        }
        pos = data_off + data_len as u64;
    }
    true
}

/// PNG: IHDR for the size, optional eXIf chunk.
pub fn png(src: &dyn Source, meta: &mut Meta) -> bool {
    let Some(h) = src.read_exact_at(0, 33) else {
        return false;
    };
    if &h[..8] != b"\x89PNG\r\n\x1a\n" || &h[12..16] != b"IHDR" {
        return false;
    }
    meta.width = be32(&h, 16).unwrap_or(0);
    meta.height = be32(&h, 20).unwrap_or(0);
    let mut pos = 8u64;
    for _ in 0..64 {
        let Some(c) = src.read_exact_at(pos, 8) else {
            break;
        };
        let len = u64::from(be32(&c, 0).unwrap_or(0));
        match &c[4..8] {
            b"eXIf" => {
                if let Some(block) = src.read_exact_at(pos + 8, len as usize) {
                    parse_tiff(&Mem(&block), 0, meta);
                }
                break;
            }
            b"IDAT" | b"IEND" => break, // metadata comes before pixel data
            _ => {}
        }
        pos += 12 + len;
    }
    true
}

/// WebP (RIFF): VP8/VP8L/VP8X size and the EXIF chunk.
pub fn webp(src: &dyn Source, meta: &mut Meta) -> bool {
    let Some(h) = src.read_exact_at(0, 12) else {
        return false;
    };
    if &h[..4] != b"RIFF" || &h[8..12] != b"WEBP" {
        return false;
    }
    let mut pos = 12u64;
    for _ in 0..64 {
        let Some(c) = src.read_exact_at(pos, 8) else {
            break;
        };
        let len = u64::from(le32(&c, 4).unwrap_or(0));
        let body = pos + 8;
        match &c[..4] {
            b"VP8X" => {
                if let Some(b) = src.read_exact_at(body, 10) {
                    let w = u32::from(b[4]) | u32::from(b[5]) << 8 | u32::from(b[6]) << 16;
                    let hh = u32::from(b[7]) | u32::from(b[8]) << 8 | u32::from(b[9]) << 16;
                    meta.width = w + 1;
                    meta.height = hh + 1;
                }
            }
            b"VP8 " if meta.width == 0 => {
                if let Some(b) = src.read_exact_at(body, 10) {
                    meta.width = u32::from(le16(&b, 6).unwrap_or(0) & 0x3FFF);
                    meta.height = u32::from(le16(&b, 8).unwrap_or(0) & 0x3FFF);
                }
            }
            b"VP8L" if meta.width == 0 => {
                if let Some(b) = src.read_exact_at(body, 5) {
                    let bits = le32(&b, 1).unwrap_or(0);
                    meta.width = (bits & 0x3FFF) + 1;
                    meta.height = ((bits >> 14) & 0x3FFF) + 1;
                }
            }
            b"EXIF" => {
                if let Some(block) = src.read_exact_at(body, len as usize) {
                    // some writers keep the JPEG-style "Exif\0\0" prefix
                    let off = if block.starts_with(b"Exif\0\0") { 6 } else { 0 };
                    parse_tiff(&Mem(&block[off..]), 0, meta);
                }
            }
            _ => {}
        }
        pos = body + len + (len & 1);
    }
    true
}

pub fn gif(src: &dyn Source, meta: &mut Meta) -> bool {
    let Some(h) = src.read_exact_at(0, 10) else {
        return false;
    };
    if &h[..3] != b"GIF" {
        return false;
    }
    meta.width = u32::from(le16(&h, 6).unwrap_or(0));
    meta.height = u32::from(le16(&h, 8).unwrap_or(0));
    true
}

pub fn bmp(src: &dyn Source, meta: &mut Meta) -> bool {
    let Some(h) = src.read_exact_at(0, 26) else {
        return false;
    };
    if &h[..2] != b"BM" {
        return false;
    }
    meta.width = le32(&h, 18).unwrap_or(0);
    meta.height = (le32(&h, 22).unwrap_or(0) as i32).unsigned_abs();
    true
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jpeg_with(tiff: &[u8], w: u16, h: u16) -> Vec<u8> {
        let mut v = vec![0xFF, 0xD8];
        let app1_len = (2 + 6 + tiff.len()) as u16;
        v.extend_from_slice(&[0xFF, 0xE1]);
        v.extend_from_slice(&app1_len.to_be_bytes());
        v.extend_from_slice(b"Exif\0\0");
        v.extend_from_slice(tiff);
        v.extend_from_slice(&[0xFF, 0xDB, 0x00, 0x04, 0x00, 0x00]); // DQT stub
        v.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x0B, 0x08]);
        v.extend_from_slice(&h.to_be_bytes());
        v.extend_from_slice(&w.to_be_bytes());
        v.extend_from_slice(&[0x01, 0x01, 0x11, 0x00]);
        v.extend_from_slice(&[0xFF, 0xDA, 0x00, 0x02, 0xFF, 0xD9]);
        v
    }

    #[test]
    fn jpeg_reads_sof_and_exif() {
        let tiff = crate::scan::exif::tests::sample_tiff();
        let j = jpeg_with(&tiff, 640, 480);
        let mut m = Meta::default();
        assert!(jpeg(&Mem(&j), &mut m));
        // SOF wins over EXIF PixelX/Y: it's what the decoder produces
        assert_eq!((m.width, m.height), (640, 480));
        assert!(m.date.is_some() && m.gps.is_some());
        for n in 0..j.len() {
            let mut m = Meta::default();
            let _ = jpeg(&Mem(&j[..n]), &mut m);
        }
    }

    #[test]
    fn small_headers() {
        let mut m = Meta::default();
        let mut png_h = b"\x89PNG\r\n\x1a\n\0\0\0\x0dIHDR".to_vec();
        png_h.extend_from_slice(&800u32.to_be_bytes());
        png_h.extend_from_slice(&600u32.to_be_bytes());
        png_h.extend_from_slice(&[8, 6, 0, 0, 0, 0, 0, 0, 0]);
        assert!(png(&Mem(&png_h), &mut m));
        assert_eq!((m.width, m.height), (800, 600));

        let mut m = Meta::default();
        assert!(gif(&Mem(b"GIF89a\x40\x01\xf0\x00"), &mut m));
        assert_eq!((m.width, m.height), (320, 240));
    }
}
