# ==============================================================================
# Script: Fix a wrong/missing poster on an already-converted mkv, from an
# image file you already downloaded yourself (e.g. a better TMDb match you
# picked by hand).
#
# Removes the old cover attachment (if any), copies -ImagePath over the
# sidecar "<mkv>.<ext>", and re-attaches it to the mkv via mkvpropedit.
#
# Usage:
#   .\FixPoster.ps1 -MkvPath "I:\Video\Kiki.mkv" -ImagePath "C:\Downloads\poster.jpg"
# ==============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$MkvPath,

    [Parameter(Mandatory = $true)]
    [string]$ImagePath
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    MkvPropEdit_Exe = "C:\Program Files\MKVToolNix\mkvpropedit.exe"
}
$MkvPropEdit_Exe = $cfg.MkvPropEdit_Exe

if (!(Test-Path $MkvPath)) {
    Write-Host "Error: file not found: $MkvPath"
    exit 1
}
$MkvPath = (Resolve-Path $MkvPath).Path

if (!(Test-Path $ImagePath)) {
    Write-Host "Error: image not found: $ImagePath"
    exit 1
}
$ImagePath = (Resolve-Path $ImagePath).Path

$ext = [System.IO.Path]::GetExtension($ImagePath).TrimStart('.').ToLowerInvariant()
$mimeType = switch ($ext) {
    "jpg"  { "image/jpeg" }
    "jpeg" { "image/jpeg" }
    "png"  { "image/png" }
    default {
        Write-Host "Error: unsupported image type '.$ext' (expected .jpg/.jpeg/.png)"
        exit 1
    }
}

$attachmentName = "cover.$ext"
$sidecarPath = [System.IO.Path]::ChangeExtension($MkvPath, $ext)

Copy-Item -Path $ImagePath -Destination $sidecarPath -Force
Write-Host " Poster copied: $sidecarPath"

# Delete any previous cover attachment regardless of its extension, so
# switching image formats across runs doesn't leave duplicates behind.
& $MkvPropEdit_Exe "$MkvPath" --delete-attachment "name:cover.jpg" --delete-attachment "name:cover.png" `
  --attachment-name $attachmentName --attachment-mime-type $mimeType --add-attachment "$sidecarPath" 2>&1 |
    ForEach-Object { Write-Host "   $_" }

Write-Host "Done: $MkvPath"
