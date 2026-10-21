#!/usr/bin/env bash
# CI entry point on a macOS runner: builds the iOS device and simulator slices from the
# extracted release source archive, wraps them into dynamic xcframeworks and audits them.
#
# Usage: scripts/ci_ios.sh <source_root> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
source_root="$1"
out_dir="$2"
work_dir="$(mktemp -d)"

"$script_dir/build_apple.sh" ios-arm64 "$source_root" "$work_dir/ios-arm64"
"$script_dir/build_apple.sh" ios-simulator-arm64 "$source_root" "$work_dir/ios-simulator-arm64"
"$script_dir/make_ios_xcframeworks.sh" "$work_dir/ios-arm64" "$work_dir/ios-simulator-arm64" "$out_dir"
"$script_dir/audit_ios.sh" "$out_dir" "$source_root/build-ios-arm64" "$source_root/build-ios-simulator-arm64"
