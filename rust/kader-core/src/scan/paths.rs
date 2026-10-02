//! Paths <-> bytes for the C ABI. On Unix paths are raw OS bytes; on Windows
//! they travel as UTF-8 with forward slashes, Qt's convention on every
//! platform, so paths from the scanner compare equal to paths from Qt.

use std::borrow::Cow;
use std::ffi::OsStr;
use std::path::PathBuf;

#[cfg(unix)]
pub fn to_bytes(p: &OsStr) -> Cow<'_, [u8]> {
    use std::os::unix::ffi::OsStrExt;
    Cow::Borrowed(p.as_bytes())
}

#[cfg(not(unix))]
pub fn to_bytes(p: &OsStr) -> Cow<'_, [u8]> {
    Cow::Owned(p.to_string_lossy().replace('\\', "/").into_bytes())
}

#[cfg(unix)]
pub fn from_bytes(b: &[u8]) -> PathBuf {
    use std::os::unix::ffi::OsStrExt;
    PathBuf::from(OsStr::from_bytes(b))
}

#[cfg(not(unix))]
pub fn from_bytes(b: &[u8]) -> PathBuf {
    PathBuf::from(String::from_utf8_lossy(b).into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips() {
        let p = from_bytes("photos/été/1.jpg".as_bytes());
        assert_eq!(&*to_bytes(p.as_os_str()), "photos/été/1.jpg".as_bytes());
    }
}
