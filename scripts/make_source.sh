#!/usr/bin/env bash
# Assembles the release source archive: the pristine upstream FFmpeg tree, the hardware header
# packages it is configured against, and this repo's build scripts. Every platform build starts
# from this archive, so the published source always matches the published binaries.
#
# Usage: scripts/make_source.sh <out_dir>
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
out_dir="$(mkdir -p "$1" && cd "$1" && pwd)"
# shellcheck source=../ffmpeg.env
source "$repo_root/ffmpeg.env"

stage_name="pam-ffmpeg-${FFMPEG_VERSION}"
work_dir="$(mktemp -d)"
stage_dir="$work_dir/$stage_name"

fetchFfmpeg() {
  local tarball="$work_dir/ffmpeg-${FFMPEG_VERSION}.tar.xz"
  curl -sSfL "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz" -o "$tarball"
  echo "${FFMPEG_SHA256}  $tarball" | sha256sum --check --strict
  tar -xJf "$tarball" -C "$stage_dir"
}

fetchNvCodecHeaders() {
  git clone --quiet --depth 1 --branch "$NV_CODEC_HEADERS_TAG" \
    https://github.com/FFmpeg/nv-codec-headers.git "$stage_dir/nv-codec-headers"
  rm -rf "$stage_dir/nv-codec-headers/.git"
}

# Only amf/public/include is needed; the full AMF repo carries large binaries.
fetchAmfHeaders() {
  local clone_dir="$work_dir/amf"
  git clone --quiet --depth 1 --branch "$AMF_TAG" --filter=blob:none --sparse \
    https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "$clone_dir"
  git -C "$clone_dir" sparse-checkout set amf/public/include
  mkdir -p "$stage_dir/amf-headers"
  cp -r "$clone_dir/amf/public/include" "$stage_dir/amf-headers/AMF"
  cp "$clone_dir/LICENSE.txt" "$stage_dir/amf-headers/LICENSE.txt"
}

# Build tool only (GPL, never linked): translates FFmpeg's GNU-syntax ARM assembly for MSVC's
# armasm64, which the Windows arm64 build needs.
fetchGasPreprocessor() {
  mkdir -p "$stage_dir/gas-preprocessor"
  curl -sSfL "https://raw.githubusercontent.com/FFmpeg/gas-preprocessor/${GAS_PREPROCESSOR_COMMIT}/gas-preprocessor.pl" \
    -o "$stage_dir/gas-preprocessor/gas-preprocessor.pl"
  chmod +x "$stage_dir/gas-preprocessor/gas-preprocessor.pl"
}

copyBuildScripts() {
  mkdir -p "$stage_dir/pam-build"
  cp -r "$repo_root/scripts" "$repo_root/ffmpeg.env" "$repo_root/README.md" "$stage_dir/pam-build/"
}

packSource() {
  tar -cJf "$out_dir/${stage_name}-source.tar.xz" -C "$work_dir" "$stage_name"
}

mkdir -p "$stage_dir"
fetchFfmpeg
fetchNvCodecHeaders
fetchAmfHeaders
fetchGasPreprocessor
copyBuildScripts
packSource
rm -rf "$work_dir"
echo "Wrote $out_dir/${stage_name}-source.tar.xz"
