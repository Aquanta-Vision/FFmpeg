#!/usr/bin/env bash
# Runs the spec's compliance checks against an installed linux platform tree: license and
# codec audit, shared-only output, no executables, and a runtime dependency allowlist.
#
# Usage: scripts/audit_linux.sh <platform_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
platform_dir="$(cd "$1" && pwd)"
failures=0

# FFmpeg's own libraries plus the C runtime; anything else is an unreviewed dependency.
allowed_deps_pattern='^(libav(codec|format|util)|libsw(scale|resample)|libc|libm|libdl|libpthread|librt|ld-linux-x86-64|linux-vdso)\.so'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

runCodecAudit() {
  local audit_bin
  audit_bin="$(mktemp)"
  cc "$script_dir/audit/audit.c" -o "$audit_bin" \
    -I"$platform_dir/include" -L"$platform_dir/lib" -lavcodec -lavutil
  LD_LIBRARY_PATH="$platform_dir/lib" "$audit_bin" || fail "codec audit"
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
  for lib in "$platform_dir"/lib/*.so.*; do
    [ -L "$lib" ] && continue
    for dep in $(readelf -d "$lib" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
      echo "$dep" | grep -qE "$allowed_deps_pattern" || fail "$(basename "$lib") needs $dep"
    done
  done
}

runCodecAudit
checkSharedOnly
checkNoExecutables
checkRuntimeDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
