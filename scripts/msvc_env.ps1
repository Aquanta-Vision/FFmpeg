# Loads the Visual Studio developer environment (what a Developer Command Prompt sets up) and
# exports it to the following GitHub Actions steps, so cl.exe, link.exe and dumpbin.exe are on
# PATH and INCLUDE/LIB point at the MSVC and Windows SDK files for the target.
#
# Usage: msvc_env.ps1 <arch>   arch as vcvarsall.bat takes it: x64, x64_arm64 or arm64
param([Parameter(Mandatory)][string]$Arch)
$ErrorActionPreference = 'Stop'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsPath = & $vswhere -latest -products * -property installationPath
$vcvarsall = Join-Path $vsPath 'VC\Auxiliary\Build\vcvarsall.bat'

$oldPath = $env:Path -split ';'
$devEnv = cmd /c "`"$vcvarsall`" $Arch >nul && set"
if ($LASTEXITCODE -ne 0) { throw "vcvarsall.bat $Arch failed" }

# PATH additions go through GITHUB_PATH; GitHub does not take PATH from GITHUB_ENV.
foreach ($line in $devEnv) {
  if ($line -notmatch '^([^=]+)=(.*)$') { continue }
  $name, $value = $Matches[1], $Matches[2]
  if ($name -eq 'Path') {
    $value -split ';' | Where-Object { $_ -and ($oldPath -notcontains $_) } |
      Add-Content -Path $env:GITHUB_PATH -Encoding utf8
  } elseif ([Environment]::GetEnvironmentVariable($name) -ne $value) {
    Add-Content -Path $env:GITHUB_ENV -Value "$name=$value" -Encoding utf8
  }
}
