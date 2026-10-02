#!/usr/bin/env bash
# Build the pinned llama.cpp release as static, CPU-only libraries into a
# prefix, so Kader's AI search is linked in without any runtime dependency.
# Used by the PKGBUILD and the CI/AppImage builds.
#
#   packaging/build-llama.sh <prefix> [source-dir]
#
# Without a source dir the pinned tag is cloned next to the prefix.
set -euo pipefail

LLAMA_TAG="${LLAMA_TAG:-v0.5.0}"
prefix="$(realpath -m "${1:?usage: build-llama.sh <prefix> [source-dir]}")"
src="${2:-$prefix-src}"

if [[ ! -f "$src/CMakeLists.txt" ]]; then
    git clone --quiet --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp "$src"
fi

cmake -S "$src" -B "$src/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_NATIVE=OFF \
    -DLLAMA_BUILD_MTMD=ON \
    -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_APP=OFF -DLLAMA_BUILD_SERVER=OFF \
    -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_OPENSSL=OFF
cmake --build "$src/build"
cmake --install "$src/build"

# libmtmd.a needs llama.cpp's vendored helpers, which are built but not
# installed; fold their objects into the installed archive.
for vendor in "$src"/build/vendor/*/libvendor-*.a; do
    [[ -f "$vendor" ]] || continue
    tmp="$(mktemp -d)"
    (cd "$tmp" && ar x "$vendor" && ar rcs "$prefix/lib/libmtmd.a" ./*.o)
    rm -rf "$tmp"
done
echo "llama.cpp $LLAMA_TAG installed to $prefix"
