# Configures this PowerShell session to build Swift on Windows.
#
# Swift on Windows needs three things that are NOT on PATH by default:
#   1. the MSVC toolchain (link.exe) from Visual Studio Build Tools
#   2. the Swift toolchain bin directory
#   3. SDKROOT, pointing at the Windows Swift platform SDK
#
# Dot-source this, do not run it:   . .\scripts\env.ps1
#
# Prerequisites (install once):
#   winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools"
#   winget install --id Swift.Toolchain

$ErrorActionPreference = 'Stop'

# --- 1. Visual Studio / MSVC ---------------------------------------------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw "vswhere.exe not found. Install Visual Studio Build Tools 2022 with the C++ workload."
}

$vsRoot = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) {
    throw "No Visual Studio install with MSVC C++ tools found. Swift on Windows requires them for linking."
}

# Enter-VsDevShell shells out to vswhere by bare name, so its own directory must be on PATH.
$env:Path = (Split-Path $vswhere) + ";" + $env:Path

Import-Module "$vsRoot\Common7\Tools\Microsoft.VisualStudio.DevShell.dll"
Enter-VsDevShell -VsInstallPath $vsRoot -SkipAutomaticLocation -DevCmdArguments "-arch=x64 -host_arch=x64" | Out-Null

# --- 2 & 3. Swift toolchain and SDK -------------------------------------------
# The Swift installer writes these to the *User* environment. A shell started before the
# install (or by a tool that snapshots the environment) will not have them, so read them
# from the registry rather than trusting the inherited environment.
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) { $env:Path = $userPath + ";" + $env:Path }

$sdkRoot = [System.Environment]::GetEnvironmentVariable("SDKROOT", "User")
if ($sdkRoot) { $env:SDKROOT = $sdkRoot }

if (-not (Get-Command swift -ErrorAction SilentlyContinue)) {
    throw "swift not on PATH after setup. Install with: winget install --id Swift.Toolchain"
}
if (-not $env:SDKROOT) {
    throw "SDKROOT is not set. Reinstall the Swift toolchain, or set it to <SwiftRoot>\Platforms\<ver>\Windows.platform\Developer\SDKs\Windows.sdk"
}
if (-not (Get-Command link -ErrorAction SilentlyContinue)) {
    throw "link.exe not on PATH after entering the VS dev shell."
}

Write-Host "Swift environment ready." -ForegroundColor Green
Write-Host "  swift   : $((Get-Command swift).Source)"
Write-Host "  link    : $((Get-Command link).Source)"
Write-Host "  SDKROOT : $env:SDKROOT"
