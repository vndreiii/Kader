//! Minimal bounds-checked byte reader for the `.kgeo` format.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodeError(pub &'static str);

impl std::fmt::Display for DecodeError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "kgeo decode error: {}", self.0)
    }
}

impl std::error::Error for DecodeError {}

pub type Result<T> = std::result::Result<T, DecodeError>;

pub struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub fn new(buf: &'a [u8]) -> Self {
        Self { buf, pos: 0 }
    }

    pub fn is_empty(&self) -> bool {
        self.pos >= self.buf.len()
    }

    pub fn bytes(&mut self, n: usize) -> Result<&'a [u8]> {
        let end = self.pos.checked_add(n).ok_or(DecodeError("length overflow"))?;
        let s = self.buf.get(self.pos..end).ok_or(DecodeError("unexpected end of data"))?;
        self.pos = end;
        Ok(s)
    }

    pub fn u8(&mut self) -> Result<u8> {
        Ok(self.bytes(1)?[0])
    }

    pub fn u16(&mut self) -> Result<u16> {
        let b = self.bytes(2)?;
        Ok(u16::from_le_bytes([b[0], b[1]]))
    }

    pub fn u32(&mut self) -> Result<u32> {
        let b = self.bytes(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }

    /// Unsigned LEB128.
    pub fn varint(&mut self) -> Result<u64> {
        let mut v = 0u64;
        let mut shift = 0u32;
        loop {
            let b = self.u8()?;
            if shift >= 64 {
                return Err(DecodeError("varint too long"));
            }
            v |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Ok(v);
            }
            shift += 7;
        }
    }

    pub fn varint_usize(&mut self, max: usize) -> Result<usize> {
        let v = self.varint()?;
        if v > max as u64 {
            return Err(DecodeError("count out of range"));
        }
        Ok(v as usize)
    }

    /// Zigzag-encoded signed varint.
    pub fn zigzag(&mut self) -> Result<i64> {
        let v = self.varint()?;
        Ok(((v >> 1) as i64) ^ -((v & 1) as i64))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn varints() {
        let data = [0x00, 0x7f, 0x80, 0x01, 0xac, 0x02, 0x03, 0x04];
        let mut r = Reader::new(&data);
        assert_eq!(r.varint().unwrap(), 0);
        assert_eq!(r.varint().unwrap(), 127);
        assert_eq!(r.varint().unwrap(), 128);
        assert_eq!(r.varint().unwrap(), 300);
        assert_eq!(r.zigzag().unwrap(), -2);
        assert_eq!(r.zigzag().unwrap(), 2);
        assert!(r.is_empty());
        assert!(r.u8().is_err());
    }
}
