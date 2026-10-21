#!/usr/bin/env bash
# Builds FFmpeg dylibs for one Apple target with Xcode's clang from an extracted release source
# archive. Install names are @rpath/<lib>, so the app or framework decides where they live.
#
# Usage: scripts/build_apple.sh <target> <source_root> <out_dir>
#   target:      macos-arm64, macos-x86_64, ios-arm64 or ios-simulator-arm64
#   source_root: the extracted pam-ffmpeg-<version> directory (from make_source.sh)
#   out_dir:     where the target tree (include/, lib/, LICENSE, BUILDINFO.txt) is installed
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$1"
source_root="$(cd "$2" && pwd)"
out_dir="$(mkdir -p "$3" && cd "$3" && pwd)"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"
# shellcheck source=common_flags.sh
source "$script_dir/common_flags.sh"

ffmpeg_dir="$source_root/ffmpeg-${FFMPEG_VERSION}"
build_dir="$source_root/build-$target"

# Sets the SDK, clang -arch, FFmpeg --arch and the minimum OS flag for the target.
selectTarget() {
  case "$target" in
    macos-arm64) sdk=macosx arch=arm64 ffmpeg_arch=aarch64 min_os="-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" ;;
    macos-x86_64) sdk=macosx arch=x86_64 ffmpeg_arch=x86_64 min_os="-mmacosx-version-min=$MACOS_DEPLOYMENT_TARGET" ;;
    ios-arm64) sdk=iphoneos arch=arm64 ffmpeg_arch=aarch64 min_os="-miphoneos-version-min=$IOS_DEPLOYMENT_TARGET" ;;
    ios-simulator-arm64) sdk=iphonesimulator arch=arm64 ffmpeg_arch=aarch64 min_os="-mios-simulator-version-min=$IOS_DEPLOYMENT_TARGET" ;;
    *)
      echo "Unsupported apple target: $target" >&2
      exit 1
      ;;
  esac
  sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
}

# Every target is configured as a cross build so the same flags work for x86_64 on an arm64
# runner and for iOS. VideoToolbox is the platform H.264 encoder.
configureFfmpeg() {
  local target_flags="-arch $arch -isysroot $sdk_path $min_os"
  mkdir -p "$build_dir"
  cd "$build_dir"
  "$ffmpeg_dir/configure" \
    --prefix="$out_dir" \
    --install-name-dir=@rpath \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    --enable-cross-compile \
    --target-os=darwin \
    --arch="$ffmpeg_arch" \
    --cc="$(xcrun --sdk "$sdk" -f clang)" \
    --extra-cflags="$target_flags" \
    --extra-ldflags="$target_flags" \
    --enable-videotoolbox \
    --enable-encoder=h264_videotoolbox || {
    tail -n 40 "$build_dir/ffbuild/config.log"
    exit 1
  }
}

compileAndInstall() {
  make -C "$build_dir" -j"$(sysctl -n hw.ncpu)"
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
    echo "Platform: $target"
    echo "Compiler: $(xcrun --sdk "$sdk" clang --version | head -1)"
    echo "SDK: $sdk $(xcrun --sdk "$sdk" --show-sdk-version), minimum OS flag $min_os"
    echo "Configure: $(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  } > "$out_dir/BUILDINFO.txt"
}

selectTarget
configureFfmpeg
compileAndInstall
pruneInstall
writeLicenseAndBuildInfo
