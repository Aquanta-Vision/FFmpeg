#!/usr/bin/env bash
# Builds the linux-<target> FFmpeg shared libraries from an extracted release source archive.
#
# Usage: scripts/build_linux.sh <target> <source_root> <out_dir>
#   target:      x86_64 or aarch64 (native build), or cortexa9t2hf (Poky SDK cross build)
#   source_root: the extracted pam-ffmpeg-<version> directory (from make_source.sh)
#   out_dir:     where the platform tree (include/, lib/, LICENSE, BUILDINFO.txt) is installed
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$1"
source_root="$(cd "$2" && pwd)"
out_dir="$(mkdir -p "$3" && cd "$3" && pwd)"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"
# shellcheck source=common_flags.sh
source "$script_dir/common_flags.sh"
# shellcheck source=gpu_vendor.sh
source "$script_dir/gpu_vendor.sh"
# shellcheck source=linux_toolchain.sh
source "$script_dir/linux_toolchain.sh"

platform="linux-$target"
ffmpeg_dir="$source_root/ffmpeg-${FFMPEG_VERSION}"
build_dir="$source_root/build-$platform"
headers_prefix="$source_root/headers-prefix"

# x86_64: NVIDIA and AMD GPU codecs (gpu_vendor.sh).
# aarch64 and cortexa9t2hf: the SoC's hardware codec through V4L2 M2M, using only the kernel
# uapi headers.
selectPlatformFlags() {
  local v4l2_m2m_flags=(
    --enable-v4l2-m2m
    --enable-encoder=h264_v4l2m2m
    --enable-decoder=h264_v4l2m2m
  )
  case "$target" in
    x86_64)
      PLATFORM_CONFIGURE_FLAGS=("${GPU_VENDOR_CONFIGURE_FLAGS[@]}")
      ;;
    aarch64)
      PLATFORM_CONFIGURE_FLAGS=("${v4l2_m2m_flags[@]}")
      ;;
    cortexa9t2hf)
      PLATFORM_CONFIGURE_FLAGS=(
        "${v4l2_m2m_flags[@]}"
        --enable-cross-compile
        --cross-prefix="$poky_cross_prefix"
        --sysroot="$SDKTARGETSYSROOT"
        --target-os=linux
        --arch=arm
        --cpu=cortex-a9
        --enable-neon
        --enable-thumb
        --extra-cflags="-mthumb -mfpu=neon -mfloat-abi=hard"
        --extra-ldflags="-mthumb -mfpu=neon -mfloat-abi=hard"
      )
      ;;
  esac
}

installHardwareHeaders() {
  [ "$target" = x86_64 ] || return 0
  installGpuVendorHeaders "$source_root" "$headers_prefix"
}

# configure only prints a one-line reason; the failing check is at the end of config.log.
configureFfmpeg() {
  mkdir -p "$build_dir"
  cd "$build_dir"
  PKG_CONFIG_PATH="$headers_prefix/lib/pkgconfig" "$ffmpeg_dir/configure" \
    --prefix="$out_dir" \
    --extra-cflags="-I$headers_prefix/include" \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    "${PLATFORM_CONFIGURE_FLAGS[@]}" || {
    tail -n 40 "$build_dir/ffbuild/config.log"
    exit 1
  }
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
    [ "$target" != x86_64 ] || echo "nv-codec-headers ${NV_CODEC_HEADERS_TAG}, AMF headers ${AMF_TAG}"
    echo "Platform: $platform"
    echo "Compiler: $($TARGET_CC --version | head -1)"
    echo "glibc: $(targetGlibcVersion)"
    echo "Configure: $(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  } > "$out_dir/BUILDINFO.txt"
}

loadLinuxToolchain "$target"
selectPlatformFlags
installHardwareHeaders
configureFfmpeg
compileAndInstall
pruneInstall
writeLicenseAndBuildInfo
