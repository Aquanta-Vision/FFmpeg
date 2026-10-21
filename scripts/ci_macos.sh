#!/usr/bin/env bash
# CI entry point on an arm64 macOS runner: builds both macOS architectures from the extracted
# release source archive, merges them into one universal tree and audits it.
#
# Usage: scripts/ci_macos.sh <source_root> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_root="$1"
out_dir="$2"
work_dir="$(mktemp -d)"

# nasm assembles FFmpeg's x86_64 SIMD code.
brew install --quiet nasm
"$script_dir/build_apple.sh" macos-arm64 "$source_root" "$work_dir/macos-arm64"
"$script_dir/build_apple.sh" macos-x86_64 "$source_root" "$work_dir/macos-x86_64"
"$script_dir/make_macos_universal.sh" "$work_dir/macos-arm64" "$work_dir/macos-x86_64" "$out_dir"
"$script_dir/audit_apple.sh" "$out_dir"
