# Changelog

Kader follows [semantic versioning](https://semver.org): MAJOR.MINOR.FIX.
Release notes for each version are taken from this file.

## [1.0.0]

First release with semantic versioning (packages before this used
date-based versions such as 2026.08.125; the Arch package carries an epoch so
pacman upgrades cleanly).

### Places: a new 3D globe
- Dotted-land globe that refines as you zoom, with coastlines, lakes, country
  and state borders, and place names from oceans down to towns of 5000+.
- Photo pins land exactly on their places, cluster when they overlap and split
  as you zoom in; the place card follows its pin and opens every photo taken
  there.
- Offline place names ("Lyon, France") in the places list — no network needed.
- Smooth drag with inertia, zoom towards the cursor, pinch and keyboard control.
- Powered by a new memory-safe Rust engine (`rust/kader-core`).

### Updates
- Kader now updates itself from GitHub releases. Updates are signed and
  verified before installing: the AppImage replaces itself, the Arch package
  installs through pacman.

### Fixes & polish
- Frameless windows can be moved and resized on Wayland and X11.
- Builds without the private milfs-connect library and without llama.cpp.
- Video thumbnails find ffmpeg tools on any distro.
