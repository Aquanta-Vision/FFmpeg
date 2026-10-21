# NVIDIA (NVENC/NVDEC) and AMD (AMF) H.264 codecs for x86_64 Linux and Windows x64. Sourced by
# the build scripts.
#
# Both are header-only: FFmpeg loads the vendor driver at runtime, so nothing extra is linked
# or shipped. --disable-autodetect turns them off, hence the explicit enables.

# shellcheck disable=SC2034
GPU_VENDOR_CONFIGURE_FLAGS=(
  --enable-ffnvcodec
  --enable-nvenc
  --enable-cuvid
  --enable-amf
  --enable-encoder=h264_nvenc,h264_amf
  --enable-decoder=h264_cuvid
)

# Installs the headers into <prefix>/include and the ffnvcodec pkg-config file into
# <prefix>/lib/pkgconfig, where configure looks for them.
installGpuVendorHeaders() {
  local source_root="$1" prefix="$2"
  make -C "$source_root/nv-codec-headers" install PREFIX="$prefix" >/dev/null
  mkdir -p "$prefix/include"
  cp -r "$source_root/amf-headers/AMF" "$prefix/include/"
}
