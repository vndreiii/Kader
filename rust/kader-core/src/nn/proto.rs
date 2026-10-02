//! Protocol-buffer wire-format reader — just enough to walk an ONNX model.
//! Every read is bounds-checked; a malformed file yields `None`, never a panic.

#[derive(Clone, Copy)]
pub enum Field<'a> {
    Varint(u64),
    Fixed64(u64),
    Bytes(&'a [u8]),
    Fixed32(u32),
}

impl<'a> Field<'a> {
    pub fn as_u64(&self) -> Option<u64> {
        match *self {
            Field::Varint(v) | Field::Fixed64(v) => Some(v),
            Field::Fixed32(v) => Some(u64::from(v)),
            Field::Bytes(_) => None,
        }
    }
    pub fn as_i64(&self) -> Option<i64> {
        self.as_u64().map(|v| v as i64)
    }
    pub fn as_f32(&self) -> Option<f32> {
        match *self {
            Field::Fixed32(v) => Some(f32::from_bits(v)),
            _ => None,
        }
    }
    pub fn as_bytes(&self) -> Option<&'a [u8]> {
        match *self {
            Field::Bytes(b) => Some(b),
            _ => None,
        }
    }
    pub fn as_str(&self) -> Option<&'a str> {
        std::str::from_utf8(self.as_bytes()?).ok()
    }
}

fn varint(buf: &[u8], pos: &mut usize) -> Option<u64> {
    let mut v = 0u64;
    for shift in (0..64).step_by(7) {
        let b = *buf.get(*pos)?;
        *pos += 1;
        v |= u64::from(b & 0x7F) << shift;
        if b & 0x80 == 0 {
            return Some(v);
        }
    }
    None
}

/// Calls `f(field_number, value)` for each top-level field of a message.
/// Returns `None` if the buffer is malformed (or `f` returns `None`).
pub fn fields<'a>(buf: &'a [u8], mut f: impl FnMut(u32, Field<'a>) -> Option<()>) -> Option<()> {
    let mut pos = 0;
    while pos < buf.len() {
        let key = varint(buf, &mut pos)?;
        let num = u32::try_from(key >> 3).ok()?;
        let field = match key & 7 {
            0 => Field::Varint(varint(buf, &mut pos)?),
            1 => {
                let b = buf.get(pos..pos + 8)?;
                pos += 8;
                Field::Fixed64(u64::from_le_bytes(b.try_into().ok()?))
            }
            2 => {
                let len = usize::try_from(varint(buf, &mut pos)?).ok()?;
                let end = pos.checked_add(len)?;
                let b = buf.get(pos..end)?;
                pos = end;
                Field::Bytes(b)
            }
            5 => {
                let b = buf.get(pos..pos + 4)?;
                pos += 4;
                Field::Fixed32(u32::from_le_bytes(b.try_into().ok()?))
            }
            _ => return None, // groups (3/4) are not used by ONNX
        };
        f(num, field)?;
    }
    Some(())
}

/// Appends a repeated int64 field that may be packed (bytes) or not (varint).
pub fn push_i64s(field: Field<'_>, out: &mut Vec<i64>) -> Option<()> {
    match field {
        Field::Bytes(b) => {
            let mut pos = 0;
            while pos < b.len() {
                out.push(varint(b, &mut pos)? as i64);
            }
        }
        other => out.push(other.as_i64()?),
    }
    Some(())
}

/// Appends a repeated float field that may be packed (bytes) or not (fixed32).
pub fn push_f32s(field: Field<'_>, out: &mut Vec<f32>) -> Option<()> {
    match field {
        Field::Bytes(b) => {
            if b.len() % 4 != 0 {
                return None;
            }
            out.extend(
                b.chunks_exact(4)
                    .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])),
            );
        }
        other => out.push(other.as_f32()?),
    }
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_fields_and_rejects_garbage() {
        // field 1 varint 150, field 2 bytes "hi", field 3 fixed32 1.0
        let mut buf = vec![0x08, 0x96, 0x01, 0x12, 0x02, b'h', b'i', 0x1D];
        buf.extend_from_slice(&1.0f32.to_le_bytes());
        let mut seen = vec![];
        fields(&buf, |n, f| {
            seen.push((n, f.as_u64(), f.as_str().map(str::to_owned), f.as_f32()));
            Some(())
        })
        .unwrap();
        assert_eq!(seen[0], (1, Some(150), None, None));
        assert_eq!(seen[1].2.as_deref(), Some("hi"));
        assert_eq!(seen[2].3, Some(1.0));
        for n in 0..buf.len() {
            let _ = fields(&buf[..n], |_, _| Some(()));
        }
        assert!(fields(&[0x12, 0xFF, 0x01], |_, _| Some(())).is_none());
    }
}
