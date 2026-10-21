#!/usr/bin/env bash
# Runs the spec's compliance checks against an android platform tree. CI cannot execute Android
# binaries, so instead of running audit.c this reads the same facts statically: the license and
# configure strings compiled into libavcodec.so, and the codec registry configure generated.
#
# Usage: scripts/audit_android.sh <platform_dir> <build_dir>
#   build_dir: the FFmpeg build directory the platform tree was installed from
# Needs ANDROID_NDK_HOME for llvm-readelf.
set -euo pipefail

platform_dir="$(cd "$1" && pwd)"
build_dir="$(cd "$2" && pwd)"
readelf="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
failures=0

expected_license='LGPL version 2.1 or later'
banned_configure_pattern='--enable-gpl|--enable-nonfree|--enable-version3|libx264|libx265|libopenh264|libfdk|libxvid'
# Same lists as audit.c.
allowed_h264_pattern='^h264_(nvenc|amf|qsv|mf|mediacodec|v4l2m2m|videotoolbox|cuvid)$'

# FFmpeg's own libraries plus Android's C runtime, JNI/NDK media and logging libraries.
allowed_deps_pattern='^(libav(codec|format|util)|libsw(scale|resample)|libc|libm|libdl|liblog|libandroid|libmediandk)\.so$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

checkLicense() {
  local license
  license="$(sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"$/\1/p' "$build_dir/config.h")"
  echo "license: $license"
  [ "$license" = "$expected_license" ] || fail "license is \"$license\""
  grep -aqF "$expected_license" "$platform_dir/lib/libavcodec.so" || fail "libavcodec.so lacks the license string"
}

checkConfiguration() {
  local configuration
  configuration="$(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  echo "configuration: $configuration"
  ! echo "$configuration" | grep -qE -- "$banned_configure_pattern" || fail "configuration contains a banned term"
}

# codec_list.c is the registry av_codec_iterate() walks, one ff_<name>_<encoder|decoder> per codec.
checkCodecs() {
  local entry name
  echo "codecs:"
  for entry in $(sed -n 's/.*&ff_\(.*\),$/\1/p' "$build_dir/libavcodec/codec_list.c"); do
    name="${entry%_*}"
    echo "  ${entry##*_} $name"
    case "$name" in
      hevc* | *_hevc* | h265*) fail "HEVC codec present: $name" ;;
      h264* | libx264* | libopenh264*)
        echo "$name" | grep -qE "$allowed_h264_pattern" || fail "software H.264 codec present: $name"
        ;;
    esac
  done
}

checkSharedOnly() {
  local static_libs
  static_libs="$(find "$platform_dir" -name '*.a')"
  [ -z "$static_libs" ] || fail "static libraries present: $static_libs"
}

checkNoExecutables() {
  [ ! -d "$platform_dir/bin" ] || fail "bin/ present: $(ls "$platform_dir/bin")"
}

checkRuntimeDependencies() {
  local lib dep
  for lib in "$platform_dir"/lib/*.so; do
    for dep in $("$readelf" -d "$lib" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      echo "$dep" | grep -qE "$allowed_deps_pattern" || fail "$(basename "$lib") needs $dep"
    done
  done
}

checkLicense
checkConfiguration
checkCodecs
checkSharedOnly
checkNoExecutables
checkRuntimeDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
