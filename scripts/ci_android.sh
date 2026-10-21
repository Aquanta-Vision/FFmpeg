#!/usr/bin/env bash
# CI entry point on an ubuntu runner: fetches the pinned NDK, then builds and audits one android
# ABI from the extracted release source archive.
#
# Usage: scripts/ci_android.sh <abi> <source_root> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
abi="$1"
source_root="$2"
out_dir="$3"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"

# The runner image's NDKs change over time; the pinned one keeps builds reproducible.
fetchNdk() {
  local work_dir
  work_dir="$(mktemp -d)"
  curl -sSfL "https://dl.google.com/android/repository/android-ndk-${ANDROID_NDK_VERSION}-linux.zip" \
    -o "$work_dir/ndk.zip"
  echo "${ANDROID_NDK_SHA256}  $work_dir/ndk.zip" | sha256sum --check --strict
  unzip -q "$work_dir/ndk.zip" -d "$work_dir"
  export ANDROID_NDK_HOME="$work_dir/android-ndk-${ANDROID_NDK_VERSION}"
}

fetchNdk
"$script_dir/build_android.sh" "$abi" "$source_root" "$out_dir"
"$script_dir/audit_android.sh" "$out_dir" "$source_root/build-android-$abi"
