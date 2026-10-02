#!/usr/bin/env bash
# Package a finished Windows (MSYS2 UCRT64) build of Kader as
#   Kader-<version>-windows-x64-portable.zip   unzip and run; keeps its data
#                                              in a "data" folder beside it
#   Kader-<version>-windows-x64-setup.exe      per-user NSIS installer (no
#                                              admin rights needed)
#
#   packaging/windows/deploy.sh <cmake-build-dir> <output-dir>
#
# Runs in an MSYS2 UCRT64 shell with windeployqt6, ldd, makensis and python.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build="$(realpath "${1:?usage: deploy.sh <build-dir> <output-dir>}")"
out="$(realpath -m "${2:?usage: deploy.sh <build-dir> <output-dir>}")"
version="$(sed -n 's/^project(Kader VERSION \([0-9.]*\).*/\1/p' "$root/CMakeLists.txt")"
prefix="${MINGW_PREFIX:-/ucrt64}"
stage="$build/stage/Kader"
mkdir -p "$out"

rm -rf "$build/stage"
cmake --install "$build" --prefix "$stage"
strip "$stage/kader.exe"

# ── Qt: libraries, plugins and the QML modules main.qml imports ────────────
wdq="$(command -v windeployqt6 || command -v windeployqt-qt6 || command -v windeployqt)"
"$wdq" --release --qmldir "$root/qml" --dir "$stage" \
    --no-translations --no-system-d3d-compiler --no-opengl-sw \
    "$stage/kader.exe"

# ── Helper programs and decoder plugins ────────────────────────────────────
cp "$prefix/bin/ffmpeg.exe" "$prefix/bin/ffprobe.exe" "$stage/"
vipsver="$(pkg-config --modversion vips | cut -d. -f1,2)"
if [[ -d "$prefix/lib/vips-modules-$vipsver" ]]; then
    mkdir -p "$stage/lib"
    cp -r "$prefix/lib/vips-modules-$vipsver" "$stage/lib/"
    # ImageMagick and OpenSlide loaders would drag in large libraries for
    # formats Kader doesn't list; libvips skips modules that aren't there.
    rm -f "$stage/lib/vips-modules-$vipsver/vips-magick.dll" "$stage/lib/vips-modules-$vipsver/vips-openslide.dll"
fi
if [[ -d "$prefix/lib/libheif/plugins" ]]; then
    mkdir -p "$stage/lib/libheif"
    cp "$prefix/lib/libheif/plugins/"*.dll "$stage/lib/libheif/"
fi

# ── Every MinGW DLL anything in the folder needs, until nothing is missing ─
while :; do
    added=0
    while IFS= read -r dll; do
        name="$(basename "$dll")"
        if [[ ! -f "$stage/$name" ]]; then
            cp "$dll" "$stage/"
            added=$((added + 1))
        fi
    done < <(find "$stage" -iname '*.exe' -o -iname '*.dll' | while read -r f; do ldd "$f" 2>/dev/null; done \
             | awk -v p="$prefix/bin/" 'index($3, p) == 1 { print $3 }' | sort -u)
    [[ $added -eq 0 ]] && break
    echo "added $added DLLs"
done

cp "$root/packaging/windows/kader.ico" "$stage/"
du -sh "$stage"

# ── Portable .zip ───────────────────────────────────────────────────────────
portable="$build/stage/portable/Kader"
rm -rf "$build/stage/portable"
mkdir -p "$(dirname "$portable")"
cp -r "$stage" "$portable"
cat > "$portable/portable.txt" <<'EOF'
Portable Kader: your library, thumbnails and settings are kept in the "data"
folder next to kader.exe instead of in your user profile. Delete this file to
make Kader use your user profile instead.
EOF
zip="$out/Kader-$version-windows-x64-portable.zip"
rm -f "$zip"
(cd "$build/stage/portable" && python -c 'import shutil,sys; shutil.make_archive(sys.argv[1], "zip", ".", "Kader")' "$(cygpath -w "${zip%.zip}")")

# ── Installer ───────────────────────────────────────────────────────────────
python "$(cygpath -w "$root/packaging/windows/nsis_filelist.py")" "$(cygpath -w "$stage")" \
    "$(cygpath -w "$build/stage/files.nsh")" "$(cygpath -w "$build/stage/unfiles.nsh")"
makensis -V2 -INPUTCHARSET UTF8 \
    -DVERSION="$version" \
    -DSRCDIR="$(cygpath -w "$stage")" \
    -DFILES="$(cygpath -w "$build/stage/files.nsh")" \
    -DUNFILES="$(cygpath -w "$build/stage/unfiles.nsh")" \
    -DICON="$(cygpath -w "$root/packaging/windows/kader.ico")" \
    -DOUTFILE="$(cygpath -w "$out/Kader-$version-windows-x64-setup.exe")" \
    "$(cygpath -w "$root/packaging/windows/kader.nsi")"

ls -la "$out"
