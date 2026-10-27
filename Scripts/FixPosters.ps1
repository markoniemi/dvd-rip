# ==============================================================================
# Script: Re-apply poster images from raw disc folders onto already-converted
# mkv files.
#
# ConvertNext.ps1 bakes the poster in at conversion time. This script redoes
# that step on demand, from whatever image is sitting in the raw disc folder
# right now - so to fix a wrong cover you drop a better jpg/png into the raw
# folder (replacing the old one) and rerun this.
#
# For every raw *.mkv that is marked converted ("<file>.mkv.converted") and
# whose converted output exists, it:
#   1. copies the raw folder's jpg/jpeg/png next to the converted mkv, named
#      after it ("<mkv basename>.<ext>"),
#   2. re-attaches it as the mkv's "cover.<ext>" attachment, replacing any
#      previous cover.
#
# Raw folders with no image, raw files not yet converted, and raw files whose
# converted output is missing are skipped - nothing is fetched from TMDb here
# (use FetchPosterPreview.ps1 for that).
#
# Usage:
#   .\FixPosters.ps1                  # every converted file that has a poster in its raw folder
#   .\FixPosters.ps1 -DirName "Kiki"  # just that one raw folder
# ==============================================================================

param(
    [string]$DirName
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    VideoRoot       = "I:\Video"
    MkvPropEdit_Exe = "C:\Program Files\MKVToolNix\mkvpropedit.exe"
}
$VideoRoot       = $cfg.VideoRoot
$MkvPropEdit_Exe = $cfg.MkvPropEdit_Exe

if (!(Test-Path $VideoRoot)) {
    Write-Host "Error: video root not found: $VideoRoot"
    exit 1
}

# Same marker/output naming ConvertNext.ps1 uses - keep these in sync with it.
function Get-MarkerPath($file) { "$($file.FullName).converted" }

function Get-OutputPath($dir, $raw, $multiple) {
    $outBase = if ($multiple) { "$($dir.Name) - $($raw.BaseName)" } else { $dir.Name }
    return Join-Path $VideoRoot "$outBase.mkv"
}

function Get-ImageMimeType($ext) {
    switch ($ext.TrimStart('.').ToLowerInvariant()) {
        "jpg"  { return "image/jpeg" }
        "jpeg" { return "image/jpeg" }
        "png"  { return "image/png" }
        default { return $null }
    }
}

# The poster for a disc is whatever jpg/jpeg/png sits in its raw folder
# (first match if there's more than one) - same rule ConvertNext.ps1 applies.
function Get-LocalPosterImage($rawDirPath) {
    if (-not $rawDirPath -or -not (Test-Path $rawDirPath)) { return $null }
    return Get-ChildItem -Path (Join-Path $rawDirPath "*") -File -Include "*.jpg", "*.jpeg", "*.png" | Select-Object -First 1
}

# Attaches $imagePath into $mkvPath as a "cover.<ext>" attachment, replacing
# any previous cover (jpg or png) so reruns/format switches don't pile up
# duplicates.
function Set-CoverArt($mkvPath, $imagePath) {
    $ext = [System.IO.Path]::GetExtension($imagePath).TrimStart('.').ToLowerInvariant()
    $mimeType = Get-ImageMimeType $ext
    if (-not $mimeType) {
        Write-Host " Unsupported poster image type '.$ext' - not attaching."
        return
    }
    & $MkvPropEdit_Exe "$mkvPath" --delete-attachment "name:cover.jpg" --delete-attachment "name:cover.png" `
      --attachment-name "cover.$ext" --attachment-mime-type $mimeType --add-attachment "$imagePath" 2>&1 |
        ForEach-Object { Write-Host "   $_" }
}

$targetDirs = Get-ChildItem -Path $VideoRoot -Directory | Sort-Object Name
if ($DirName) { $targetDirs = $targetDirs | Where-Object { $_.Name -eq $DirName } }
if (-not $targetDirs) {
    if ($DirName) {
        Write-Host "Error: folder not found: $DirName"
        exit 1
    }
    Write-Host "No raw folders under $VideoRoot."
    exit 0
}

$fixed = 0

foreach ($dir in $targetDirs) {
    $rawFiles = Get-ChildItem -Path $dir.FullName -Filter "*.mkv" -File
    if (-not $rawFiles) { continue }
    $multiple = $rawFiles.Count -gt 1

    $poster = Get-LocalPosterImage $dir.FullName
    if (-not $poster) {
        Write-Host " Skipping (no poster image in raw folder): $($dir.FullName)"
        continue
    }

    foreach ($raw in $rawFiles) {
        if (-not (Test-Path (Get-MarkerPath $raw))) {
            Write-Host " Skipping (not converted yet): $($raw.FullName)"
            continue
        }

        $outPath = Get-OutputPath $dir $raw $multiple
        if (-not (Test-Path $outPath)) {
            Write-Host " Skipping (converted file missing): $outPath"
            continue
        }

        $ext = $poster.Extension.TrimStart('.').ToLowerInvariant()
        if (-not (Get-ImageMimeType $ext)) {
            Write-Host " Skipping (unsupported poster type '.$ext'): $($poster.FullName)"
            continue
        }

        Write-Host "====================================================="
        Write-Host " Fixing poster: $outPath"
        Write-Host " Image        : $($poster.FullName)"
        Write-Host "====================================================="

        $sidecarPath = [System.IO.Path]::ChangeExtension($outPath, $ext)
        Copy-Item -Path $poster.FullName -Destination $sidecarPath -Force
        Write-Host " Poster copied: $sidecarPath"

        # A previous run may have left a sidecar in the other image format -
        # drop it so there's exactly one image next to the mkv.
        foreach ($staleExt in @("jpg", "jpeg", "png")) {
            if ($staleExt -eq $ext) { continue }
            $stale = [System.IO.Path]::ChangeExtension($outPath, $staleExt)
            if (Test-Path $stale) {
                Remove-Item -Path $stale -Force
                Write-Host " Removed stale sidecar: $stale"
            }
        }

        Set-CoverArt $outPath $sidecarPath
        $fixed++
        Write-Host " Done: $outPath"
    }
}

Write-Host ""
Write-Host "Posters fixed: $fixed"
