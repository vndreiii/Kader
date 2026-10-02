# Changelog

Kader follows [semantic versioning](https://semver.org): MAJOR.MINOR.FIX.
Release notes for each version are taken from this file.

## [2.1.0]

### Windows
Kader now runs on Windows 10 and 11, in two flavours:
- **Installer** (`…-windows-x64-setup.exe`): installs for your user without
  administrator rights, adds a Start menu entry, an optional desktop shortcut
  and "Open with Kader" for photos and videos (your default apps are left
  alone). The uninstaller removes only Kader's files and asks before deleting
  your library index.
- **Portable** (`…-windows-x64-portable.zip`): unzip anywhere and run; the
  library, thumbnails and settings stay in a `data` folder next to it.

Both update themselves from signed releases. Windows paths (drive letters,
network shares, any language) work throughout, "Show in folder" opens
Explorer, and "System" theme and dynamic colour follow Windows' light/dark
mode and accent colour.

### Fixed
- The AppImage crashed at start on Wayland (Hyprland, niri, GNOME, KDE…)
  with "Failed to create RHI": Qt's Wayland graphics integration wasn't
  bundled. Every AppImage is now launched on Wayland and X11 in CI before
  release.
- File names containing `#` or `%` didn't show thumbnails or open.
- "System" theme loaded no colours when no Quickshell palette was present;
  it now follows the desktop's light/dark setting.
- Controls keep Kader's Material 3 look on every desktop (KDE included)
  instead of picking up the desktop's widget style.

## [2.0.1]

### Fixed
- The AppImage didn't open on systems with a different Qt version installed
  (for example Arch with Qt 6.11): it now bundles Qt Multimedia and its
  FFmpeg backend instead of picking up the system's copy. CI now launches
  every AppImage before it is released.

## [2.0.0]

The first release with semantic versioning (packages before this used
date-based versions such as 2026.08.125; the Arch package carries an epoch so
pacman upgrades cleanly). Much of Kader was rebuilt for it.

### Search, people and memories
- New **Search** tab: one box finds people by name, places (city or
  country), colours, years and months, albums and file names instantly,
  with visual AI matches below.
- **People**: faces are found and recognised on your computer (opt-in, two
  small models downloaded once) and grouped into people. Name them, remove
  wrong faces, add faces from suggestions, merge, hide, and calibrate how
  strict the grouping is.
- **Memories** (on this day, trips named after where they happened,
  years), **places**, **things** (sunsets, food, pets… from the AI index)
  and **colours**.
- Smart (AI) search actually works now: the embedding model is used as
  designed, HEIC/RAW/video are indexed from thumbnails, and results no
  longer vanish after a search. Existing AI indexes are rebuilt once.

### Places: a new 3D globe
- Dotted-land globe that refines as you zoom: coastlines, borders and place
  names from oceans down to towns, with soft, readable styling.
- Squircle photo pins that cluster and split as you zoom; a clicked pin
  morphs into its place card.
- Places panel with search and sorting that collapses to a slim rail.
- Offline place names, smooth drag, zoom towards the cursor.

### Viewer
- Opening a photo from your file manager is much faster.
- The photo fills the whole window; high-contrast controls stay visible
  (they step aside only in fullscreen); progressive loading from the
  thumbnail.

### Storage, settings and more
- Storage dashboard: where the space goes (disk overview, folders, years,
  file types) and how to win it back (largest files, likely duplicates,
  trash).
- Settings redesigned after Material 3 Expressive, with search. Every
  option works: auto-scan watches your folders, trash empties itself after
  the period you choose, metadata (or just location) can be stripped from
  photos.
- About page with licences; support Kader on Ko-fi.
- Window buttons on desktops that expect them (none under tiling window
  managers like Hyprland or niri).
- Loading skeletons everywhere instead of empty screens.

### Speed
- Library scanning rewritten in Rust: a 5,000-photo folder indexes in about
  half a second instead of several seconds; deleted files are pruned during
  scans.
- Faster start-up, and no needless refreshes after rescans that changed
  nothing.

### Updates
- Kader updates itself from GitHub releases. Updates are signed and
  verified before installing: the AppImage replaces itself, the Arch package
  installs through pacman.
- AppImage builds alongside the Arch package.
