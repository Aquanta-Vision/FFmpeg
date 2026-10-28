#!/usr/bin/env bash
# The license and codec half of the spec's audit, for platforms whose binaries CI cannot execute
# (Android, iOS). Instead of running audit.c it reads the same facts statically: the license and
# configure strings configure generated (and libavcodec carries), and the codec registry that
# av_codec_iterate() walks.
#
# Usage: scripts/audit_build_config.sh <build_dir> <libavcodec_binary>
#   build_dir: the FFmpeg build directory the binary was built in
set -euo pipefail

build_dir="$(cd "$1" && pwd)"
libavcodec="$2"
failures=0

expected_license='LGPL version 2.1 or later'
banned_configure_pattern='--enable-gpl|--enable-nonfree|--enable-version3|libx264|libx265|libopenh264|libfdk|libxvid'
# Same lists as audit.c.
allowed_h264_pattern='^h264_(nvenc|amf|qsv|mf|mediacodec|v4l2m2m|videotoolbox|cuvid|vaapi)$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

checkLicense() {
  local license
  license="$(sed -n 's/^#define FFMPEG_LICENSE "\(.*\)"$/\1/p' "$build_dir/config.h")"
  echo "license: $license"
  [ "$license" = "$expected_license" ] || fail "license is \"$license\""
  grep -aqF "$expected_license" "$libavcodec" || fail "$(basename "$libavcodec") lacks the license string"
}

checkConfiguration() {
  local configuration
  configuration="$(sed -n 's/^#define FFMPEG_CONFIGURATION //p' "$build_dir/config.h")"
  echo "configuration: $configuration"
  ! echo "$configuration" | grep -qE -- "$banned_configure_pattern" || fail "configuration contains a banned term"
}

# codec_list.c has one ff_<name>_<encoder|decoder> entry per registered codec.
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

checkLicense
checkConfiguration
checkCodecs

[ "$failures" -eq 0 ] || {
  echo "Build config audit FAILED with $failures finding(s)"
  exit 1
}
