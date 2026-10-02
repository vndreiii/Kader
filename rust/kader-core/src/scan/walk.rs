//! Parallel directory walk collecting media files with their size and mtime.

use std::collections::VecDeque;
use std::fs::Metadata;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Condvar, Mutex};

#[derive(Debug, Clone)]
pub struct Entry {
    pub path: PathBuf,
    pub size: u64,
    /// Modification time, Unix seconds.
    pub mtime: i64,
}

pub struct Options {
    /// Lower-case extensions including the dot (".jpg").
    pub extensions: Vec<Vec<u8>>,
    /// Directories whose path contains any of these substrings are skipped.
    pub exclusions: Vec<Vec<u8>>,
    pub threads: usize,
    /// Run workers at background priority (nice 10; background mode on Windows).
    pub background: bool,
}

pub struct Result {
    pub entries: Vec<Entry>,
    pub dirs: usize,
}

use super::paths::to_bytes;

#[cfg(target_os = "linux")]
fn deprioritise() {
    extern "C" {
        fn setpriority(which: i32, who: u32, prio: i32) -> i32;
        fn gettid() -> i32;
    }
    // PRIO_PROCESS with a thread id is per-thread on Linux.
    unsafe {
        setpriority(0, gettid() as u32, 10);
    }
}

#[cfg(windows)]
fn deprioritise() {
    #[link(name = "kernel32")]
    extern "system" {
        fn GetCurrentThread() -> *mut core::ffi::c_void;
        fn SetThreadPriority(thread: *mut core::ffi::c_void, priority: i32) -> i32;
    }
    // Background mode lowers CPU and I/O priority; the worker exits after.
    const THREAD_MODE_BACKGROUND_BEGIN: i32 = 0x0001_0000;
    unsafe {
        SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_BEGIN);
    }
}

#[cfg(not(any(target_os = "linux", windows)))]
fn deprioritise() {}

/// Modification time in Unix seconds.
fn mtime(md: &Metadata) -> i64 {
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        md.mtime()
    }
    #[cfg(not(unix))]
    {
        use std::time::UNIX_EPOCH;
        match md.modified().map(|t| t.duration_since(UNIX_EPOCH)) {
            Ok(Ok(d)) => d.as_secs() as i64,
            Ok(Err(before)) => -(before.duration().as_secs() as i64),
            Err(_) => 0,
        }
    }
}

fn has_ext(name: &[u8], exts: &[Vec<u8>]) -> bool {
    let Some(dot) = name.iter().rposition(|&c| c == b'.') else {
        return false;
    };
    let ext = &name[dot..];
    exts.iter().any(|e| {
        e.len() == ext.len() && e.iter().zip(ext).all(|(a, b)| *a == b.to_ascii_lowercase())
    })
}

fn excluded(path: &[u8], excl: &[Vec<u8>]) -> bool {
    excl.iter()
        .any(|x| !x.is_empty() && path.windows(x.len()).any(|w| w == x.as_slice()))
}

struct Queue {
    dirs: VecDeque<PathBuf>,
    busy: usize,
}

pub fn walk(root: &Path, opts: &Options, progress: &(dyn Fn(usize) + Sync)) -> Result {
    let threads = opts.threads.clamp(1, 64);
    let queue = Mutex::new(Queue {
        dirs: VecDeque::from([root.to_path_buf()]),
        busy: 0,
    });
    let cv = Condvar::new();
    let found = AtomicUsize::new(0);
    let dirs = AtomicUsize::new(0);

    let parts: Vec<Vec<Entry>> = std::thread::scope(|s| {
        let handles: Vec<_> = (0..threads)
            .map(|_| {
                s.spawn(|| {
                    if opts.background {
                        deprioritise();
                    }
                    let mut out = Vec::new();
                    loop {
                        // take a directory, or finish when nobody can add more
                        let dir = {
                            let mut q = queue.lock().unwrap();
                            loop {
                                if let Some(d) = q.dirs.pop_front() {
                                    q.busy += 1;
                                    break Some(d);
                                }
                                if q.busy == 0 {
                                    break None;
                                }
                                q = cv.wait(q).unwrap();
                            }
                        };
                        let Some(dir) = dir else {
                            cv.notify_all();
                            break;
                        };
                        let mut subdirs = Vec::new();
                        if let Ok(rd) = std::fs::read_dir(&dir) {
                            dirs.fetch_add(1, Ordering::Relaxed);
                            for e in rd.flatten() {
                                let Ok(ft) = e.file_type() else { continue };
                                if ft.is_dir() {
                                    let p = e.path();
                                    if !excluded(&to_bytes(p.as_os_str()), &opts.exclusions) {
                                        subdirs.push(p);
                                    }
                                } else if ft.is_file()
                                    && has_ext(&to_bytes(&e.file_name()), &opts.extensions)
                                {
                                    if let Ok(md) = e.metadata() {
                                        out.push(Entry {
                                            path: e.path(),
                                            size: md.len(),
                                            mtime: mtime(&md),
                                        });
                                        let n = found.fetch_add(1, Ordering::Relaxed) + 1;
                                        if n.is_multiple_of(256) {
                                            progress(n);
                                        }
                                    }
                                }
                            }
                        }
                        let mut q = queue.lock().unwrap();
                        q.dirs.extend(subdirs);
                        q.busy -= 1;
                        drop(q);
                        cv.notify_all();
                    }
                    out
                })
            })
            .collect();
        handles
            .into_iter()
            .map(|h| h.join().unwrap_or_default())
            .collect()
    });

    let mut entries: Vec<Entry> = parts.into_iter().flatten().collect();
    entries.sort_unstable_by(|a, b| a.path.cmp(&b.path));
    progress(entries.len());
    Result {
        entries,
        dirs: dirs.load(Ordering::Relaxed),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn walks_filters_and_excludes() {
        let root = std::env::temp_dir().join(format!("kader-walk-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        for d in ["a/b/c", "a/skip_me/x", "d"] {
            std::fs::create_dir_all(root.join(d)).unwrap();
        }
        for f in [
            "a/1.JPG",
            "a/b/2.png",
            "a/b/c/3.heic",
            "a/b/notes.txt",
            "a/skip_me/x/4.jpg",
            "d/5.mp4",
            "d/noext",
        ] {
            std::fs::write(root.join(f), b"x").unwrap();
        }
        let opts = Options {
            extensions: [".jpg", ".png", ".heic", ".mp4"]
                .iter()
                .map(|e| e.as_bytes().to_vec())
                .collect(),
            exclusions: vec![b"skip_me".to_vec()],
            threads: 4,
            background: false,
        };
        let r = walk(&root, &opts, &|_| {});
        let names: Vec<_> = r
            .entries
            .iter()
            .map(|e| {
                e.path
                    .strip_prefix(&root)
                    .unwrap()
                    .to_string_lossy()
                    .replace('\\', "/")
            })
            .collect();
        assert_eq!(names, ["a/1.JPG", "a/b/2.png", "a/b/c/3.heic", "d/5.mp4"]);
        assert!(r.entries.iter().all(|e| e.size == 1 && e.mtime > 0));
        let _ = std::fs::remove_dir_all(&root);
    }
}
