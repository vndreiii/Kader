# KaderGallery

Kader (photo/media gallery app) was integrated with the new milfs-connect shared library so it can receive live "media added" events from sibling apps (e.g. Recamara, the camera app) without waiting for its next full directory scan, and so it can be deep-linked to open directly on a specific photo/video.

## Work completed

- Added `find_package(MilfsConnect REQUIRED)` to CMakeLists.txt and linked `MilfsConnect::MilfsConnect` into the `kader` target.
- In `src/main.cpp`: constructed a `MilfsConnect::Bus` for appId `"kader"` and subscribed to `media.added` events — on receipt, if the event's file path exists and its containing directory isn't already indexed, it's added as an indexed directory and an incremental scan is kicked off, so newly-captured media from other apps shows up live.
- Confirmed Kader already supported deep-linking via a bare file-path CLI argument (`Exec=kader %U`) — no new flag needed; verified end-to-end that launching Kader with a photo path opens `ViewerWindow.qml` focused on that photo (user-confirmed working).
- Fixed an unrelated, real, user-reported UI bug: a white border/corner artifact around Kader's frameless, rounded-corner main window. Root cause: the QML `ApplicationWindow` had a rounded-corner `background: Rectangle` but the underlying window surface wasn't alpha-enabled, so the opaque rectangular window surface showed through around the rounded corners. Fixed with the standard two-part Qt Quick fix: `QQuickWindow::setDefaultAlphaBuffer(true)` called before `QGuiApplication` construction in main.cpp, plus `color: "transparent"` on the root `ApplicationWindow` in `qml/main.qml`. User confirmed the fix visually resolved the issue.
- Added `'milfs-connect'` to the PKGBUILD's `makedepends`.
- Committed and pushed all of the above to Kader's own repo (`ssh://git@code.milfs.party:2222/alex/Kader.git`, commit `b359eec`).
- Built the real system package via `makepkg -f --noconfirm` (this only succeeded once the milfs-connect packaging bug described in milfs-connect's own SUMMARY was fixed — the static archive was previously broken), then installed it via `pacman -U`. Confirmed the freshly-built-and-installed real system package launches and runs correctly, actively performing real work (photo/video thumbnail generation).
- **Dynamic Color & Matugen Support**: Implemented a `dynamicColor` property in `ThemeManager` to dynamically load Material 3 design tokens from Quickshell's generated `material_colors.scss` file. It automatically translates `kebab-case` and `snake_case` variables into `camelCase`, and handles the 'Pinkish Accent Fix' (prioritizing `$inversePrimary` over `$primary` in dark mode). Added instructions for configuring Matugen templates in `README.md` and created a Matugen template on the user's system to sync with Kader seamlessly.

## Open / future items

- Noted but not acted on (out of the requested scope): a pre-existing structural quirk in `main.cpp` where the `viewerOnly` variable is defined *after* the early-return path for a non-empty `startupFile` argument, meaning it's effectively always `false` by the time gallery-mode setup code runs. Not something introduced by this work; flagged for awareness only.
- While smoke-testing the installed package, encountered a SIGPIPE-related process exit when the thumbnail generator's ffmpeg subprocess feeder thread hit files with invalid/corrupt video containers (an EBML parse failure and a missing `moov` atom, in two specific files in the user's library) — this looked like a possible unhandled-SIGPIPE crash path in the subprocess feeder. The user confirmed the app "genuinely is fine, it opens and works" in normal use, so this was NOT pursued further or fixed — flagging only in case it resurfaces.

## 2026-08-11

- **claude-mem:learn-codebase pass completed**: Full read-only pass through entire repository codebase. Every source file was read in full: `include/*.h` headers, `src/*.cpp` implementations, `qml/components/*.qml` and `qml/views/*.qml`, `qml/main.qml`, `qml/I18n.js` (18-language translation table), `qml/shaders/globe.frag` shader, all `tests/*.cpp` and `tests/benchmarks/*.cpp`, `tests/tst_ui.qml`, `CMakeLists.txt`, `PKGBUILD`, `scripts/generate_icon.py`, and deployment/documentation scripts. Builds passive semantic memory context for future sessions — no code was changed.
- **task-observer skill initialized**: First-time setup for this repository. Created observation log at `/home/meh/.claude/projects/-home-meh-Projects-KaderGallery/skill-observations/log.md` and `last-review-date.txt`.
- **Open observation #1 (flagged OPEN)**: claude-mem's auto-compression of Read tool results can silently replace full file content with a compressed skeleton even on a file's very first read during learn-codebase, meaning "read every file in full" is satisfied via semantic memory capture rather than literally visible context. Needs input on whether that's intended behavior — review pending in observation log.

## 2026-08-24

- **Zoom and Pan Jitter Fixes**: Completely resolved intense jittering and dizziness issues when zooming with the mouse wheel in `ViewerOverlay.qml`.
- The previous implementation grabbed intermediate mid-animation values of `_zoom` while rapid scrolling occurred, compounding math errors and causing wild jumping. Fixed by introducing decoupled target variables (`_targetZoom`, `_targetPanX`, `_targetPanY`) to run mathematical calculations cleanly against the intended zoom factor, preserving buttery-smooth QML `Behavior` interpolation.
- Fixed an incorrect mathematical offset where the image center for focal point calculations incorrectly referenced `root.width/2` instead of `imgArea`'s margins, resulting in the image shifting away from the cursor.
- Updated mouse drag handlers to immediately sync with target pan properties, removing abrupt snaps caused by state misalignment between manual dragging and programmatic zooming.
- Addressed boundary crossover snapping bugs where zooming out past the screen bounds would incorrectly reset pan translation.
- Packaged and installed via `makepkg` and `pacman/yay`.
