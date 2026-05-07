# Kader

A modern Linux gallery app inspired by Android, built with Qt 6, QML (Material 3), and C++.

## Branding
- **Name:** Kader
- **Icon:** An eye inside a frame.

## Key Features
- Timeline view (mosaic grid, monthly separation).
- Album view (folder-based, weight calculation, pinning, custom covers).
- Smart views (Location/Maps, Favorites, Trash).
- Fast parallel metadata parsing (Exiv2).
- Ultra-fast thumbnail generation (libvips).
- Integrated video player (libmpv).
- Dynamic Material 3 theming from system SCSS.

## Tech Stack
- **Frontend:** QML (Qt 6) + [QmlMaterial](https://github.com/hypengw/QmlMaterial)
- **Backend:** C++17/20 (Qt 6)
- **Database:** SQLite 3
- **Image/Video:** libvips, Exiv2, libmpv
