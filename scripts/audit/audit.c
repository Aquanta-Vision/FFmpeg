// Fails (exit 1) if the FFmpeg libraries it is linked against break the PAM licensing rules:
// anything other than LGPL 2.1, a banned configure flag or external library, a software H.264
// codec, or any HEVC codec. Prints every finding, not just the first.
#include <libavcodec/avcodec.h>
#include <libavcodec/codec.h>
#include <stdio.h>
#include <string.h>

static const char* const expected_license = "LGPL version 2.1 or later";

static const char* const banned_configure_terms[] = {
  "--enable-gpl", "--enable-nonfree", "--enable-version3", "libx264",
  "libx265",      "libopenh264",      "libfdk",            "libxvid",
};

// Hardware/platform H.264 codecs; every other H.264 codec is a software implementation.
static const char* const allowed_h264_codecs[] = {
  "h264_nvenc",      "h264_amf",     "h264_qsv",          "h264_mf",
  "h264_mediacodec", "h264_v4l2m2m", "h264_videotoolbox", "h264_cuvid",
  "h264_vaapi",
};

static int contains(const char* const* list, size_t count, const char* name) {
  for (size_t i = 0; i < count; ++i) {
    if (strcmp(list[i], name) == 0) {
      return 1;
    }
  }
  return 0;
}

static int checkLicense(void) {
  const char* license = avcodec_license();
  if (strcmp(license, expected_license) != 0) {
    printf("FAIL license is \"%s\", expected \"%s\"\n", license, expected_license);
    return 1;
  }
  return 0;
}

static int checkConfiguration(void) {
  const char* configuration = avcodec_configuration();
  int failures              = 0;
  size_t count = sizeof(banned_configure_terms) / sizeof(banned_configure_terms[0]);
  for (size_t i = 0; i < count; ++i) {
    if (strstr(configuration, banned_configure_terms[i]) != NULL) {
      printf("FAIL configuration contains %s\n", banned_configure_terms[i]);
      ++failures;
    }
  }
  return failures;
}

static int checkCodec(const AVCodec* codec) {
  size_t allowed_count = sizeof(allowed_h264_codecs) / sizeof(allowed_h264_codecs[0]);
  if (codec->id == AV_CODEC_ID_HEVC) {
    printf("FAIL HEVC codec present: %s\n", codec->name);
    return 1;
  }
  if (codec->id == AV_CODEC_ID_H264 && !contains(allowed_h264_codecs, allowed_count, codec->name)) {
    printf("FAIL software H.264 codec present: %s\n", codec->name);
    return 1;
  }
  return 0;
}

static int checkCodecs(void) {
  void* iterator = NULL;
  int failures   = 0;
  const AVCodec* codec;
  while ((codec = av_codec_iterate(&iterator)) != NULL) {
    printf("  %s %s\n", av_codec_is_encoder(codec) ? "encoder" : "decoder", codec->name);
    failures += checkCodec(codec);
  }
  return failures;
}

int main(void) {
  printf("license: %s\nconfiguration: %s\ncodecs:\n", avcodec_license(), avcodec_configuration());
  int failures = checkLicense() + checkConfiguration() + checkCodecs();
  printf(failures == 0 ? "PASS\n" : "FAILED with %d finding(s)\n", failures);
  return failures == 0 ? 0 : 1;
}
