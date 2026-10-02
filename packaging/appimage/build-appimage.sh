#!/usr/bin/env bash
# Package a finished CMake build of Kader as an AppImage.
#
#   packaging/appimage/build-appimage.sh <cmake-build-dir> <output-dir>
#
# Env:
#   QMAKE            qmake of the Qt to bundle (default: qmake6/qmake in PATH)
#   LINUXDEPLOY_DIR  where linuxdeploy tools live / get downloaded
#
# The result embeds AppImage update information for GitHub releases, but Kader
# updates itself through its own signed manifest (see UpdateManager).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="$(realpath "${1:?usage: build-appimage.sh <build-dir> <output-dir>}")"
out="$(realpath -m "${2:?usage: build-appimage.sh <build-dir> <output-dir>}")"
version="$(sed -n 's/^project(Kader VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")"
appdir="$build/AppDir"
tools="${LINUXDEPLOY_DIR:-$build/linuxdeploy}"
mkdir -p "$out" "$tools"

fetch() {
    local url="$1" dest="$tools/$(basename "$1")"
    [[ -x "$dest" ]] || { curl -fsSL --retry 3 -o "$dest" "$url"; chmod +x "$dest"; }
}
fetch https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage
fetch https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage

rm -rf "$appdir"
DESTDIR="$appdir" cmake --install "$build" --prefix /usr

export PATH="$tools:$PATH"
export APPIMAGE_EXTRACT_AND_RUN=1           # no FUSE needed (CI containers)
export QMAKE="${QMAKE:-$(command -v qmake6 || command -v qmake)}"
# linuxdeploy resolves libraries like the dynamic loader does: a Qt outside
# the system prefix (aqtinstall in CI) has to be on the search path
export LD_LIBRARY_PATH="$("$QMAKE" -query QT_INSTALL_LIBS)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QML_SOURCES_PATHS="$root/qml"
export EXTRA_QT_MODULES="svg;waylandclient"
# Ship native Wayland support alongside xcb (whichever plugins this Qt has).
plugdir="$("$QMAKE" -query QT_INSTALL_PLUGINS)/platforms"
extra=()
for p in libqwayland-egl.so libqwayland-generic.so libqwayland.so; do
    [[ -f "$plugdir/$p" ]] && extra+=("$p")
done
EXTRA_PLATFORM_PLUGINS="$(IFS=';'; echo "${extra[*]:-}")"
export EXTRA_PLATFORM_PLUGINS
export LDAI_OUTPUT="$out/Kader-$version-x86_64.AppImage"
export LDAI_UPDATE_INFORMATION="gh-releases-zsync|vndreiii|kader|latest|Kader-*x86_64.AppImage.zsync"
export LDAI_COMP=zstd

# Qt Multimedia is only used from QML (the viewer's video player), so the
# Qt plugin can't see it in the binary's dependencies: bundle the libraries
# and the FFmpeg backend explicitly. Without them the QtMultimedia QML plugin
# falls back to the host's Qt (and fails when that Qt differs).
qtlibs="$("$QMAKE" -query QT_INSTALL_LIBS)"
mmplugins="$("$QMAKE" -query QT_INSTALL_PLUGINS)/multimedia"
mm=()
for lib in libQt6Multimedia.so.6 libQt6MultimediaQuick.so.6; do
    mm+=(--library "$qtlibs/$lib")
done
if [[ -d "$mmplugins" ]]; then
    mkdir -p "$appdir/usr/plugins/multimedia"
    cp "$mmplugins"/*.so "$appdir/usr/plugins/multimedia/"
    mm+=(--deploy-deps-only "$appdir/usr/plugins/multimedia")
fi

linuxdeploy-x86_64.AppImage \
    --appdir "$appdir" \
    --desktop-file "$appdir/usr/share/applications/kader.desktop" \
    --icon-file "$appdir/usr/share/icons/hicolor/256x256/apps/kader.png" \
    "${mm[@]}" \
    --plugin qt \
    --output appimage

echo "AppImage: $LDAI_OUTPUT"
