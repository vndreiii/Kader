// C ABI of the Rust core (rust/kader-core). Keep in sync with src/ffi.rs —
// struct layouts are asserted by the crate's tests.
#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct KgWorld KgWorld;
typedef struct KgGlobe KgGlobe;

typedef struct KgVertex {
    float x, y;      // item coordinates (logical px)
    float u, v;      // shape-local coordinates in [-1, 1]
    float w;         // half extent in device px (antialiasing)
    uint8_t rgba[4]; // premultiplied
} KgVertex;

typedef struct KgLabel {
    uint32_t id;
    float x, y;
    float alpha;
    uint8_t cls;     // 0 ocean, 1 country, 2 state, 3 major city, 4 city, 5 town
    uint8_t anchor;  // 0 centre, 1 right of marker, 2 left of marker
    uint8_t capital;
    uint8_t _pad;
} KgLabel;

typedef struct KgPin {
    uint32_t cluster;
    uint32_t lead;    // index of the heaviest member pin
    uint32_t count;   // summed weight (photos)
    uint32_t members; // number of pins in the cluster
    float x, y;       // anchor point (bubble sits above it)
    float depth;      // > 0 on the visible hemisphere, 1 at the centre
    float alpha;
} KgPin;

typedef struct KgStyle {
    uint8_t land[4], coast[4], border[4], state[4], city[4], city_halo[4], casing[4];
    float dot_spacing, dot_size;
    float coast_width, border_width, state_width;
    float label_density;
    float pin_width, pin_height, pin_merge;
} KgStyle;

typedef struct KgPinIn {
    double lat, lon;
    uint32_t weight;
} KgPinIn;

typedef struct KgCamera {
    double lat, lon, radius, zoom, fit_radius;
} KgCamera;

typedef struct KgFrame {
    const KgVertex *vertices;
    uint32_t vertex_count;
    const uint32_t *indices;
    uint32_t index_count;
    const KgLabel *labels;
    uint32_t label_count;
    const KgPin *pins;
    uint32_t pin_count;
    uint32_t pin_epoch;
    float center_x, center_y, radius, zoom;
} KgFrame;

const char *kg_version(void);

KgWorld *kg_world_new(const uint8_t *data, size_t len);
void kg_world_free(KgWorld *world);
const uint8_t *kg_world_label_name(const KgWorld *world, uint32_t id, size_t *len);
// Offline "City, Country" for a point (UTF-8, not NUL terminated); returns
// the byte length, 0 when no town of 5000+ people lies within max_km.
size_t kg_world_place_name(const KgWorld *world, double lat, double lon, double max_km,
                           uint8_t *buf, size_t cap, double *distance_km);

KgGlobe *kg_globe_new(void);
void kg_globe_free(KgGlobe *g);
void kg_globe_set_viewport(KgGlobe *g, double width, double height, double dpr);
void kg_globe_set_style(KgGlobe *g, const KgStyle *style);
void kg_globe_set_pins(KgGlobe *g, const KgPinIn *pins, size_t count);
const uint32_t *kg_globe_pin_members(KgGlobe *g, uint32_t cluster, size_t *count);
uint32_t kg_globe_cluster_count(KgGlobe *g);
bool kg_globe_cluster_info(KgGlobe *g, uint32_t cluster, double *lat, double *lon,
                           uint32_t *weight, uint32_t *lead);
int64_t kg_globe_pin_at(KgGlobe *g, double x, double y);
void kg_globe_drag_begin(KgGlobe *g);
void kg_globe_drag(KgGlobe *g, double dx, double dy);
void kg_globe_drag_end(KgGlobe *g, double vx, double vy);
void kg_globe_zoom_by(KgGlobe *g, double factor, double x, double y, bool animate);
void kg_globe_fly_to(KgGlobe *g, double lat, double lon, double radius);
double kg_globe_radius_for_km(KgGlobe *g, double km);
void kg_globe_reset(KgGlobe *g);
void kg_globe_set_auto_rotate(KgGlobe *g, bool on);
bool kg_globe_tick(KgGlobe *g, double dt);
void kg_globe_camera(KgGlobe *g, KgCamera *out);
double kg_globe_project(KgGlobe *g, double lat, double lon, double *x, double *y);
bool kg_globe_unproject(KgGlobe *g, double x, double y, double *lat, double *lon);
bool kg_globe_build(KgGlobe *g, const KgWorld *world, double dt, KgFrame *out);

