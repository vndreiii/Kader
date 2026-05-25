# Maintainer: Alex <alex@milfs.party>
pkgname=kader
pkgver=0.1.0.r55.cf4964b
pkgrel=1
pkgdesc="Modern photo gallery"
arch=('x86_64')
url="https://code.milfs.party/alex/Kader"
license=('MIT')
depends=(
    'qt6-base'
    'qt6-declarative'
    'qt6-location'
    'qt6-positioning'
    'qt6-shadertools'
    'libvips'
    'exiv2'
    'openssl'
    'libheif'
    'libraw'
)
makedepends=(
    'cmake'
    'ninja'
    'qt6-tools'
    'pkgconfig'
)
source=(
    "$pkgname::git+ssh://git@code.milfs.party:2222/alex/Kader.git"
    "QmlMaterial::git+https://github.com/hypengw/QmlMaterial"
)
sha256sums=('SKIP' 'SKIP')

pkgver() {
    cd "$pkgname"
    local ver=$(git describe --tags --long 2>/dev/null | sed 's/\([^-]*-g\)/r\1/;s/-/./g')
    if [ -z "$ver" ]; then
        printf "0.1.0.r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
    else
        echo "$ver"
    fi
}

prepare() {
    cd "$pkgname"
    mkdir -p lib
    rm -rf lib/QmlMaterial
    ln -sf "$srcdir/QmlMaterial" lib/QmlMaterial
}

build() {
    cmake -B build-pkg -S "$pkgname" \
        -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DBUILD_TESTING=OFF
    cmake --build build-pkg
}

package() {
    cd "$srcdir"

    # Binary lives in /usr/lib/kader/
    install -Dm755 "build-pkg/kader" "$pkgdir/usr/lib/kader/kader"

    # QML modules (like Qcm.Material)
    if [ -d "build-pkg/qml_modules" ]; then
        mkdir -p "$pkgdir/usr/lib/kader/qml_modules"
        cp -r build-pkg/qml_modules/* "$pkgdir/usr/lib/kader/qml_modules/"
    fi

    # Wrapper script in PATH
    install -Dm755 /dev/stdin "$pkgdir/usr/bin/kader" <<'EOF'
#!/bin/sh
# QmlMaterial is looked up relative to app path or via import path
export QML2_IMPORT_PATH="/usr/lib/kader/qml_modules:$QML2_IMPORT_PATH"
exec /usr/lib/kader/kader "$@"
EOF

    # Desktop entry
    install -Dm644 "$pkgname/kader.desktop" "$pkgdir/usr/share/applications/kader.desktop"

    # Icons — scalable SVG only (avoids upgrade conflicts with fixed-size PNGs)
    install -Dm644 "$pkgname/assets/Kader Logoicon.svg" "$pkgdir/usr/share/icons/hicolor/scalable/apps/kader.svg"
}
