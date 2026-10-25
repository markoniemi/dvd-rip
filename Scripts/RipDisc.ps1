# ==============================================================================
# Script 1: Rip Disc (MakeMKV with Title Detection)
# ==============================================================================

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    DriveLetter       = "J:"                       # Your DVD/Blu-ray Drive Letter
    VideoRoot         = "I:\Video"                 # Raw rips land in a subfolder here; ConvertNext.ps1 picks them up
    MakeMKV_Exe       = "C:\Program Files (x86)\MakeMKV\makemkvcon64.exe"
    MinLengthSeconds  = 3600                        # 60 minutes minimum length
}
$DriveLetter      = $cfg.DriveLetter
$VideoRoot        = $cfg.VideoRoot
$MakeMKV_Exe      = $cfg.MakeMKV_Exe
$MinLengthSeconds = $cfg.MinLengthSeconds

if (!(Test-Path $VideoRoot)) { New-Item -ItemType Directory -Path $VideoRoot | Out-Null }

Write-Host "====================================================="
Write-Host " Detecting Disc Title from Drive $DriveLetter..."
Write-Host "====================================================="

# Query MakeMKV for disc information
$DiscInfo = & $MakeMKV_Exe -r info disc:0 2>&1

# Extract the volume name from the drive info line (DRV:0,...)
$DiscTitle = ""
foreach ($line in $DiscInfo) {
    if ($line -match 'DRV:0,\d+,\d+,\d+,"([^"]+)","([^"]+)"') {
        $DiscTitle = $Matches[2].Trim()
        break
    }
}

# Clean up invalid filename characters or handle empty titles
if ([string]::IsNullOrWhiteSpace($DiscTitle) -or $DiscTitle -eq " " -or $DiscTitle -eq '""') {
    $CleanTitle = "Movie_" + (Get-Date -Format "yyyyMMdd_HHmmss")
} else {
    # Replace spaces/underscores and remove illegal filename characters
    $CleanTitle = $DiscTitle -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'
}

Write-Host " Detected Movie Title: $CleanTitle"

# Each disc gets its own subfolder under Video, so 4_ConvertNext.ps1 can treat
# any subfolder there as a pending raw rip.
$DiscFolder = Join-Path -Path $VideoRoot -ChildPath $CleanTitle
if (Test-Path $DiscFolder) {
    # Folder already exists (same title ripped before) - don't collide with it.
    $DiscFolder = "$DiscFolder`_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
}
New-Item -ItemType Directory -Path $DiscFolder | Out-Null

Write-Host " Starting Disc Extraction via MakeMKV..."
Write-Host " Raw output folder: $DiscFolder"

# Extract the main feature
& $MakeMKV_Exe mkv disc:0 all $DiscFolder --minlength=$MinLengthSeconds

$RippedFiles = Get-ChildItem -Path $DiscFolder -Filter "*.mkv"

if ($RippedFiles) {
    Write-Host "====================================================="
    Write-Host " Rip completed successfully!"
    foreach ($f in $RippedFiles) { Write-Host " - $($f.FullName)" }
    Write-Host "====================================================="
} else {
    Write-Host "Error: No main feature found matching criteria."
    Remove-Item -Path $DiscFolder -Force -Recurse -ErrorAction SilentlyContinue
}