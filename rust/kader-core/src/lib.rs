//! Kader core — the performance-critical, memory-safe parts of the Kader
//! gallery, exposed to the Qt/C++ application through a small C ABI
//! (see `include/kader_core.h`).
//!
//! * [`geo`] — the vector globe engine: world dataset decoding, orthographic
//!   camera, level-of-detail culling, dotted-land generation, label
//!   decluttering and photo-pin clustering. It emits ready-to-upload vertex
//!   buffers so the GPU only ever draws antialiased quads.

//! * [`scan`] — library scanning: a parallel directory walk and memory-safe,
//!   header-only metadata probes (EXIF date/GPS/size, HEIC, PNG, WebP,
//!   MP4/MOV duration, size and location).

pub mod ffi;
pub mod geo;
pub mod scan;
pub mod scan_ffi;
