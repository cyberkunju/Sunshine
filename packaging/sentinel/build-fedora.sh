#!/usr/bin/env bash
# Reproducible build of the Sentinel "ultimate" Sunshine fork for the exact target box:
# Fedora 43, EC2 m7i.xlarge (4 vCPU Sapphire Rapids, NO GPU). Software x264 path only.
#
# PROVEN recipe (verified on the box):
# - system gcc (gcc15 on F43; gcc14 is NOT packaged on F43)
# - -march=native to exploit Sapphire Rapids / AVX-512 in Sunshine's own C++
#   (x264 itself runtime-dispatches its AVX-512 asm regardless)
# - CUDA/NVENC disabled (no GPU)
# - builds FFmpeg + x264 + x265 + SVT-AV1 from the build-deps submodules, then Sunshine
# - installs to /opt/sunshine-ultimate so the stock /usr/bin/sunshine stays as rollback
set -euo pipefail
SRC="${SRC:-$HOME/sunshine-src}"
PREFIX="${PREFIX:-/opt/sunshine-ultimate}"
cd "$SRC"

echo "==== [1/6] build dependencies ===="
sudo dnf install -y \
  cmake ninja-build git wget which desktop-file-utils rpm-build systemd-rpm-macros \
  gcc gcc-c++ libatomic libstdc++-static glibc-static libxcrypt-static \
  nasm yasm meson \
  boost-devel \
  openssl-devel libcurl-devel libcap-devel libdrm-devel libevdev-devel \
  libnotify-devel libva-devel numactl-devel opus-devel miniupnpc-devel \
  pulseaudio-libs-devel pipewire-devel \
  libX11-devel libxcb-devel libXcursor-devel libXfixes-devel libXi-devel \
  libXinerama-devel libXrandr-devel libXtst-devel \
  mesa-libGL-devel mesa-libgbm-devel \
  libayatana-appindicator3-devel libgudev \
  vulkan-loader-devel vulkan-headers glslc glslang \
  doxygen graphviz \
  nodejs-npm python3-jinja2 python3-setuptools \
  appstream libappstream-glib xorg-x11-server-Xvfb

echo "==== [2/6] submodules (incl. build-deps FFmpeg/x264/x265/SVT-AV1) ===="
git submodule update --init --recursive

echo "==== [3/6] configure (system gcc, -march=native, no CUDA) ===="
export CC=gcc CXX=g++
rm -rf build && mkdir build
cmake -B build -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DSUNSHINE_ENABLE_CUDA=OFF \
  -DSUNSHINE_ENABLE_DRM=ON -DSUNSHINE_ENABLE_X11=ON -DSUNSHINE_ENABLE_WAYLAND=ON \
  -DCMAKE_C_FLAGS="-O3 -march=native -mtune=native" \
  -DCMAKE_CXX_FLAGS="-O3 -march=native -mtune=native -Wno-error" \
  -DBUILD_TESTS=OFF -Wno-dev

echo "==== [4/6] compile ===="
cmake --build build -- -j"$(nproc)"

echo "==== [5/6] install to $PREFIX + capabilities ===="
sudo cmake --install build
sudo setcap cap_sys_admin,cap_sys_nice+p "$PREFIX/bin/sunshine"
getcap "$PREFIX/bin/sunshine"

echo "==== [6/6] switch the service (reversible drop-in) ===="
sudo tee /etc/systemd/system/sunshine.service.d/20-ultimate.conf >/dev/null <<EOF
[Service]
ExecStart=
ExecStart=$PREFIX/bin/sunshine
EOF
sudo systemctl daemon-reload
sudo systemctl restart sunshine
echo "OK. Rollback: sudo rm /etc/systemd/system/sunshine.service.d/20-ultimate.conf && sudo systemctl daemon-reload && sudo systemctl restart sunshine"
