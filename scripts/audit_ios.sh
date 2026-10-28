#!/usr/bin/env bash
# Runs the spec's compliance checks against the iOS xcframework tree. CI cannot execute iOS
# binaries, so the license and codec checks are static (audit_build_config.sh), once per build.
#
# Usage: scripts/audit_ios.sh <platform_dir> <device_build_dir> <simulator_build_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
platform_dir="$(cd "$1" && pwd)"
device_build_dir="$2"
simulator_build_dir="$3"
failures=0

# FFmpeg's own frameworks, plus the OS: system libraries and frameworks.
allowed_deps_pattern='^(@rpath/lib(avcodec|avformat|avutil|swscale|swresample)_pam\.framework/lib[a-z]+_pam|/usr/lib/.*|/System/Library/Frameworks/.*)$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

frameworkBinaries() {
  find "$platform_dir" -path '*.framework/lib*' -type f -not -path '*/Headers/*'
}

checkBuildConfig() {
  local codec_binary="libavcodec_pam.xcframework/ios-arm64/libavcodec_pam.framework/libavcodec_pam"
  "$script_dir/audit_build_config.sh" "$device_build_dir" "$platform_dir/$codec_binary" ||
    fail "device build config audit"
  codec_binary="libavcodec_pam.xcframework/ios-arm64-simulator/libavcodec_pam.framework/libavcodec_pam"
  "$script_dir/audit_build_config.sh" "$simulator_build_dir" "$platform_dir/$codec_binary" ||
    fail "simulator build config audit"
}

# Every framework binary must be a dynamic library; static frameworks or .a files break LGPL.
checkDynamicOnly() {
  local binary
  [ -z "$(find "$platform_dir" -name '*.a')" ] || fail "static .a libraries present"
  for binary in $(frameworkBinaries); do
    file "$binary" | grep -q 'dynamically linked shared library' || fail "not a dylib: $binary"
  done
}

checkNoExecutables() {
  local executables
  executables="$(find "$platform_dir" -type f -exec file {} + | grep 'Mach-O.*executable' || true)"
  [ -z "$executables" ] || fail "executables present: $executables"
}

checkDylibDependencies() {
  local binary dep
  for binary in $(frameworkBinaries); do
    for dep in $(otool -L "$binary" | awk '/^\t/ { print $1 }' | sort -u); do
      echo "$dep" | grep -qE "$allowed_deps_pattern" || fail "$(basename "$binary") needs $dep"
    done
  done
}

checkBuildConfig
checkDynamicOnly
checkNoExecutables
checkDylibDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
