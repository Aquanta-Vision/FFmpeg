#!/usr/bin/env bash
# Runs the spec's compliance checks against an installed macOS platform tree: license and codec
# audit for every architecture slice, shared-only output, no executables, and a dependency
# allowlist. Runs on an arm64 Mac; x86_64 slices run under Rosetta.
#
# Usage: scripts/audit_apple.sh <platform_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
platform_dir="$(cd "$1" && pwd)"
failures=0

# FFmpeg's own dylibs by install name, plus the OS: system libraries and frameworks.
allowed_deps_pattern='^(@rpath/lib(avcodec|avformat|avutil|swscale|swresample)_pam\.[0-9]+\.dylib|/usr/lib/.*|/System/Library/Frameworks/.*)$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

runCodecAudit() {
  local arch audit_bin
  for arch in $(lipo -archs "$platform_dir/lib/libavcodec_pam.dylib"); do
    audit_bin="$(mktemp)"
    echo "== $arch"
    clang -arch "$arch" "$script_dir/audit/audit.c" -o "$audit_bin" \
      -I"$platform_dir/include" -L"$platform_dir/lib" -Wl,-rpath,"$platform_dir/lib" -lavcodec_pam -lavutil_pam
    arch "-$arch" "$audit_bin" || fail "codec audit ($arch)"
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

# otool -L prints the library's own install name first, then its dependencies, per slice.
checkDylibDependencies() {
  local dylib dep
  for dylib in "$platform_dir"/lib/*.dylib; do
    [ -L "$dylib" ] && continue
    for dep in $(otool -L "$dylib" | awk '/^\t/ { print $1 }' | sort -u); do
      echo "$dep" | grep -qE "$allowed_deps_pattern" || fail "$(basename "$dylib") needs $dep"
    done
  done
}

runCodecAudit
checkSharedOnly
checkNoExecutables
checkDylibDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