// ── Library scanning (src/scan, src/scan_ffi.rs) ───────────────────────────

typedef struct KsScan KsScan;
typedef void (*ks_progress_fn)(void *user, size_t found);

typedef struct KsMeta {
    uint32_t width, height;  // display size (EXIF orientation applied)
    uint16_t orientation;
    uint8_t flags;           // KS_* below
    uint8_t _pad0;
    uint16_t year;
    uint8_t month, day, hour, minute, second, _pad1;
    double lat, lon, duration;
} KsMeta;

enum {
    KS_KNOWN = 1,      // format recognised and parsed
    KS_SIZE = 2,
    KS_DATE = 4,
    KS_DATE_UTC = 8,   // date is UTC (video container); otherwise local time
    KS_GPS = 16,
    KS_VIDEO = 32,
    KS_DURATION = 64,
};

// Parallel walk of `root` (threads 0 = all cores) for files whose lower-case
// extension (".jpg") is in `exts`, skipping directories whose path contains
// any of `exclusions`. `progress` is called from worker threads.
KsScan *ks_scan_dir(const char *root, const char *const *exts, size_t n_exts,
                    const char *const *exclusions, size_t n_exclusions, uint32_t threads,
                    ks_progress_fn progress, void *user);
size_t ks_scan_count(const KsScan *scan);
size_t ks_scan_dirs(const KsScan *scan);
bool ks_scan_entry(const KsScan *scan, size_t i, const uint8_t **path, size_t *path_len,
                   uint64_t *size, int64_t *mtime);
void ks_scan_free(KsScan *scan);

// Header-only metadata of `n` files, probed in parallel into out[n].
void ks_probe_batch(const uint8_t *const *paths, const size_t *lens, size_t n, uint32_t threads,
                    KsMeta *out);

// ── Faces, clustering and colour (kf_*, kc_*, kn_*) ─────────────────────────
// Images are packed 8-bit RGB, `h` rows `stride` bytes apart.

typedef struct KfDetector KfDetector;
typedef struct KfRecognizer KfRecognizer;

typedef struct KfFace {
    float x, y, w, h;      // box, input-image pixels
    float score;           // 0..1
    float landmarks[10];   // right eye, left eye, nose, right/left mouth corner
} KfFace;

typedef struct KcStats {
    uint8_t average[3];
    uint8_t bucket;        // colour bucket (kc_bucket_name), 0 = none dominant
    float bucket_frac;     // share of the frame in that bucket
    uint8_t palette[5][3]; // mean colour of the five largest buckets
    float palette_frac[5];
} KcStats;

#define KF_EMBED_DIM 128

// Worker threads for large convolutions (default 1).
void kn_set_threads(uint32_t n);

// Load ONNX models (YuNet / SFace). On failure return NULL and write a
// message to err (optional).
KfDetector *kf_detector_load(const uint8_t *onnx, size_t len, char *err, size_t err_len);
void kf_detector_free(KfDetector *d);
KfRecognizer *kf_recognizer_load(const uint8_t *onnx, size_t len, char *err, size_t err_len);
void kf_recognizer_free(KfRecognizer *r);

// Faces found (best first, at most max_out), or -1. The image is scaled to
// at most max_side on its longer edge for detection.
int32_t kf_detect(const KfDetector *d, const uint8_t *rgb, uint32_t w, uint32_t h, uint32_t stride,
                  uint32_t max_side, float score_thr, KfFace *out, int32_t max_out);
// L2-normalised 128-d identity embedding of `face` (aligned internally). 0 = ok.
int32_t kf_embed(const KfRecognizer *r, const uint8_t *rgb, uint32_t w, uint32_t h, uint32_t stride,
                 const KfFace *face, float *out);
// Groups n embeddings into people. fixed[i]/exclude[i]: confirmed person id
// / person id the face must not join, or -1. Writes labels[n] (cluster per
// face) and cluster_person[n] (person id per cluster, -1 = new group).
// Returns the cluster count, or -1.
int64_t kf_cluster(const float *embeddings, size_t n, const int64_t *fixed, const int64_t *exclude,
                   float threshold, uint32_t *labels, int64_t *cluster_person);

int32_t kc_color_stats(const uint8_t *rgb, uint32_t w, uint32_t h, uint32_t stride, KcStats *out);
const char *kc_bucket_name(uint32_t bucket);

#ifdef __cplusplus
}
#endif
