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

#ifdef __cplusplus
}
#endif
