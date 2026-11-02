# ==============================================================================
# Script 1: Rip Disc (MakeMKV with Title Detection)
#
# Usage:
#   .\RipDisc.ps1                                  # folder named after the disc label
#   .\RipDisc.ps1 -Title Kikis_Delivery_Service    # folder named explicitly
#   .\RipDisc.ps1 -Title The_Crown_S01 -Index 1    # TV season, disc 1 -> E01.mkv, E02.mkv, ...
#   .\RipDisc.ps1 -Title The_Crown_S01 -Index 5    # next disc of it, continues at E05.mkv
#
# Disc labels are often useless ("G7_67158D1"), so -Title overrides them. With
# -Title an existing folder is REUSED, so every disc of a season lands in one
# folder; without it, a timestamp suffix keeps earlier rips intact.
#
# -Index <n> renames the ripped files to E<nn>.mkv starting at n, in MakeMKV
# title order. ConvertNext.ps1 turns "The_Crown_S01\E05.mkv" into
# "The Crown - S01E05.mkv" (see Get-SeriesInfo in Config.ps1).
#
# Title order is USUALLY episode order, but a "Play All" title or a bonus
# feature longer than MinLengthSeconds shifts everything by one. Every rip
# appends the disc's title table (duration, chapter count, source VOB) to
# titles.txt in the output folder - check it against the renames this script
# prints before converting. A "Play All" title that holds several episodes can
# be renamed for its range by hand, "E01-E03.mkv", and ConvertNext.ps1 turns
# that into "The Crown - S01E01-E03.mkv".
# ==============================================================================

param(
    [string]$Title,
    [int]$Index = 0
)

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

# Robot-mode TINFO attribute ids this script reads out of "makemkvcon -r info".
$TitleAttributes = @{
    8  = "Chapters"
    9  = "Duration"
    16 = "Source"
}

function ConvertTo-Seconds([string]$duration) {
    if ($duration -match '^(\d+):(\d{2}):(\d{2})$') { return ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [int]$Matches[3] }
    if ($duration -match '^(\d+):(\d{2})$')         { return ([int]$Matches[1] * 60) + [int]$Matches[2] }
    return $null
}

# Turns robot-mode TINFO lines into one row per title, in title-id order - the
# same order MakeMKV writes the files in, which is the order -Index numbers
# them in. "Rip" is whether this run's --minlength keeps the title.
function Get-DiscTitles($infoLines) {
    $titles = @{}
    foreach ($line in $infoLines) {
        if ($line -notmatch '^TINFO:(\d+),(\d+),\d+,"([^"]*)"') { continue }
        $id = [int]$Matches[1]
        $attribute = $TitleAttributes[[int]$Matches[2]]
        if (-not $attribute) { continue }
        if (-not $titles.ContainsKey($id)) { $titles[$id] = @{} }
        $titles[$id][$attribute] = $Matches[3]
    }

    foreach ($id in ($titles.Keys | Sort-Object)) {
        $seconds = ConvertTo-Seconds $titles[$id].Duration
        $rip = if ($null -eq $seconds) { "?" } elseif ($seconds -ge $MinLengthSeconds) { "yes" } else { "no" }
        [pscustomobject]@{
            Title    = "t{0:D2}" -f $id
            Duration = $titles[$id].Duration
            Chapters = $titles[$id].Chapters
            Source   = $titles[$id].Source
            Rip      = $rip
        }
    }
}

# MakeMKV names its output after the disc volume label, "C1_t00.mkv". Discs of
# one season often carry the SAME label, so disc 2 would write t00.mkv straight
# over disc 1's, with no warning. So each rip goes into its own staging folder
# and is moved up afterwards - a rename on the same volume, so no copying - and
# a name already taken gets a disc counter inserted: C1_d2_t00.mkv. The counter
# goes before the _tNN part, because that suffix is what NameEpisodes.ps1 reads
# the title order from.
function Move-RippedFiles($stageFolder, $folder) {
    $moved = @()

    foreach ($file in (Get-ChildItem -Path $stageFolder -Filter "*.mkv" -File | Sort-Object Name)) {
        $newName = $file.Name
        $disc = 1
        while (Test-Path (Join-Path $folder $newName)) {
            $disc++
            $newName = if ($file.BaseName -match '^(.*?)(_t\d+)$') {
                "{0}_d{1}{2}{3}" -f $Matches[1], $disc, $Matches[2], $file.Extension
            } else {
                "{0}_d{1}{2}" -f $file.BaseName, $disc, $file.Extension
            }
        }

        Move-Item -LiteralPath $file.FullName -Destination (Join-Path $folder $newName)
        if ($newName -ne $file.Name) { Write-Host " $($file.Name) -> $newName (name taken by an earlier disc)" }
        $moved += Get-Item -LiteralPath (Join-Path $folder $newName)
    }

    return $moved
}

# Renames this run's files to E<nn>.mkv in title order, starting at
# $firstEpisode. Only the files passed in are touched: earlier discs may have
# left unrenamed titles in the folder, and those are not this disc's episodes.
function Rename-Episodes($folder, $files, $firstEpisode) {
    $episode = $firstEpisode
    $renamed = @()

    foreach ($file in ($files | Sort-Object Name)) {
        if (Get-EpisodeTag $file.BaseName) { continue }

        $newName = "E{0:D2}.mkv" -f $episode
        if (Test-Path (Join-Path $folder $newName)) {
            # Wrong -Index for this disc. Stop, rather than scattering the rest
            # of the episodes across whatever numbers happen to be free.
            Write-Host " $newName already exists - stopping renames. Fix -Index, rename the rest by hand."
            break
        }

        Rename-Item -LiteralPath $file.FullName -NewName $newName
        Write-Host " $($file.Name) -> $newName"
        $renamed += $newName
        $episode++
    }

    return $renamed
}

