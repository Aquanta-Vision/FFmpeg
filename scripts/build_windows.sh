#!/usr/bin/env bash
# Builds the windows-<target> FFmpeg DLLs and import libraries with MSVC from an extracted
# release source archive. Runs in MSYS2 bash with the Visual Studio developer environment for
# the target already loaded (msvc_env.ps1), so cl.exe is on PATH.
#
# Usage: scripts/build_windows.sh <target> <source_root> <out_dir>
#   target:      x64 (native) or arm64 (cross-compiled from x64)
#   source_root: the extracted pam-ffmpeg-<version> directory (from make_source.sh)
#   out_dir:     where the platform tree (include/, bin/*.dll, lib/*.lib, LICENSE, BUILDINFO.txt)
#                is installed
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

platform="windows-$target"
ffmpeg_dir="$source_root/ffmpeg-${FFMPEG_VERSION}"
build_dir="$source_root/build-$platform"
headers_prefix="$source_root/headers-prefix"

# Media Foundation's H.264 encoder ships with Windows on both architectures. NVIDIA and AMD GPU
# codecs only exist for x64.
selectPlatformFlags() {
  local windows_flags=(
    --toolchain=msvc
    --enable-mediafoundation
    --enable-encoder=h264_mf
  )
  case "$target" in
    x64)
      PLATFORM_CONFIGURE_FLAGS=(
        "${windows_flags[@]}"
        --arch=x86_64
        "${GPU_VENDOR_CONFIGURE_FLAGS[@]}"
      )
      ;;
    arm64)
      PLATFORM_CONFIGURE_FLAGS=(
        "${windows_flags[@]}"
        --arch=aarch64
        --target-os=win32
        --enable-cross-compile
      )
      ;;
    *)
      echo "Unsupported windows target: $target" >&2
      exit 1
      ;;
  esac
}

installHardwareHeaders() {
  [ "$target" = x64 ] || return 0
  installGpuVendorHeaders "$source_root" "$headers_prefix"
}

# configure wraps armasm64 with gas-preprocessor.pl, which it finds on PATH.
addGasPreprocessorToPath() {
  [ "$target" = arm64 ] || return 0
  export PATH="$source_root/gas-preprocessor:$PATH"
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

# FFmpeg installs the import libraries next to the DLLs in bin/; lib/ is where linkers and PAM
# look for them. The .def files and share/ (examples) are not part of the published tree.
arrangeInstall() {
  mv "$out_dir"/bin/*.lib "$out_dir/lib/"
  rm -rf "$out_dir/share" "$out_dir"/lib/*.def
}

writeLicenseAndBuildInfo() {
  cp "$ffmpeg_dir/COPYING.LGPLv2.1" "$out_dir/LICENSE"
  {
    echo "FFmpeg ${FFMPEG_VERSION} (https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz, sha256 ${FFMPEG_SHA256})"
    [ "$target" != x64 ] || echo "nv-codec-headers ${NV_CODEC_HEADERS_TAG}, AMF headers ${AMF_TAG}"
    [ "$target" != arm64 ] || echo "gas-preprocessor ${GAS_PREPROCESSOR_COMMIT}"
    echo "Platform: $platform"
    echo "Compiler: $(cl.exe 2>&1 | head -1)"
    echo "Windows SDK: ${WindowsSDKVersion:-unknown}"
    echo "Configure: $(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  } > "$out_dir/BUILDINFO.txt"
}

selectPlatformFlags
installHardwareHeaders
addGasPreprocessorToPath
configureFfmpeg
compileAndInstall
arrangeInstall
writeLicenseAndBuildInfo
