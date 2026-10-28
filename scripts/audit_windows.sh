#!/usr/bin/env bash
# Runs the spec's compliance checks against an installed windows platform tree: license and
# codec audit, import libraries only, no executables, and a DLL dependency allowlist. Runs in
# MSYS2 or Git Bash with the Visual Studio developer environment loaded, on a machine that can
# execute the target's binaries.
#
# Usage: scripts/audit_windows.sh <platform_dir>
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
platform_dir="$(cd "$1" && pwd)"
failures=0

# FFmpeg's own DLLs, the MSVC/UCRT runtime and Windows system DLLs; anything else is an
# unreviewed dependency.
allowed_deps_pattern='^(av(codec|format|util)|sw(scale|resample))_pam-[0-9]+\.dll$|^(kernel32|user32|advapi32|ole32|oleaut32|bcrypt|ws2_32|mfplat|vcruntime140(_1)?|api-ms-win-[a-z0-9-]+)\.dll$'

fail() {
  echo "FAIL $*"
  failures=$((failures + 1))
}

# MSVC tools take Windows paths; MSYS paths only work where its argument conversion guesses right.
winPath() {
  cygpath -w "$1"
}

runCodecAudit() {
  local work_dir
  work_dir="$(mktemp -d)"
  (
    cd "$work_dir"
    cl.exe -nologo "$(winPath "$script_dir/audit/audit.c")" -I"$(winPath "$platform_dir/include")" \
      -Feaudit.exe -link -LIBPATH:"$(winPath "$platform_dir/lib")" avcodec_pam.lib avutil_pam.lib
  )
  PATH="$platform_dir/bin:$PATH" "$work_dir/audit.exe" || fail "codec audit"
}

# Every .lib must be the import library of a shipped DLL, never a static library.
checkImportLibsOnly() {
  local lib name
  for lib in "$platform_dir"/lib/*.lib; do
    name="$(basename "$lib" .lib)"
    compgen -G "$platform_dir/bin/$name-*.dll" >/dev/null || fail "$(basename "$lib") has no matching DLL"
  done
  [ -z "$(find "$platform_dir" -name '*.a')" ] || fail "static .a libraries present"
}

checkNoExecutables() {
  local exes
  exes="$(find "$platform_dir" -iname '*.exe')"
  [ -z "$exes" ] || fail "executables present: $exes"
}

dllDependencies() {
  dumpbin.exe -nologo -dependents "$(winPath "$1")" | tr -d '\r' | sed -n 's/^ *\([^ ]*\.dll\)$/\1/Ip'
}

checkDllDependencies() {
  local dll dep
  for dll in "$platform_dir"/bin/*.dll; do
    for dep in $(dllDependencies "$dll"); do
      echo "$dep" | tr 'A-Z' 'a-z' | grep -qE "$allowed_deps_pattern" || fail "$(basename "$dll") needs $dep"
    done
  done
}

runCodecAudit
checkImportLibsOnly
checkNoExecutables
checkDllDependencies

if [ "$failures" -ne 0 ]; then
  echo "Audit FAILED with $failures finding(s)"
  exit 1
fi
echo "Audit PASSED"
