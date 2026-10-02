#!/usr/bin/env python3
"""Bake the vector world dataset used by Kader's 3D globe.

Produces ``assets/geo/world.kgeo`` — a compact binary file read by the Rust
geo engine (``rust/kader-core/src/geo``). Inputs are fetched on first run and
cached in ``tools/geo/.cache``:

* Natural Earth vector data (public domain) — coastlines, country borders,
  state/province lines, land + lake polygons, country and province labels.
  https://www.naturalearthdata.com/  (GitHub mirror: nvkelso/natural-earth-vector)
* GeoNames ``cities5000`` (CC BY 4.0) — every town of 5000+ inhabitants,
  taken from the ``geonamescache`` wheel on PyPI.  https://www.geonames.org/

Requires: Python 3.9+, numpy, Pillow.

File layout (little endian, varints are unsigned LEB128, "zz" = zigzag):
    b"KGEO" u16 version u16 section_count
    section*: tag[4] u32 byte_len payload
      LAND: varint w, varint h, per row: varint n_runs, n_runs × varint
            (alternating ocean/land run lengths, first run is ocean)
      LINE: u8 kind (0 coast, 1 country border, 2 state border), u8 lod,
            varint n_lines, per line: varint n_pts, zz lon0, zz lat0,
            then (n_pts-1) × (zz dlon, zz dlat); units are 1e-5 degree
      CTRY: varint n, per country: 2 bytes ISO-3166 alpha-2, varint len, utf8
      LABL: varint n, per label: u8 kind (0 country, 1 state, 2 city,
            3 ocean), u8 flags (bit0 capital), zz lon, zz lat, u8 min_zoom
            (×1/16 web-mercator zoom), varint population, varint country
            (1-based CTRY index, 0 = none), varint len, utf8
"""
from __future__ import annotations

import io
import json
import math
import re
import struct
import sys
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(__file__).resolve().parent / ".cache"
OUT = ROOT / "assets" / "geo" / "world.kgeo"

NE_URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/{}.geojson"
GEONAMES_WHEEL = "https://files.pythonhosted.org/packages/py3/g/geonamescache/geonamescache-3.0.2-py3-none-any.whl"

Q = 1e5            # coordinate quantisation (1e-5° ≈ 1.1 m)
LAND_W, LAND_H = 16384, 8192
LAKE_RANK = 7      # Natural Earth lake scalerank kept (0 = largest)


def lakes(max_rank: int) -> dict:
    fc = ne("ne_10m_lakes")
    return {"type": "FeatureCollection",
            "features": [f for f in fc["features"]
                         if f["properties"].get("scalerank") is not None
                         and f["properties"]["scalerank"] <= max_rank]}


# ── fetching ─────────────────────────────────────────────────────────────────

