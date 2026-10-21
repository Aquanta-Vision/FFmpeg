#!/usr/bin/env bash
# Builds the android-<abi> FFmpeg shared libraries with the NDK from an extracted release source
# archive.
#
# Usage: scripts/build_android.sh <abi> <source_root> <out_dir>
#   abi:         arm64-v8a, armeabi-v7a, x86 or x86_64
#   source_root: the extracted pam-ffmpeg-<version> directory (from make_source.sh)
#   out_dir:     where the platform tree (include/, lib/, LICENSE, BUILDINFO.txt) is installed
# Needs ANDROID_NDK_HOME pointing at the NDK from ffmpeg.env.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
abi="$1"
source_root="$(cd "$2" && pwd)"
out_dir="$(mkdir -p "$3" && cd "$3" && pwd)"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"
# shellcheck source=common_flags.sh
source "$script_dir/common_flags.sh"

platform="android-$abi"
ffmpeg_dir="$source_root/ffmpeg-${FFMPEG_VERSION}"
build_dir="$source_root/build-$platform"
toolchain="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"

# Each ABI's clang is named by target triple and API level.
selectAbiFlags() {
  local triple
  case "$abi" in
    arm64-v8a)
      triple=aarch64-linux-android
      ABI_CONFIGURE_FLAGS=(--arch=aarch64)
      ;;
    armeabi-v7a)
      triple=armv7a-linux-androideabi
      ABI_CONFIGURE_FLAGS=(--arch=arm --cpu=armv7-a --enable-neon --enable-thumb)
      ;;
    # 32-bit x86 assembly needs text relocations, which Android refuses to load.
    x86)
      triple=i686-linux-android
      ABI_CONFIGURE_FLAGS=(--arch=x86 --disable-asm)
      ;;
    x86_64)
      triple=x86_64-linux-android
      ABI_CONFIGURE_FLAGS=(--arch=x86_64)
      ;;
    *)
      echo "Unsupported android ABI: $abi" >&2
      exit 1
      ;;
  esac
  CLANG="$toolchain/bin/${triple}${ANDROID_API}-clang"
}

# MediaCodec is the platform H.264 encoder and decoder; FFmpeg reaches it through JNI and the
# NDK media library, both part of Android.
configureFfmpeg() {
  mkdir -p "$build_dir"
  cd "$build_dir"
  "$ffmpeg_dir/configure" \
    --prefix="$out_dir" \
    "${COMMON_CONFIGURE_FLAGS[@]}" \
    --enable-cross-compile \
    --target-os=android \
    --sysroot="$toolchain/sysroot" \
    --cc="$CLANG" \
    --cxx="$CLANG++" \
    --ar="$toolchain/bin/llvm-ar" \
    --nm="$toolchain/bin/llvm-nm" \
    --ranlib="$toolchain/bin/llvm-ranlib" \
    --strip="$toolchain/bin/llvm-strip" \
    "${ABI_CONFIGURE_FLAGS[@]}" \
    --enable-jni \
    --enable-mediacodec \
    --enable-encoder=h264_mediacodec \
    --enable-decoder=h264_mediacodec || {
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
    echo "Platform: $platform"
    echo "NDK: ${ANDROID_NDK_VERSION} ($(sed -n 's/^Pkg.Revision = //p' "$ANDROID_NDK_HOME/source.properties")), API ${ANDROID_API}"
    echo "Compiler: $("$CLANG" --version | head -1)"
    echo "Configure: $(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  } > "$out_dir/BUILDINFO.txt"
}

selectAbiFlags
configureFfmpeg
compileAndInstall
pruneInstall
writeLicenseAndBuildInfo
