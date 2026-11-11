<#
.SYNOPSIS
    Install all tools this pipeline needs, via winget.

.DESCRIPTION
    Skips anything already present at its expected path. Those paths come from
    the same config as the other scripts, so override them there if you
    install somewhere non-default (see docs/Configuration.md).

    See docs/InstallTools.md for the tool list and the Subtitle Edit version
    trap.

.PARAMETER SkipMakeMKV
    Don't install MakeMKV (the ripper).

.PARAMETER SkipHandBrake
    Don't install HandBrakeCLI (the H.265 encoder).

.PARAMETER SkipMkvToolNix
    Don't install MKVToolNix (mkvmerge/mkvpropedit/mkvextract).

.PARAMETER SkipSubtitleEdit
    Don't install Subtitle Edit (seconv.exe, the subtitle OCR CLI).

.PARAMETER SkipTesseract
    Don't install Tesseract OCR (the engine seconv shells out to).

.EXAMPLE
    .\InstallTools.ps1
    Install everything that's missing.

.EXAMPLE
    .\InstallTools.ps1 -SkipMakeMKV
    Install the rest, leaving MakeMKV alone.

.LINK
    docs/InstallTools.md
#>

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
