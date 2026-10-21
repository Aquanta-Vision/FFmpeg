# FFmpeg for PAM

LGPL 2.1 FFmpeg shared libraries for every platform PAM ships on, built from source in CI and
published as GitHub Releases. PAM pins one release by URL and SHA256.

Each release contains a `pam-ffmpeg-<version>-<platform>.tar.xz` per platform (headers, shared
libraries, `LICENSE`, `BUILDINFO.txt` with the exact configure line), the
`pam-ffmpeg-<version>-source.tar.xz` every platform was built from, and `SHA256SUMS`.

## Releasing

1. Edit `ffmpeg.env` (upstream version and its SHA256) or the build scripts.
2. Push a tag `ffmpeg-<FFMPEG_VERSION>-pam.<N>`; bump `N` for recipe-only changes.

The `Release` workflow builds, audits and publishes. Run it with `workflow_dispatch` to build and
audit without publishing.

## What is in the build

Configure flags live in `scripts/common_flags.sh` plus a short platform list in each
`scripts/build_<platform>.sh`. No GPL or nonfree components, no software H.264 or HEVC codecs,
nothing autodetected from the build machine. `scripts/audit_<platform>.sh` enforces this on every
build.