def fetch(url: str, name: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / name
    if not path.exists() or path.stat().st_size == 0:
        print(f"  downloading {url}", file=sys.stderr)
        with urllib.request.urlopen(url, timeout=300) as r:
            path.write_bytes(r.read())
    return path


def ne(name: str) -> dict:
    return json.loads(fetch(NE_URL.format(name), name + ".geojson").read_text(encoding="utf-8"))


def geonames_cities() -> tuple[dict, dict]:
    whl = fetch(GEONAMES_WHEEL, "geonamescache.whl")
    with zipfile.ZipFile(whl) as z:
        cities = json.loads(z.read("geonamescache/data/cities5000.json"))
        countries = json.loads(z.read("geonamescache/data/countries.json"))
    return cities, countries


# ── encoding helpers ─────────────────────────────────────────────────────────

def varint(n: int) -> bytes:
    assert n >= 0
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def zz(n: int) -> bytes:
    return varint((n << 1) ^ (n >> 63) if n < 0 else n << 1)


def section(tag: bytes, payload: bytes) -> bytes:
    assert len(tag) == 4
    return tag + struct.pack("<I", len(payload)) + payload


# ── geometry ─────────────────────────────────────────────────────────────────

def lines_of(fc: dict):
    for f in fc["features"]:
        g = f.get("geometry")
        if not g:
            continue
        if g["type"] == "LineString":
            yield g["coordinates"]
        elif g["type"] == "MultiLineString":
            yield from g["coordinates"]
        elif g["type"] == "Polygon":
            yield from g["coordinates"]
        elif g["type"] == "MultiPolygon":
            for poly in g["coordinates"]:
                yield from poly


def simplify(pts: np.ndarray, tol: float) -> np.ndarray:
    """Iterative Douglas–Peucker in lon/lat degrees."""
    n = len(pts)
    if n < 3 or tol <= 0:
        return pts
    keep = np.zeros(n, dtype=bool)
    keep[0] = keep[-1] = True
    stack = [(0, n - 1)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        seg = pts[a + 1:b]
        p, q = pts[a], pts[b]
        d = q - p
        L = math.hypot(d[0], d[1])
        if L == 0:
            dist = np.hypot(seg[:, 0] - p[0], seg[:, 1] - p[1])
        else:
            dist = np.abs(d[0] * (seg[:, 1] - p[1]) - d[1] * (seg[:, 0] - p[0])) / L
        i = int(np.argmax(dist))
        if dist[i] > tol:
            m = a + 1 + i
            keep[m] = True
            stack.append((a, m))
            stack.append((m, b))
    return pts[keep]


def encode_lines(kind: int, lod: int, fcs, tol: float = 0.0) -> tuple[bytes, int]:
    body = bytearray()
    count = 0
    total_pts = 0
    if isinstance(fcs, dict):
        fcs = [fcs]
    for coords in (c for fc in fcs for c in lines_of(fc)):
        pts = np.asarray(coords, dtype=np.float64)[:, :2]
        if tol:
            pts = simplify(pts, tol)
        q = np.round(pts * Q).astype(np.int64)
        # drop consecutive duplicates introduced by quantisation
        if len(q) > 1:
            m = np.ones(len(q), dtype=bool)
            m[1:] = np.any(q[1:] != q[:-1], axis=1)
            q = q[m]
        if len(q) < 2:
            continue
        count += 1
        total_pts += len(q)
        body += varint(len(q))
        body += zz(int(q[0, 0])) + zz(int(q[0, 1]))
        for dx, dy in (q[1:] - q[:-1]).tolist():
            body += zz(dx) + zz(dy)
    payload = bytes([kind, lod]) + varint(count) + bytes(body)
    print(f"  LINE kind={kind} lod={lod}: {count} lines, {total_pts} pts, {len(payload)/1024:.0f} KiB",
          file=sys.stderr)
    return section(b"LINE", payload), total_pts


# ── land mask ────────────────────────────────────────────────────────────────

def land_mask() -> bytes:
    img = Image.new("L", (LAND_W, LAND_H), 0)
    draw = ImageDraw.Draw(img)

    def px(ring):
        return [((lon + 180.0) / 360.0 * LAND_W, (90.0 - lat) / 180.0 * LAND_H) for lon, lat, *_ in ring]

    def polys(fc, pred=lambda p: True):
        for f in fc["features"]:
            if not pred(f["properties"]):
                continue
            g = f["geometry"]
            if g["type"] == "Polygon":
                yield g["coordinates"]
            elif g["type"] == "MultiPolygon":
                yield from g["coordinates"]

    for poly in polys(ne("ne_10m_land")):
        draw.polygon(px(poly[0]), fill=255)
        for hole in poly[1:]:
            draw.polygon(px(hole), fill=0)
    # Lakes read as water on the globe (Great Lakes, Geneva, Baikal…).
    for poly in polys(ne("ne_10m_lakes"), lambda p: p.get("scalerank") is not None and p["scalerank"] <= LAKE_RANK):
        draw.polygon(px(poly[0]), fill=0)
        for hole in poly[1:]:
            draw.polygon(px(hole), fill=255)

    a = np.asarray(img) > 127
    out = bytearray(varint(LAND_W) + varint(LAND_H))
    for row in a:
        # run boundaries, starting with an ocean run (possibly empty)
        changes = np.flatnonzero(np.diff(row.astype(np.int8))) + 1
        edges = [0] + changes.tolist() + [LAND_W]
        runs = [edges[i + 1] - edges[i] for i in range(len(edges) - 1)]
        if row[0]:
            runs = [0] + runs
        out += varint(len(runs))
        for r in runs:
            out += varint(r)
    print(f"  LAND {LAND_W}x{LAND_H}: {len(out)/1024:.0f} KiB, land={a.mean()*100:.1f}%", file=sys.stderr)
    return section(b"LAND", bytes(out))


# ── labels ───────────────────────────────────────────────────────────────────

OCEANS = [
    ("Pacific Ocean", -150.0, 5.0, 1.0), ("Pacific Ocean", 170.0, -25.0, 1.4),
    ("Atlantic Ocean", -35.0, 25.0, 1.0), ("Atlantic Ocean", -15.0, -25.0, 1.4),
    ("Indian Ocean", 78.0, -22.0, 1.0), ("Arctic Ocean", 0.0, 85.0, 1.5),
    ("Southern Ocean", 60.0, -62.0, 1.6),
]


def mz(z: float) -> int:
    return max(0, min(255, int(round(z * 16))))


def label(kind, flags, lon, lat, zoom, pop, name, country=0) -> bytes:
    name_b = name.encode("utf-8")[:120]
    return (bytes([kind, flags]) + zz(int(round(lon * Q))) + zz(int(round(lat * Q)))
            + bytes([mz(zoom)]) + varint(max(0, int(pop or 0))) + varint(country)
            + varint(len(name_b)) + name_b)


def labels() -> list[bytes]:
    cities, countries = geonames_cities()
    iso_list = sorted(c["iso"] for c in countries.values() if len(c.get("iso", "")) == 2)
    iso_index = {iso: i + 1 for i, iso in enumerate(iso_list)}
    names = {c["iso"]: c["name"] for c in countries.values()}
    ctry = bytearray(varint(len(iso_list)))
    for iso in iso_list:
        n = names[iso].encode("utf-8")
        ctry += iso.encode("ascii") + varint(len(n)) + n

    out = []
    for name, lon, lat, z in OCEANS:
        out.append(label(3, 0, lon, lat, z, 0, name))

    for f in ne("ne_50m_admin_0_countries")["features"]:
        p = f["properties"]
        name = p.get("NAME") or p.get("ADMIN")
        if not name or p.get("LABEL_X") is None:
            continue
        out.append(label(0, 0, p["LABEL_X"], p["LABEL_Y"], float(p.get("MIN_LABEL") or 4), p.get("POP_EST"), name,
                         iso_index.get(p.get("ISO_A2") or "", 0)))

    for f in ne("ne_10m_admin_1_states_provinces")["features"]:
        p = f["properties"]
        name = p.get("name")
        if not name or p.get("latitude") is None:
            continue
        z = float(p.get("min_label") or 7) + 0.5
        out.append(label(1, 0, p["longitude"], p["latitude"], z, 0, name, iso_index.get(p.get("iso_a2") or "", 0)))

    capitals = {(c["iso"], c["capital"]) for c in countries.values() if c.get("capital")}
    district = re.compile(r"^\S+ \d{1,2}(\s|$)")  # "Paris 02 Bourse", "Lyon 03", …
    for c in cities.values():
        pop = int(c.get("population") or 0)
        # GeoNames lists city districts as separate "cities": "Paris 02 Bourse",
        # "Zürich (Kreis 9)" — they only clutter the map.
        if pop < 5000 or district.match(c["name"]) or "(" in c["name"]:
            continue
        cap = (c["countrycode"], c["name"]) in capitals
        z = 3.0 + math.log2(max(1.0, 1e7 / pop)) * 0.62
        if cap:
            z = max(2.5, z - 1.6)
        out.append(label(2, 1 if cap else 0, c["longitude"], c["latitude"], z, pop, c["name"],
                         iso_index.get(c["countrycode"], 0)))

    payload = varint(len(out)) + b"".join(out)
    print(f"  CTRY: {len(iso_list)} countries; LABL: {len(out)} labels, {len(payload)/1024:.0f} KiB",
          file=sys.stderr)
    return [section(b"CTRY", bytes(ctry)), section(b"LABL", payload)]


# ── main ─────────────────────────────────────────────────────────────────────

def main() -> None:
    secs = [land_mask()]
    plan = [
        (0, 0, "ne_110m_coastline", 0.0),
        (0, 1, ["ne_50m_coastline", ("lakes", 3)], 0.004),
        (0, 2, ["ne_10m_coastline", ("lakes", LAKE_RANK)], 0.0015),
        (1, 0, "ne_110m_admin_0_boundary_lines_land", 0.0),
        (1, 1, "ne_50m_admin_0_boundary_lines_land", 0.0),
        (1, 2, "ne_10m_admin_0_boundary_lines_land", 0.001),
        (2, 1, "ne_50m_admin_1_states_provinces_lines", 0.0),
        (2, 2, "ne_10m_admin_1_states_provinces_lines", 0.002),
    ]
    for kind, lod, names, tol in plan:
        names = names if isinstance(names, list) else [names]
        fcs = [lakes(n[1]) if isinstance(n, tuple) else ne(n) for n in names]
        secs.append(encode_lines(kind, lod, fcs, tol)[0])
    secs.extend(labels())

    blob = b"KGEO" + struct.pack("<HH", 1, len(secs)) + b"".join(secs)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(blob)
    print(f"wrote {OUT} ({len(blob)/1024/1024:.2f} MiB)", file=sys.stderr)


if __name__ == "__main__":
    main()
