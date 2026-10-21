# Configure flags shared by every platform. Sourced by the per-platform build scripts.
#
# --disable-autodetect is the important one: without it, configure links any library it finds
# on the build machine, which is how x264 and OpenH264 end up in builds nobody asked for.
# --enable-gpl, --enable-nonfree and --enable-version3 are never passed (LGPL 2.1 only).
#
# There is no software H.264 or HEVC decoder or encoder: H.264 goes through platform and
# hardware codecs only, and HEVC is not used.

# shellcheck disable=SC2034
COMMON_CONFIGURE_FLAGS=(
  --disable-everything
  --disable-autodetect
  --enable-shared
  --disable-static
  --enable-pic
  --disable-programs
  --disable-doc
  --disable-avdevice
  --disable-avfilter
  --disable-postproc

  --enable-encoder=mpeg4,ffv1,rawvideo
  --enable-decoder=mpeg4,ffv1,rawvideo

  --enable-muxer=mp4,mov,matroska,mpegts,avi,rtsp,rtp,h264,m4v
  --enable-demuxer=mov,matroska,mpegts,avi,rtsp,rtp,sdp,h264,m4v
  --enable-protocol=file,tcp,udp,rtp

  --enable-parser=h264,mpeg4video
  --enable-bsf=h264_mp4toannexb,extract_extradata,dump_extradata
)
