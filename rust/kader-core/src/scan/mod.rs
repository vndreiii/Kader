//! Library scanning: a parallel directory walk and header-only metadata
//! probes (capture date, GPS, pixel size, video duration) for the formats a
//! photo library is made of. Replaces per-file Exiv2/libvips/ffprobe calls in
//! the common case; anything not understood here is left to those fallbacks.

pub mod bmff;
pub mod exif;
pub mod formats;
pub mod paths;
pub mod source;
pub mod walk;

use source::{FileSource, Source};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct DateTime {
    pub year: u16,
    pub month: u8,
    pub day: u8,
    pub hour: u8,
    pub minute: u8,
    pub second: u8,
}

impl DateTime {
    pub fn is_valid(&self) -> bool {
        (1900..=2200).contains(&self.year)
            && (1..=12).contains(&self.month)
            && (1..=31).contains(&self.day)
            && self.hour < 24
            && self.minute < 60
            && self.second < 61
    }

    /// Civil date from Unix seconds (UTC), Howard Hinnant's algorithm.
    pub fn from_unix(t: i64) -> Self {
        let days = t.div_euclid(86_400);
        let secs = t.rem_euclid(86_400);
        let z = days + 719_468;
        let era = z.div_euclid(146_097);
        let doe = z - era * 146_097;
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
        let y = yoe + era * 400;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let m = if mp < 10 { mp + 3 } else { mp - 9 };
        Self {
            year: (if m <= 2 { y + 1 } else { y }) as u16,
            month: m as u8,
            day: d as u8,
            hour: (secs / 3600) as u8,
            minute: (secs % 3600 / 60) as u8,
            second: (secs % 60) as u8,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Meta {
    pub width: u32,
    pub height: u32,
    /// Size from a TIFF IFD0 (RAW files: often a preview) — used only when
    /// nothing better exists.
    pub tiff_width: u32,
    pub tiff_height: u32,
    /// EXIF orientation (1–8, 0 = unknown).
    pub orientation: u16,
    pub date: Option<DateTime>,
    /// `date` is UTC (video container timestamps) rather than local time.
    pub date_utc: bool,
    pub gps: Option<(f64, f64)>,
    pub duration: f64,
    pub is_video: bool,
    pub format_known: bool,
}

impl Meta {
    pub fn set_gps(&mut self, lat: f64, lon: f64) {
        let valid = lat.is_finite() && lon.is_finite() && lat.abs() <= 90.0 && lon.abs() <= 180.0;
        // (0, 0) is how many cameras write "no fix"
        if valid && !(lat.abs() < 1e-9 && lon.abs() < 1e-9) {
            self.gps = Some((lat, lon));
        }
    }

    /// Display size: orientations 5–8 rotate by 90°, so the grid needs the
    /// swapped aspect ratio.
    pub fn display_size(&self) -> (u32, u32) {
        let (w, h) = if self.width > 0 && self.height > 0 {
            (self.width, self.height)
        } else {
            (self.tiff_width, self.tiff_height)
        };
        if (5..=8).contains(&self.orientation) {
            (h, w)
        } else {
            (w, h)
        }
    }
}

/// Probes one file. Never panics on malformed input; unknown formats come
/// back with `format_known == false`.
pub fn probe(path: &std::path::Path) -> Meta {
    match FileSource::open(path) {
        Some(src) => probe_source(&src),
        None => Meta::default(),
    }
}

pub fn probe_source(src: &dyn Source) -> Meta {
    let mut m = Meta::default();
    let Some(magic) = src.read_at(0, 16) else {
        return m;
    };
    let ok = if magic.starts_with(&[0xFF, 0xD8]) {
        formats::jpeg(src, &mut m)
    } else if magic.starts_with(b"\x89PNG") {
        formats::png(src, &mut m)
    } else if magic.starts_with(b"RIFF") && magic.get(8..12) == Some(b"WEBP") {
        formats::webp(src, &mut m)
    } else if magic.starts_with(b"GIF8") {
        formats::gif(src, &mut m)
    } else if magic.starts_with(b"BM") {
        formats::bmp(src, &mut m)
    } else if magic.starts_with(b"II") || magic.starts_with(b"MM") {
        exif::parse_tiff(src, 0, &mut m)
    } else if bmff::is_bmff(src) {
        match bmff::brand(src) {
            Some(b)
                if matches!(
                    &b,
                    b"heic" | b"heix" | b"heim" | b"heis" | b"mif1" | b"msf1" | b"avif" | b"avis"
                ) =>
            {
                bmff::heif(src, &mut m)
            }
            Some(b) if &b == b"crx " => false, // Canon CR3: leave to Exiv2
            _ => bmff::video(src, &mut m),
        }
    } else {
        false
    };
    m.format_known = ok;
    m
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unix_to_civil() {
        let d = DateTime::from_unix(1_700_000_000);
        assert_eq!(
            (d.year, d.month, d.day, d.hour, d.minute, d.second),
            (2023, 11, 14, 22, 13, 20)
        );
        let d = DateTime::from_unix(951_782_400); // 2000-02-29
        assert_eq!((d.year, d.month, d.day), (2000, 2, 29));
    }

    #[test]
    fn display_size_respects_orientation() {
        let m = Meta {
            width: 4000,
            height: 3000,
            orientation: 6,
            ..Default::default()
        };
        assert_eq!(m.display_size(), (3000, 4000));
    }

    #[test]
    fn real_demo_jpegs_if_present() {
        // KADER_TEST_PHOTOS=<dir of JPEGs with GPS>, e.g. one album written by
        // tools/screenshots/make_demo_library.py
        let Ok(dir) = std::env::var("KADER_TEST_PHOTOS") else {
            return;
        };
        let dir = std::path::Path::new(&dir);
        let Ok(rd) = std::fs::read_dir(dir) else {
            return;
        };
        for e in rd.flatten() {
            let m = probe(&e.path());
            assert!(
                m.format_known && m.width > 0 && m.date.is_some(),
                "{:?} {m:?}",
                e.path()
            );
            assert!(m.gps.is_some());
        }
    }
}
