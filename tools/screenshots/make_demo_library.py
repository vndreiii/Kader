#!/usr/bin/env python3
"""Build a demo photo library for screenshots and UI testing.

Downloads freely licensed sample photos (Pixabay-derived, from
github.com/yavuzceliker/sample-images) and writes them into album folders with
realistic EXIF capture dates and GPS coordinates — a fictional few years of
trips — so every view (timeline, albums, places globe) has something real to
show.

    python3 tools/screenshots/make_demo_library.py ~/Pictures/KaderDemo

Requires: Pillow, piexif.
"""
from __future__ import annotations

import random
import sys
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

import piexif
from PIL import Image

SRC = "https://raw.githubusercontent.com/yavuzceliker/sample-images/main/docs/image-{}.jpg"
CACHE = Path(__file__).resolve().parent / ".cache"

# album → (start date, [(image id, lat, lon) …]); lat/lon None = no GPS
ALBUMS: dict[str, tuple[str, list[tuple[int, float | None, float | None]]]] = {
    "Switzerland 2025": ("2025-06-14", [
        (1192, 47.0502, 8.3093), (1151, 46.4312, 6.9107), (1196, 46.6863, 7.8632),
        (1310, 47.3307, 9.4093), (1021, 46.0207, 7.7491), (1050, 46.6242, 8.0414),
        (1304, 46.5838, 7.0828), (1006, 46.5590, 7.9100),
    ]),
    "Paris": ("2025-09-03", [
        (1285, 48.8049, 2.1204), (1217, 48.8566, 2.3522), (1037, 48.8606, 2.3376),
        (1009, 48.8584, 2.2945), (1178, 48.8530, 2.3499), (1214, 48.8462, 2.3371),
    ]),
    "Japan": ("2024-04-02", [
        (1243, 35.0116, 135.7681), (1150, 35.0036, 135.7780), (1229, 35.6895, 139.6917),
        (1147, 35.6586, 139.7454), (1270, 35.0270, 135.7982), (1166, 35.3606, 138.7274),
    ]),
    "Dolomites": ("2024-10-11", [
        (1177, 46.5405, 12.1357), (1152, 46.4300, 11.8500), (1258, 46.6000, 11.9000),
        (1290, 46.5500, 12.0000), (1262, 46.5110, 11.7680),
    ]),
    "Iceland": ("2023-12-27", [
        (1005, 64.1466, -21.9426), (1094, 63.4186, -19.0060), (1042, 64.2559, -20.5200),
        (1136, 64.3271, -20.1199), (1173, 64.0490, -16.1800),
    ]),
    "New York": ("2025-02-20", [
        (1172, 40.7061, -73.9969), (1195, 40.7484, -73.9857), (1028, 40.7306, -73.9866),
        (1247, 40.7128, -74.0060),
    ]),
    "Kenya & Tanzania": ("2024-07-08", [
        (1111, -1.3733, 36.8580), (1020, -2.3333, 34.8333), (1117, -1.4061, 35.0076),
    ]),
    "Cape Town": ("2025-08-02", [
        (1257, -33.9249, 18.4241), (1275, -34.0700, 18.4500), (1083, -34.3568, 18.4740),
    ]),
    "Sydney NYE": ("2023-12-31", [
        (1027, -33.8568, 151.2153), (1120, -33.7969, 151.2878), (1187, -33.9399, 151.1753),
    ]),
    "Canadian Rockies": ("2025-11-03", [
        (1141, 51.4254, -116.1773), (1249, 58.7684, -94.1650), (1200, 51.1784, -115.5708),
    ]),
    "Lisbon": ("2023-05-18", [
        (1216, 38.7223, -9.1393), (1017, 38.6979, -9.4215), (1231, 38.7139, -9.1334),
    ]),
    "Monterey Bay": ("2024-08-21", [
        (1143, 36.6182, -121.9019), (1211, 36.6002, -121.8947),
    ]),
    "Family": ("2024-02-10", [
        (1007, None, None), (1062, None, None), (1121, None, None), (1148, None, None),
        (1156, None, None), (1109, None, None), (1198, None, None),
    ]),
    "Pets": ("2025-03-09", [
        (1114, None, None), (1302, None, None), (1316, None, None),
    ]),
    "Holidays": ("2024-12-20", [
        (1034, None, None), (1084, None, None), (1080, None, None), (1040, None, None),
    ]),
    "Food": ("2025-01-12", [
        (1185, None, None), (1204, None, None), (1205, None, None), (1184, None, None),
    ]),
    "Wildlife": ("2024-05-25", [
        (1008, 52.3700, 4.8900), (1127, 51.5007, -0.1246), (1170, 60.1699, 24.9384),
        (1149, 9.7489, -83.7534), (1074, -3.4653, -62.2159), (1085, 1.3521, 103.8198),
        (1092, 13.7563, 100.5018), (1194, 59.3293, 18.0686),
    ]),
    "Macro": ("2025-04-27", [
        (1051, None, None), (1181, None, None), (1207, None, None), (1210, None, None),
        (1169, None, None), (1123, None, None),
    ]),
    "Studio": ("2025-07-19", [
        (1000, None, None), (1011, None, None), (1138, None, None), (1292, None, None), (1095, None, None),
    ]),
}


def fetch(image_id: int) -> bytes:
    CACHE.mkdir(parents=True, exist_ok=True)
    p = CACHE / f"image-{image_id}.jpg"
    if not p.exists():
        with urllib.request.urlopen(SRC.format(image_id), timeout=120) as r:
            p.write_bytes(r.read())
    return p.read_bytes()


def dms(value: float) -> tuple:
    value = abs(value)
    d = int(value)
    m = int((value - d) * 60)
    s = round(((value - d) * 60 - m) * 60 * 100)
    return ((d, 1), (m, 1), (s, 100))


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1]).expanduser()
    rnd = random.Random(7)
    n = 0
    for album, (start, shots) in ALBUMS.items():
        folder = out / album
        folder.mkdir(parents=True, exist_ok=True)
        t = datetime.fromisoformat(start) + timedelta(hours=9)
        for image_id, lat, lon in shots:
            t += timedelta(hours=rnd.randint(2, 30), minutes=rnd.randint(0, 59))
            img = Image.open(__import__("io").BytesIO(fetch(image_id))).convert("RGB")
            exif = {"0th": {piexif.ImageIFD.Make: b"Kader", piexif.ImageIFD.Model: b"Demo"},
                    "Exif": {piexif.ExifIFD.DateTimeOriginal: t.strftime("%Y:%m:%d %H:%M:%S").encode(),
                             piexif.ExifIFD.PixelXDimension: img.width,
                             piexif.ExifIFD.PixelYDimension: img.height},
                    "GPS": {}}
            if lat is not None:
                # scatter a little so a place is a handful of nearby shots
                la = lat + rnd.uniform(-0.003, 0.003)
                lo = lon + rnd.uniform(-0.003, 0.003)
                exif["GPS"] = {
                    piexif.GPSIFD.GPSLatitudeRef: b"N" if la >= 0 else b"S",
                    piexif.GPSIFD.GPSLatitude: dms(la),
                    piexif.GPSIFD.GPSLongitudeRef: b"E" if lo >= 0 else b"W",
                    piexif.GPSIFD.GPSLongitude: dms(lo),
                }
            dest = folder / f"IMG_{t.strftime('%Y%m%d_%H%M%S')}.jpg"
            img.save(dest, quality=90, exif=piexif.dump(exif))
            ts = t.timestamp()
            import os
            os.utime(dest, (ts, ts))
            n += 1
    print(f"wrote {n} photos into {out}")


if __name__ == "__main__":
    main()
