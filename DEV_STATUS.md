# Kader Gallery — Dev Status

**Last updated:** 2026-05-23  
**Stack:** Qt 6 / QML / C++17 · libvips thumbnails · SQLite · QmlMaterial (`import Qcm.Material as MD`)  
**Build:** `cmake --build build --parallel`  
**Run:** `build/kader`

---

## Architecture at a Glance

```
src/
  main.cpp               — registers all C++ context objects in QML engine
  DatabaseManager.cpp/h  — SQLite; getAllMedia(), pruneOrphanedMedia(), toggleFavorite(), etc.
  FileScanner.cpp/h      — background dir scan via QtConcurrent; emits scanStarted/Progress/Finished
  TimelineModel.cpp/h    — QAbstractListModel; aspect-ratio row packing (Google Photos style)
  ThumbnailGenerator.cpp/h — getOrCreateThumbnail() via libvips; disk cache ~/.cache/kader/thumbs/
  ThumbnailProvider.cpp/h  — QQuickImageProvider "thumbnails"; requestImage() on Qt image thread
  AlbumModel.cpp/h       — folder-grouped album list; pinned/ignored/trashed states
  StorageManager.cpp/h   — disk usage stats

qml/
  main.qml               — ApplicationWindow, Sidebar, StackView, FAB, scan banner, ViewerOverlay
  views/
    AlbumListView.qml    — GridView of albums with right-click menu
    AlbumDetailView.qml  — filtered mosaic for one album (passes folderPath to TimelineModel)
    ViewerOverlay.qml    — full-screen image viewer with zoom/pan
    MapView.qml          — GPS map (OSM + Carto Dark Matter tiles)
    SettingsView.qml     — settings (scan dirs, etc.)
  components/
    Tile.qml             — single media tile; rounded corners via MultiEffect; right-click menu
    MediaGrid.qml        — timeline ListView with aspect-ratio row packing + date scrubber
    Sidebar.qml          — left nav with animated spring-bounce pill
    SidebarItem.qml      — nav entry with outline→filled icon animation
    M3Icon.qml           — SVG path icon renderer (ALL icons hardcoded as path strings here)
    MediaInfoPanel.qml   — EXIF info panel; slides in from right in viewer
```

### QML Context Properties (registered in main.cpp)
`DB`, `FileScanner`, `TimelineModel`, `AlbumModel`, `StorageManager`, `ThemeManager`, `Settings`

---

## What's Working

### Mosaic / Timeline
- Aspect-ratio row packing: photos keep real aspect ratios, rows fill contentWidth at ~260px target height, row height varies naturally
- Hero tiles: every 9th photo (flatIdx % 9 == 4) is a single full-width tile at 1.5× target height; loads original file (bypasses thumbnail) for quality
- Width-responsive via debounced `setContentWidth()` (8px threshold + 120ms timer)
- Scroll position preserved across fav toggles, model refreshes, and view switches (`Qt.callLater` defer pattern)
- Fast-scroll date scrubber on right edge (drag handle shows month label)
- Right-click on any tile: Favorite/Unfavorite, Open in Folder, Move to Trash / Restore

### Thumbnails
- URL: `"image://thumbnails" + filePath` — **NO extra slash** (double-slash silently kills provider call)
- `requestImage()` restores leading `/`: `const QString fp = id.startsWith('/') ? id : '/' + id`
- 512px via libvips, cached to disk
- Hero tiles (tile width > 600px) use `"file://" + file_path` directly for full quality

### Tile Rounded Corners (Tile.qml)
- `clip: true` alone only clips to bounding box — does NOT clip to radius
- `layer.enabled: true` alone also does NOT clip children to rounded shape
- **Correct fix:** `MultiEffect { maskEnabled: true; maskSource: roundMask }` from `import QtQuick.Effects`
  - `roundMask` = invisible Rectangle with `radius: 16` and `layer.enabled: true`
  - `contentLayer` Item wraps all content and applies `layer.effect: MultiEffect {...}`

### Viewer Overlay (ViewerOverlay.qml)
- Zoom: double-click toggles 1×↔2.5×; Ctrl+scroll continuous 1×–8×; drag to pan when zoomed
- Bottom-center zoom controls: − / 100% / + (percentage label acts as reset)
- Zoom resets on nav (prev/next) and media change; backdrop click only dismisses at 1×
- Slide transition with direction (left/right) on navigate
- `autoTransform: true` on images (EXIF orientation for portrait photos)
- All buttons: `Rectangle + MouseArea + M3Icon` — **never `Button`** (Qcm.Material makes it a thin pill)

### Sidebar (Sidebar.qml)
- Spring-bounce pill: `SpringAnimation { spring: 600; damping: 28; mass: 1.0 }`
- Animated icon fill: SidebarItem uses two overlaid M3Icons (outline + filled) with opacity crossfade
- Toggle: `"menu"` when collapsed, `"menu_close"` when open — both defined in M3Icon.qml

### Icons (M3Icon.qml)
**ALL icons are hardcoded SVG path strings.** If an icon name is not in the map → empty path → invisible. Always check before using a new name.

