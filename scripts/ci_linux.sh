#!/usr/bin/env bash
# CI entry point inside a linux build container: installs the build tools, then builds and
# audits one target from the extracted release source archive. Runs as root.
#
# Usage: scripts/ci_linux.sh <target> <source_root> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$1"
source_root="$2"
out_dir="$3"

# The FLIR Poky image points apt at an internal mirror that CI cannot reach.
usePublicUbuntuMirror() {
  local codename
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  printf 'deb http://archive.ubuntu.com/ubuntu %s main universe\n' \
    "$codename" "$codename-updates" "$codename-security" > /etc/apt/sources.list
}

# Cross builds still need a host compiler for configure, and qemu-user runs the cross-built
# audit program.
installBuildTools() {
  local packages
  case "$target" in
    x86_64) packages=(build-essential nasm pkg-config libva-dev) ;;
    aarch64) packages=(build-essential pkg-config) ;;
    cortexa9t2hf)
      usePublicUbuntuMirror
      packages=(build-essential pkg-config qemu-user)
      ;;
  esac
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq --no-install-recommends "${packages[@]}"
}

installBuildTools
"$script_dir/build_linux.sh" "$target" "$source_root" "$out_dir"
"$script_dir/audit_linux.sh" "$target" "$out_dir"
