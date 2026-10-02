//! Positional, bounds-checked reads from a file (or an in-memory buffer in
//! tests). Parsers only ever see slices they asked for, so a corrupt offset
//! can produce "not found" but never an out-of-bounds read.

use std::fs::File;
use std::os::unix::fs::FileExt;

pub trait Source {
    fn len(&self) -> u64;
    fn is_empty(&self) -> bool {
        self.len() == 0
    }
    /// Reads up to `len` bytes at `off` (short at end of file).
    fn read_at(&self, off: u64, len: usize) -> Option<Vec<u8>>;

    fn read_exact_at(&self, off: u64, len: usize) -> Option<Vec<u8>> {
        let v = self.read_at(off, len)?;
        (v.len() == len).then_some(v)
    }
}

pub struct FileSource {
    file: File,
    len: u64,
}

impl FileSource {
    pub fn open(path: &std::path::Path) -> Option<Self> {
        let file = File::open(path).ok()?;
        let len = file.metadata().ok()?.len();
        Some(Self { file, len })
    }
}

/// Upper bound for any single read — metadata blocks are small; this keeps a
/// hostile length field from allocating gigabytes.
pub const MAX_READ: usize = 16 << 20;

impl Source for FileSource {
    fn len(&self) -> u64 {
        self.len
    }

    fn read_at(&self, off: u64, len: usize) -> Option<Vec<u8>> {
        if off >= self.len {
            return None;
        }
        let len = len.min(MAX_READ).min((self.len - off) as usize);
        let mut buf = vec![0u8; len];
        let mut done = 0;
        while done < len {
            match self.file.read_at(&mut buf[done..], off + done as u64) {
                Ok(0) => break,
                Ok(n) => done += n,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(_) => return None,
            }
        }
        buf.truncate(done);
        Some(buf)
    }
}

/// An in-memory buffer (embedded EXIF blocks, tests).
pub struct Mem<'a>(pub &'a [u8]);

impl Source for Mem<'_> {
    fn len(&self) -> u64 {
        self.0.len() as u64
    }

    fn read_at(&self, off: u64, len: usize) -> Option<Vec<u8>> {
        let off = usize::try_from(off).ok()?;
        if off >= self.0.len() {
            return None;
        }
        let end = off.saturating_add(len.min(MAX_READ)).min(self.0.len());
        Some(self.0[off..end].to_vec())
    }
}

#[inline]
pub fn be16(b: &[u8], o: usize) -> Option<u16> {
    Some(u16::from_be_bytes(b.get(o..o + 2)?.try_into().ok()?))
}
#[inline]
pub fn be32(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_be_bytes(b.get(o..o + 4)?.try_into().ok()?))
}
#[inline]
pub fn be64(b: &[u8], o: usize) -> Option<u64> {
    Some(u64::from_be_bytes(b.get(o..o + 8)?.try_into().ok()?))
}
#[inline]
pub fn le16(b: &[u8], o: usize) -> Option<u16> {
    Some(u16::from_le_bytes(b.get(o..o + 2)?.try_into().ok()?))
}
#[inline]
pub fn le32(b: &[u8], o: usize) -> Option<u32> {
    Some(u32::from_le_bytes(b.get(o..o + 4)?.try_into().ok()?))
}
