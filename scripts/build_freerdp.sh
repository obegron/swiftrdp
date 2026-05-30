#!/bin/bash
set -e

# Configuration
SRCDIR="$(pwd)/ThirdParty/FreeRDP"
BUILDDIR="$(pwd)/Build/FreeRDP"
INSTALLDIR="$(pwd)/Build/install"

mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    FFMPEG_PREFIX="$(brew --prefix ffmpeg 2>/dev/null || true)"
    OPENSSL_PREFIX="$(brew --prefix openssl@3 2>/dev/null || true)"
    CMAKE_PREFIX_PATH="${FFMPEG_PREFIX};${OPENSSL_PREFIX};${BREW_PREFIX}"
else
    CMAKE_PREFIX_PATH=""
fi

CMAKE_PREFIX_ARGS=()
if [ -n "$CMAKE_PREFIX_PATH" ]; then
    CMAKE_PREFIX_ARGS+=("-DCMAKE_PREFIX_PATH=$CMAKE_PREFIX_PATH")
fi

if command -v sysctl >/dev/null 2>&1 && sysctl -n hw.ncpu >/dev/null 2>&1; then
    JOBS="$(sysctl -n hw.ncpu)"
else
    JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
fi

# Run CMake
# We disable as much as possible to keep it lean and native.
cmake "$SRCDIR" \
    "${CMAKE_PREFIX_ARGS[@]}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_CCACHE=OFF \
    -DWITH_X11=OFF \
    -DWITH_WAYLAND=OFF \
    -DWITH_PCSC=OFF \
    -DWITH_CUPS=OFF \
    -DWITH_PULSE=OFF \
    -DWITH_ALSA=OFF \
    -DWITH_CAIRO=OFF \
    -DWITH_OSS=OFF \
    -DWITH_OPENGL=OFF \
    -DWITH_MACAUDIO=ON \
    -DWITH_ZLIB=ON \
    -DWITH_OPENSSL=ON \
    -DWITH_FFMPEG=ON \
    -DWITH_VIDEO_FFMPEG=ON \
    -DWITH_VAAPI=OFF \
    -DWITH_VAAPI_H264_ENCODING=OFF \
    -DWITH_VIDEOTOOLBOX=ON \
    -DCHANNEL_URBDRC=OFF \
    -DWITH_SERVER=OFF \
    -DWITH_CLIENT=OFF \
    -DWITH_MANPAGES=OFF \
    -DBUILD_CLIENT=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_UTILS=OFF

# Build and Install
make -j"$JOBS"
make install

echo "----------------------------------------"
echo "FreeRDP Static Libraries built in: $INSTALLDIR"
echo "----------------------------------------"
