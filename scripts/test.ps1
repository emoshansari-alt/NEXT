# Runs the NextKit test suite (Tier 1 verification — see ARCHITECTURE.md §6).
#
#   .\scripts\test.ps1              run all tests
#   .\scripts\test.ps1 -Build       compile only, do not run tests
#   .\scripts\test.ps1 -Filter Rank run only tests whose name matches

param(
    [switch]$Build,
    [string]$Filter
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

. "$PSScriptRoot\env.ps1"

Push-Location "$repo\NextKit"
try {
    if ($Build) {
        swift build
    } elseif ($Filter) {
        swift test --filter $Filter
    } else {
        swift test
    }
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

exit $code
