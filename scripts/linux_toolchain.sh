# Selects the compiler, readelf and binary runner for a linux target. Sourced by build_linux.sh
# and audit_linux.sh so the build and the audit use the same toolchain.
#
# x86_64 and aarch64 build natively, so the target must match the machine. cortexa9t2hf
# cross-compiles with the Poky 3.3 SDK in the FLIR toolchain image and runs target binaries
# under qemu-arm.

poky_env=/opt/poky/3.3-cortexa9t2hf/environment-setup-cortexa9t2hf-neon-oe-linux-gnueabi
poky_cross_prefix=arm-oe-linux-gnueabi-

requireNativeMachine() {
  [ "$(uname -m)" = "$1" ] || {
    echo "Target $1 builds natively, but this machine is $(uname -m)" >&2
    exit 1
  }
}

# The SDK script reads LD_LIBRARY_PATH before setting it, so nounset is off while sourcing.
loadPokySdk() {
  set +u
  # shellcheck disable=SC1090
  source "$poky_env"
  set -u
}

# Sets TARGET_CC, TARGET_READELF and TARGET_RUNNER (the command prefix that runs a target binary).
loadLinuxToolchain() {
  case "$1" in
    x86_64 | aarch64)
      requireNativeMachine "$1"
      TARGET_CC=cc
      TARGET_READELF=readelf
      TARGET_RUNNER=(env)
      ;;
    cortexa9t2hf)
      loadPokySdk
      TARGET_CC="$CC"
      TARGET_READELF="${poky_cross_prefix}readelf"
      TARGET_RUNNER=(qemu-arm -L "$SDKTARGETSYSROOT")
      ;;
    *)
      echo "Unsupported linux target: $1" >&2
      exit 1
      ;;
  esac
}

# Reads the glibc version from the target's headers, which also works for a cross sysroot.
targetGlibcVersion() {
  printf '#include <features.h>\n__GLIBC__.__GLIBC_MINOR__\n' | $TARGET_CC -E -P - | tail -1 | tr -d ' '
}
