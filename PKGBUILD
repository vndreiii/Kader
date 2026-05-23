# Maintainer: Alex <alex@milfs.party>
pkgname=kader
pkgver=0.1.0
pkgrel=1
pkgdesc="Modern photo gallery"
arch=('x86_64')
url="https://code.milfs.party/alex/Kader"
license=('MIT')
depends=(
    'qt6-base'
    'qt6-declarative'
    'qt6-location'
    'vips'
    'exiv2'
    'openssl'
    'libheif'
)
makedepends=(
    'cmake'
    'ninja'
    'qt6-tools'
    'pkgconfig'
)
source=("$pkgname::git+ssh://git@code.milfs.party:2222/alex/Kader.git")
sha256sums=('SKIP')

pkgver() {
    cd "$pkgname"
    git describe --tags --long 2>/dev/null | sed 's/\([^-]*-g\)/r\1/;s/-/./g' \
        || printf "0.1.0.r%s.%s" "$(git rev-list --count HEAD)" "$(git rev-parse --short HEAD)"
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

    # Binary lives in /usr/lib/kader/ so applicationDirPath()+"/qml_modules" resolves correctly
    install -Dm755 "build-pkg/kader" "$pkgdir/usr/lib/kader/kader"

    # QML module (QmlMaterial / Qcm.Material)
    if [ -d "build-pkg/qml_modules" ]; then
        cp -r "build-pkg/qml_modules" "$pkgdir/usr/lib/kader/qml_modules"
    fi

    # Wrapper script in PATH
    install -Dm755 /dev/stdin "$pkgdir/usr/bin/kader" <<'EOF'
#!/bin/sh
exec /usr/lib/kader/kader "$@"
EOF

    # Desktop entry
    install -Dm644 "$pkgname/kader.desktop" "$pkgdir/usr/share/applications/kader.desktop"

    # Icon
    install -Dm644 "$pkgname/assets/icon.svg" "$pkgdir/usr/share/icons/hicolor/scalable/apps/kader.svg"
}
