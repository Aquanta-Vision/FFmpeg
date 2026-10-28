#!/usr/bin/env bash
# Wraps the ios-arm64 and ios-simulator-arm64 trees into one dynamic .xcframework per FFmpeg
# library (libavcodec_pam.xcframework, ...). Dynamic frameworks keep FFmpeg a separate, replaceable
# library inside the app, which LGPL requires; the old static .a builds did not.
#
# Usage: scripts/make_ios_xcframeworks.sh <device_dir> <simulator_dir> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
device_dir="$(cd "$1" && pwd)"
simulator_dir="$(cd "$2" && pwd)"
out_dir="$(mkdir -p "$3" && cd "$3" && pwd)"
# shellcheck source=../ffmpeg.env
source "$script_dir/../ffmpeg.env"
work_dir="$(mktemp -d)"
libraries=(libavutil libswresample libswscale libavcodec libavformat)
# Matches --build-suffix in common_flags.sh; header directories keep the plain names.
library_suffix=_pam

writeInfoPlist() {
  local name="$1" version="$2" platform="$3" plist="$4"
  cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$name</string>
  <key>CFBundleIdentifier</key><string>com.aquantavision.ffmpeg.${name//_/-}</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$IOS_DEPLOYMENT_TARGET</string>
</dict>
</plist>
EOF
}

# Points the binary's own install name and its references to the other FFmpeg dylibs at the
# framework paths, then re-signs ad hoc because install_name_tool invalidates the signature.
relinkAsFramework() {
  local binary="$1" name="$2" dep dep_name
  install_name_tool -id "@rpath/$name.framework/$name" "$binary"
  for dep in $(otool -L "$binary" | awk '/^\t@rpath\/lib.*\.dylib/ { print $1 }'); do
    dep_name="$(basename "$dep" | cut -d. -f1)"
    [ "$dep_name" = "$name" ] || install_name_tool -change "$dep" "@rpath/$dep_name.framework/$dep_name" "$binary"
  done
  codesign --force --sign - "$binary"
}

# <tree>/lib/libavcodec_pam.dylib is a symlink to libavcodec_pam.<major>.<minor>.<micro>.dylib.
makeFramework() {
  local tree="$1" library="$2" platform="$3" framework_dir="$4"
  local name="$library$library_suffix"
  local dylib version
  dylib="$(cd "$tree/lib" && realpath "$name.dylib")"
  version="$(basename "$dylib" .dylib | cut -d. -f2-)"
  mkdir -p "$framework_dir/Headers"
  cp "$dylib" "$framework_dir/$name"
  cp -R "$tree/include/$library/" "$framework_dir/Headers/"
  writeInfoPlist "$name" "$version" "$platform" "$framework_dir/Info.plist"
  relinkAsFramework "$framework_dir/$name" "$name"
}

makeXcframeworks() {
  local library name
  for library in "${libraries[@]}"; do
    name="$library$library_suffix"
    makeFramework "$device_dir" "$library" iPhoneOS "$work_dir/device/$name.framework"
    makeFramework "$simulator_dir" "$library" iPhoneSimulator "$work_dir/simulator/$name.framework"
    xcodebuild -create-xcframework \
      -framework "$work_dir/device/$name.framework" \
      -framework "$work_dir/simulator/$name.framework" \
      -output "$out_dir/$name.xcframework"
  done
}

writeLicenseAndBuildInfo() {
  cp "$device_dir/LICENSE" "$out_dir/LICENSE"
  cat "$device_dir/BUILDINFO.txt" <(echo) "$simulator_dir/BUILDINFO.txt" > "$out_dir/BUILDINFO.txt"
}

makeXcframeworks
writeLicenseAndBuildInfo
rm -rf "$work_dir"
