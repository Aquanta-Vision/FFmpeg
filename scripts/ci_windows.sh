#!/usr/bin/env bash
# CI entry point in MSYS2 bash on a Windows x64 runner: builds one windows target from the
# extracted release source archive, and audits it when the runner can execute it. The arm64
# build is audited in a separate job on an arm64 runner.
#
# Usage: scripts/ci_windows.sh <target> <source_root> <out_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
target="$1"
source_root="$2"
out_dir="$3"

"$script_dir/build_windows.sh" "$target" "$source_root" "$out_dir"
[ "$target" != x64 ] || "$script_dir/audit_windows.sh" "$out_dir"
