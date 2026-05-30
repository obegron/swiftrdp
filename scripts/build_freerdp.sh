#!/bin/bash
set -e

# Configuration
SRCDIR="$(pwd)/ThirdParty/FreeRDP"
BUILDDIR="$(pwd)/Build/FreeRDP"
INSTALLDIR="$(pwd)/Build/install"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# Run CMake
# We disable as much as possible to keep it lean and native.
cmake "$SRCDIR" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_X11=OFF \
    -DWITH_WAYLAND=OFF \
    -DWITH_PCSC=OFF \
    -DWITH_CUPS=OFF \
    -DWITH_PULSE=OFF \
    -DWITH_ALSA=OFF \
    -DWITH_CAIRO=OFF \
    -DWITH_OSS=OFF \
    -DWITH_OPENGL=OFF \
    -DWITH_ZLIB=ON \
    -DWITH_OPENSSL=ON \
    -DCHANNEL_URBDRC=OFF \
    -DWITH_SERVER=OFF \
    -DWITH_CLIENT=OFF \
    -DWITH_MANPAGES=OFF \
    -DBUILD_CLIENT=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_UTILS=OFF

# Build and Install
make -j$(sysctl -n hw.ncpu)
make install

echo "----------------------------------------"
echo "FreeRDP Static Libraries built in: $INSTALLDIR"
echo "----------------------------------------"
