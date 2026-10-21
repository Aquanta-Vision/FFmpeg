#!/usr/bin/env bash
# Merges the macos-arm64 and macos-x86_64 trees into one macos-universal tree: each dylib becomes
# a fat binary with both slices, symlinks and headers come from the arm64 tree (the headers are
# architecture independent), and BUILDINFO.txt keeps both builds' details.
#
# Usage: scripts/make_macos_universal.sh <arm64_dir> <x86_64_dir> <out_dir>
set -euo pipefail

arm64_dir="$(cd "$1" && pwd)"
x86_64_dir="$(cd "$2" && pwd)"
out_dir="$3"

copyArm64Tree() {
  rm -rf "$out_dir"
  cp -R "$arm64_dir" "$out_dir"
}

mergeDylibs() {
  local dylib name
  for dylib in "$arm64_dir"/lib/*.dylib; do
    [ -L "$dylib" ] && continue
    name="$(basename "$dylib")"
    lipo -create "$dylib" "$x86_64_dir/lib/$name" -output "$out_dir/lib/$name"
  done
}

mergeBuildInfo() {
  cat "$arm64_dir/BUILDINFO.txt" <(echo) "$x86_64_dir/BUILDINFO.txt" > "$out_dir/BUILDINFO.txt"
}

copyArm64Tree
mergeDylibs
mergeBuildInfo
