#!/usr/bin/env bash
# Builds the linux-x86_64 FFmpeg shared libraries from an extracted release source archive.
#
# Usage: scripts/build_linux.sh <source_root> <out_dir>
#   source_root: the extracted pam-ffmpeg-<version> directory (from make_source.sh)
#   out_dir:     where the platform tree (include/, lib/, LICENSE, BUILDINFO.txt) is installed
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_root="$(cd "$1" && pwd)"
out_dir="$(mkdir -p "$2" && cd "$2" && pwd)"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"
# shellcheck source=common_flags.sh
source "$script_dir/common_flags.sh"

ffmpeg_dir="$source_root/ffmpeg-${FFMPEG_VERSION}"
build_dir="$source_root/build-linux-x86_64"
headers_prefix="$source_root/headers-prefix"

# NVENC/NVDEC and AMF are header-only here: FFmpeg dlopens the vendor driver at runtime, so
# nothing extra is linked or shipped.
PLATFORM_CONFIGURE_FLAGS=(
  --enable-ffnvcodec
  --enable-nvenc
  --enable-cuvid
  --enable-amf
  --enable-encoder=h264_nvenc,h264_amf
  --enable-decoder=h264_cuvid
)

installHardwareHeaders() {
  make -C "$source_root/nv-codec-headers" install PREFIX="$headers_prefix" >/dev/null
  mkdir -p "$headers_prefix/include"
  cp -r "$source_root/amf-headers/AMF" "$headers_prefix/include/"
}

configureFfmpeg() {
  mkdir -p "$build_dir"
  cd "$build_dir"
  PKG_CONFIG_PATH="$headers_prefix/lib/pkgconfig" "$ffmpeg_dir/configure" \
    --prefix="$out_dir" \
    --extra-cflags="-I$headers_prefix/include" \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    "${PLATFORM_CONFIGURE_FLAGS[@]}"
}

compileAndInstall() {
  make -C "$build_dir" -j"$(nproc)"
  make -C "$build_dir" install
}

# Static libraries and share/ (examples) are not part of the published tree.
pruneInstall() {
  rm -rf "$out_dir/share" "$out_dir/bin"
  find "$out_dir/lib" -name '*.a' -delete
}

writeLicenseAndBuildInfo() {
  cp "$ffmpeg_dir/COPYING.LGPLv2.1" "$out_dir/LICENSE"
  {
    echo "FFmpeg ${FFMPEG_VERSION} (https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz, sha256 ${FFMPEG_SHA256})"
    echo "nv-codec-headers ${NV_CODEC_HEADERS_TAG}, AMF headers ${AMF_TAG}"
    echo "Platform: linux-x86_64"
    echo "Compiler: $(cc --version | head -1)"
    echo "glibc: $(ldd --version | head -1)"
    echo "Configure: $(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  } > "$out_dir/BUILDINFO.txt"
}

installHardwareHeaders
configureFfmpeg
compileAndInstall
pruneInstall
writeLicenseAndBuildInfo