Write-Host "====================================================="
Write-Host " Detecting Disc Title from Drive $DriveLetter..."
Write-Host "====================================================="

# Query MakeMKV for disc information
$DiscInfo = & $MakeMKV_Exe -r info disc:0 2>&1

# Extract the volume name from the drive info line (DRV:0,...)
$DiscLabel = ""
foreach ($line in $DiscInfo) {
    if ($line -match 'DRV:0,\d+,\d+,\d+,"([^"]+)","([^"]+)"') {
        $DiscLabel = $Matches[2].Trim()
        break
    }
}

# Clean up invalid filename characters or handle empty titles
if ($Title) {
    $CleanTitle = $Title -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'
    Write-Host " Disc label   : $DiscLabel"
    Write-Host " Using -Title : $CleanTitle"
} elseif ([string]::IsNullOrWhiteSpace($DiscLabel) -or $DiscLabel -eq '""') {
    $CleanTitle = "Movie_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    Write-Host " No usable disc label - using: $CleanTitle"
} else {
    # Replace spaces/underscores and remove illegal filename characters
    $CleanTitle = $DiscLabel -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'
    Write-Host " Detected Movie Title: $CleanTitle"
}

# Each disc gets its own subfolder under Video, so ConvertNext.ps1 can treat
# any subfolder there as a pending raw rip. A whole TV season shares one
# folder instead - that's what -Title plus -Index is for.
$DiscFolder = Join-Path -Path $VideoRoot -ChildPath $CleanTitle
$FolderCreated = $false
if (Test-Path $DiscFolder) {
    if ($Title) {
        # Explicit title, so the collision is deliberate: next disc of a season.
        Write-Host " Folder exists, appending to it: $DiscFolder"
    } else {
        # Folder already exists (same disc label ripped before) - don't collide with it.
        $DiscFolder = "$DiscFolder`_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $DiscFolder | Out-Null
        $FolderCreated = $true
    }
} else {
    New-Item -ItemType Directory -Path $DiscFolder | Out-Null
    $FolderCreated = $true
}

# Title table first: it's the only way to tell whether title order really is
# episode order on this disc, and it's worth having even if the rip fails.
$DiscTitles = Get-DiscTitles $DiscInfo
if ($DiscTitles) {
    $TitleTable = $DiscTitles | Format-Table Title, Duration, Chapters, Source, Rip -AutoSize | Out-String
    Write-Host $TitleTable
    $TitlesFile = Join-Path $DiscFolder "titles.txt"
    Add-Content -Path $TitlesFile -Value "Disc label: $DiscLabel   Ripped: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')   MinLength: $MinLengthSeconds s   Index: $Index"
    Add-Content -Path $TitlesFile -Value $TitleTable
    Write-Host " Title table appended to: $TitlesFile"
} else {
    Write-Host " Could not read a title table from MakeMKV - ripping anyway."
}

Write-Host " Starting Disc Extraction via MakeMKV..."
Write-Host " Raw output folder: $DiscFolder"

# Rip into a staging folder so this disc's output can never overwrite an
# earlier disc's, and so "did this rip produce anything" is answerable in a
# folder that already holds other discs. A subfolder is invisible to
# ConvertNext.ps1 and NameEpisodes.ps1, which both look at top-level files only.
$StageFolder = Join-Path $DiscFolder "_rip"
if (Test-Path $StageFolder) { Remove-Item -Path $StageFolder -Force -Recurse }
New-Item -ItemType Directory -Path $StageFolder | Out-Null

# Extract the main feature
& $MakeMKV_Exe mkv disc:0 all $StageFolder --minlength=$MinLengthSeconds

if (-not (Get-ChildItem -Path $StageFolder -Filter "*.mkv" -File)) {
    Write-Host "Error: No main feature found matching criteria."
    Remove-Item -Path $StageFolder -Force -Recurse -ErrorAction SilentlyContinue
    # Only throw the folder away if this run created it - with -Title it may
    # hold earlier discs of the same season.
    if ($FolderCreated) { Remove-Item -Path $DiscFolder -Force -Recurse -ErrorAction SilentlyContinue }
    exit 1
}

$RippedFiles = @(Move-RippedFiles $StageFolder $DiscFolder)
Remove-Item -Path $StageFolder -Force -Recurse -ErrorAction SilentlyContinue

if ($Index -gt 0) {
    Write-Host "====================================================="
    Write-Host (" Renaming episodes, starting at E{0:D2}:" -f $Index)
    $Renamed = @(Rename-Episodes $DiscFolder $RippedFiles $Index)
    if (-not $Renamed) { Write-Host " Nothing to rename." }

    # What this disc produced, under the names it ended up with: the new E<nn>
    # files plus anything the rename stopped short of.
    $RippedFiles = @($Renamed | ForEach-Object { Get-Item -LiteralPath (Join-Path $DiscFolder $_) }) +
                   @($RippedFiles | Where-Object { Test-Path -LiteralPath $_.FullName })
}

Write-Host "====================================================="
Write-Host " Rip completed successfully! This disc produced:"
foreach ($f in ($RippedFiles | Sort-Object Name)) { Write-Host " - $($f.Name)" }
Write-Host " Folder now contains:"
foreach ($f in (Get-ChildItem -Path $DiscFolder -Filter "*.mkv" -File | Sort-Object Name)) { Write-Host " - $($f.FullName)" }
Write-Host "====================================================="
