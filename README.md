<p align="center">
  <img src="assets/KaderPNGicon.png" width="120" alt="Kader icon" />
</p>

<h1 align="center">Kader</h1>
<p align="center">A fast, modern photo gallery for Linux — built with Qt 6, QML Material 3, and C++.</p>

---

## Features

- **Timeline** — mosaic grid with automatic monthly separators and variable density
- **Albums** — folder-based with pinning, custom covers, and virtual album creation
- **Videos** — dedicated view with an integrated player (FFmpeg backend), looping, volume, seeking
- **Places / Map** — geotagged photos plotted on an OpenStreetMap with reverse-geocoded pin cards
- **Favorites, Hidden, Trash** — smart views; hidden photos are password-protected
- **Viewer** — zoom/pan, EXIF info panel, keyboard navigation, fullscreen, copy to clipboard
- **RAW camera support** — thumbnail extraction via LibRaw for NEF, CR2, CR3, ARW, DNG, RAF and more
- **Encrypted thumbnails** — AES-256-CBC per-machine key, cached on disk
- **Fast scanning** — parallel directory walk using Linux `getdents64`, Exiv2 EXIF parsing, batch SQLite writes in WAL transactions
- **Storage overview** — sidebar card showing photos, video, and other disk usage

## Tech Stack

| Layer | Technology |
|---|---|
| UI | QML + Qt 6 Quick + [QmlMaterial](https://github.com/hypengw/QmlMaterial) |
| Backend | C++17, Qt 6 Core / Sql / Concurrent / Multimedia |
| Thumbnails | libvips (images), ffmpegthumbnailer (video), LibRaw (RAW) |
| Metadata | Exiv2 |
| Database | SQLite 3 (WAL mode) |
| Encryption | OpenSSL AES-256-CBC |

## Building

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
./build/kader
```

**Dependencies:** Qt 6 (Core Gui Qml Quick Sql Positioning Location Concurrent Multimedia), libvips, Exiv2, LibRaw, OpenSSL, ffmpegthumbnailer

On Arch Linux:
```bash
makepkg -si
```

## Usage

```bash
kader                        # open gallery
kader /path/to/photo.jpg     # open a single file directly
kader file:///path/to/photo  # XDG / .desktop %U handler
```
