#!/usr/bin/env bash
# Reproducible build of the Sentinel "ultimate" Sunshine fork for the exact target box:
# Fedora, EC2 m7i.xlarge (4 vCPU Sapphire Rapids, no GPU). Software x264 path only.
#
# - uses gcc14 (the toolchain Sunshine expects at this commit; gcc15 may not compile it)
# - -march=native to exploit Sapphire Rapids / AVX-512 in Sunshine's own C++
# - CUDA/NVENC disabled (no GPU)
# - builds into ./build and installs to /opt/sunshine-ultimate so the stock
#   /usr/bin/sunshine stays untouched as an instant rollback
set -euo pipefail
SRC="${SRC:-$HOME/sunshine-src}"
PREFIX="${PREFIX:-/opt/sunshine-ultimate}"
cd "$SRC"

echo "==== [1/5] build dependencies ===="
sudo dnf install -y \
  cmake git wget which desktop-file-utils rpm-build systemd-rpm-macros \
  gcc14 gcc14-c++ libatomic \
  boost-devel \
  openssl-devel libcurl-devel libcap-devel libdrm-devel libevdev-devel \
  libnotify-devel libva-devel numactl-devel opus-devel miniupnpc-devel \
  pulseaudio-libs-devel pipewire-devel \
  libX11-devel libxcb-devel libXcursor-devel libXfixes-devel libXi-devel \
  libXinerama-devel libXrandr-devel libXtst-devel \
  mesa-libGL-devel mesa-libgbm-devel \
  libayatana-appindicator3-devel libgudev \
  vulkan-loader-devel vulkan-headers shaderc \
  nodejs-npm python3-jinja2 python3-setuptools \
  appstream libappstream-glib xorg-x11-server-Xvfb || true

echo "==== [2/5] submodules ===="
git submodule update --init --recursive

echo "==== [3/5] configure (gcc14, -march=native, no CUDA) ===="
export CC=gcc-14 CXX=g++-14
rm -rf build && mkdir build
cmake -B build -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DSUNSHINE_ENABLE_CUDA=OFF \
  -DSUNSHINE_ENABLE_DRM=ON \
  -DSUNSHINE_ENABLE_X11=ON \
  -DSUNSHINE_ENABLE_WAYLAND=ON \
  -DCMAKE_C_FLAGS="-O3 -march=native -mtune=native" \
  -DCMAKE_CXX_FLAGS="-O3 -march=native -mtune=native" \
  -DBUILD_TESTS=OFF

echo "==== [4/5] compile ===="
cmake --build build -- -j"$(nproc)"

echo "==== [5/5] result ===="
ls -lh build/sunshine 2>/dev/null && echo "BUILD OK -> $SRC/build/sunshine"
echo "To install into the isolated prefix: sudo cmake --install build"