Currently defined: `schedule`, `folder`, `map`, `favorite`, `favorite_fill`, `delete`, `settings`, `search`, `menu_open`, `menu_close`, `menu`, `tune`, `close`, `computer`, `pin`, `more_vert`, `add`, `remove`, `check`, `play`, `chevron_left`, `chevron_right`, `folder_open`, `info`, `delete_forever`, `video_library`, `videocam`, `schedule_fill`, `folder_fill`, `map_fill`, `delete_fill`, `settings_fill`, `video_library_fill`, `app_icon`

---

## Pending / Next Session

### 1. Settings "Add directory & Scan" button (HIGH)
- FAB and Settings currently hardcode `Settings.homePath + "/Pictures"`
- Should open XDG folder picker: `Qt.labs.platform.FolderDialog` or `QtQuick.Dialogs.FolderDialog`
- `qml/views/SettingsView.qml` — verify `folderPicker.open()` is wired to the button

### 2. Hidden Images with Password (Task #9 — full spec below)

### 3. Periodic background prune (MEDIUM)
- `DatabaseManager::pruneOrphanedMedia()` exists and is thread-safe (named connection pattern)
- Not yet scheduled — add `QTimer` in main.cpp, interval 5 min, calls `DB.pruneOrphanedMedia()`

### 4. Album viewer uses global allItems (MEDIUM)
- Opening viewer from AlbumDetailView sets `allItems = TimelineModel.getFlatMediaList()` (global)
- Prev/next navigates global timeline, not album-filtered list
- Fix: AlbumDetailView should maintain its own filtered list and pass it to viewer

### 5. Video playback (LOW)
- Videos appear in timeline with a play badge but show static thumbnails only
- Options: `QtMultimedia.Video` inline, or spawn `mpv` via `Qt.openUrlExternally`

---

## Hidden Images — Full Implementation Plan (Task #9)

### Goal
A "Hidden" section in the sidebar, password-protected, shows photos the user has hidden. Optional: AES-256 encrypt the actual files on disk.

### Database changes
```sql
-- Add to media table
ALTER TABLE media ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0;
-- New settings table entry (or reuse existing settings table)
INSERT INTO settings(key, value) VALUES('hidden_password_hash', '');
-- Optional: track encryption state
ALTER TABLE media ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 0;
```

### C++ changes (DatabaseManager.h/cpp)
```cpp
// New methods
void     setHidden(int id, bool hidden);
bool     checkHiddenPassword(const QString &password);  // compare against stored bcrypt/SHA256
void     setHiddenPassword(const QString &newPassword);
bool     hasHiddenPassword();
// Optional encryption
bool     encryptFile(const QString &filePath);   // AES-256-CBC via OpenSSL (already linked)
bool     decryptFile(const QString &filePath);
```

### QML changes
1. **Sidebar.qml**: Add `SidebarItem { icon: "lock"; label: "Hidden" }` below Trash
2. **main.qml**: Add `"hidden"` case in `onViewChanged`; before switching push a `PasswordPrompt` dialog
3. **TimelineModel**: Add `HiddenMode = 3` to `FilterMode` enum; filter `WHERE is_hidden = 1`
4. **PasswordPrompt.qml** (new component): Modal dialog with PIN/password field; calls `DB.checkHiddenPassword()`; on success emits `accepted`
5. **Tile.qml context menu**: Add "Hide" / "Unhide" option (only unhide when in Hidden view)

### Flow
```
User clicks "Hidden" in sidebar
  → PasswordPrompt dialog appears
  → If no password set yet: ask to create one (confirm twice)
  → If password set: ask for existing password
  → DB.checkHiddenPassword() → SHA-256(input) == stored hash
  → On success: window.currentView = "hidden", TimelineModel.filterMode = HiddenMode
  → On fail: shake animation, don't navigate
```

### Optional disk encryption
- When hiding a photo: copy original → encrypt in-place (AES-256-CBC) → update DB `is_encrypted = 1`
- When viewing hidden photo: decrypt to temp file → load → delete temp on viewer close
- OR: decrypt to memory buffer → load via `QQuickImageProvider` from memory → never touches disk
- OpenSSL is already linked (`find_package(OpenSSL REQUIRED COMPONENTS Crypto)`)
- Key derivation: `PBKDF2(password, machine-id, 100000 iterations, SHA-256)` → 32-byte AES key

### Settings integration
- Add toggle in SettingsView: "Encrypt hidden files on disk"
- Add "Change hidden password" button
- Add "Show hidden photos count" (or keep count hidden for privacy)

---

## Critical "Never Do" Rules

1. **Never name a QML property `modelData`** — shadows Repeater context, all tiles get `{}` silently
2. **Thumbnail URL: no double slash** — `"image://thumbnails" + filePath` not `"image://thumbnails/" + "/home/..."` 
3. **Never use `Button` with Qcm.Material** — Material style turns it into a thin pill. Use `Rectangle + MouseArea + M3Icon`
4. **Context menu `onTriggered` loses `model`** — always capture in local delegate `property string _path: model.path || ""`
5. **`clip: true` only clips to bounding rect** — use `MultiEffect { maskEnabled: true }` for rounded corners
6. **AlbumModel role is `model.path` not `model.folder_path`**
7. **`pruneOrphanedMedia()` must use thread-local named connection** — `m_db` from background thread = crash
8. **Check M3Icon.qml before using any icon name** — undefined names = invisible (empty SVG path)
9. **Scroll restore must use `Qt.callLater`** — not a timer; defers until after layout is complete
