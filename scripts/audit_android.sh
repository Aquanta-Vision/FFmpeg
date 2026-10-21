#!/usr/bin/env bash
# Runs the spec's compliance checks against an android platform tree. CI cannot execute Android
# binaries, so the license and codec checks are static (audit_build_config.sh).
#
# Usage: scripts/audit_android.sh <platform_dir> <build_dir>
#   build_dir: the FFmpeg build directory the platform tree was installed from
# Needs ANDROID_NDK_HOME for llvm-readelf.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
platform_dir="$(cd "$1" && pwd)"
build_dir="$2"
readelf="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
failures=0

# FFmpeg's own libraries plus Android's C runtime, JNI/NDK media and logging libraries.
allowed_deps_pattern='^(libav(codec|format|util)|libsw(scale|resample)|libc|libm|libdl|liblog|libandroid|libmediandk)\.so$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

checkBuildConfig() {
  "$script_dir/audit_build_config.sh" "$build_dir" "$platform_dir/lib/libavcodec.so" || fail "build config audit"
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

checkBuildConfig
checkSharedOnly
checkNoExecutables
checkRuntimeDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
