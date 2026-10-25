# ==============================================================================
# Script: Install all tools this pipeline needs, via winget.
#
# Installs (skips any that's already present at its expected path):
#   - MakeMKV           (RipDisc.ps1)
#   - HandBrakeCLI       (ConvertNext.ps1 - encode)
#   - MKVToolNix         (ConvertNext.ps1/FixPoster.ps1 - mkvmerge/mkvpropedit)
#   - Subtitle Edit      (ConvertNext.ps1 - seconv.exe OCR CLI)
#   - Tesseract OCR      (ConvertNext.ps1 - OCR engine seconv shells out to)
#
# Winget's Subtitle Edit package can lag behind the 5.4.0-beta5+ needed for
# seconv.exe to exist. This script checks for seconv.exe afterwards and
# tells you to grab a newer installer manually from nikse.dk if it's missing.
#
# Usage:
#   .\InstallTools.ps1                     # install everything that's missing
#   .\InstallTools.ps1 -SkipMakeMKV         # (also: -SkipHandBrake, -SkipMkvToolNix,
#                                           #  -SkipSubtitleEdit, -SkipTesseract)
#
# Expected install paths come from the same config as the other scripts
# (see Config.ps1 / config.example.json) - override there if you install
# somewhere non-default.
# ==============================================================================

param(
    [switch]$SkipMakeMKV,
    [switch]$SkipHandBrake,
    [switch]$SkipMkvToolNix,
    [switch]$SkipSubtitleEdit,
    [switch]$SkipTesseract
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    MakeMKV_Exe     = "C:\Program Files (x86)\MakeMKV\makemkvcon64.exe"
    HandBrake_Exe   = "C:\Program Files\HandBrake\HandBrakeCLI.exe"
    MkvMerge_Exe    = "C:\Program Files\MKVToolNix\mkvmerge.exe"
    Seconv_Exe      = "C:\Program Files\Subtitle Edit\seconv.exe"
    TesseractDir    = "C:\Program Files\Tesseract-OCR"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "Error: winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    exit 1
}

function Install-Tool($name, $wingetId, $checkPath) {
    if (Test-Path $checkPath) {
        Write-Host " $name already installed: $checkPath"
        return
    }

    Write-Host "====================================================="
    Write-Host " Installing $name ($wingetId)..."
    Write-Host "====================================================="

    & winget install --id $wingetId -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Host " winget install failed for $name (exit $LASTEXITCODE)."
        return
    }

    if (Test-Path $checkPath) {
        Write-Host " $name installed: $checkPath"
    } else {
        Write-Host " ${name}: winget reported success but expected path not found: $checkPath"
        Write-Host " (it may have installed elsewhere - find it and set the matching path in config.json)"
    }
}

if (-not $SkipMakeMKV)      { Install-Tool "MakeMKV"       "GuinpinSoft.MakeMKV"      $cfg.MakeMKV_Exe }
if (-not $SkipHandBrake)    { Install-Tool "HandBrakeCLI"  "HandBrake.HandBrake.CLI"  $cfg.HandBrake_Exe }
if (-not $SkipMkvToolNix)   { Install-Tool "MKVToolNix"    "MoritzBunkus.MKVToolNix"  $cfg.MkvMerge_Exe }
if (-not $SkipSubtitleEdit) { Install-Tool "Subtitle Edit" "Nikse.SubtitleEdit"       $cfg.Seconv_Exe }
if (-not $SkipTesseract)    { Install-Tool "Tesseract OCR" "tesseract-ocr.tesseract"  (Join-Path $cfg.TesseractDir "tesseract.exe") }

Write-Host "====================================================="
Write-Host " Checking seconv.exe (needs Subtitle Edit 5.4.0-beta5+)..."
Write-Host "====================================================="
if (-not $SkipSubtitleEdit -and -not (Test-Path $cfg.Seconv_Exe)) {
    Write-Host " seconv.exe not found at $($cfg.Seconv_Exe)."
    Write-Host " winget's Subtitle Edit build may be older than 5.4.0-beta5, which is when seconv.exe"
    Write-Host " was added. Download a newer installer manually from https://www.nikse.dk/subtitleedit"
} else {
    Write-Host " OK."
}

Write-Host ""
Write-Host "Done. Remember to also set up Scripts\tmdb_api_key.txt (see README.md) for poster fetching."
