# ==============================================================================
# Shared config loader and naming helpers - dot-source this from other scripts.
#
# Each script defines its own defaults as a hashtable and calls Get-RipConfig
# with them. If config.json exists next to the scripts, matching keys there
# override the defaults; anything config.json doesn't mention keeps its
# default. config.json is optional - skip it and everything just uses
# defaults as before.
#
# config.json is shared across all scripts, so it can hold keys a given
# script doesn't use (e.g. RipDisc.ps1 ignores ConvertNext.ps1's keys) -
# that's expected, not an error.
#
# Usage (in another script):
#   . (Join-Path $PSScriptRoot "Config.ps1")
#   $cfg = Get-RipConfig @{
#       VideoRoot = "I:\Video"
#       MinLengthSeconds = 3600
#   }
#   $VideoRoot = $cfg.VideoRoot
# ==============================================================================

function Get-RipConfig([hashtable]$Defaults) {
    $config = $Defaults.Clone()
    $configPath = Join-Path $PSScriptRoot "config.json"

    if (Test-Path $configPath) {
        $overrides = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($prop in $overrides.PSObject.Properties) {
            # Keys this script doesn't declare belong to another script -
            # config.json is shared, so silently skip them.
            if (-not $Defaults.ContainsKey($prop.Name)) { continue }
            $config[$prop.Name] = $prop.Value
        }
    }

    return $config
}

# ==============================================================================
# TV series naming, shared by RipDisc.ps1 / ConvertNext.ps1 / FetchPosterPreview.ps1.
#
# A raw folder named "<Show>_S<season>" (e.g. "The_Crown_S01", "TheCrownS01")
# is a TV season rather than a movie. RipDisc.ps1 -Index names the files in it
# E01.mkv, E02.mkv, ... and ConvertNext.ps1 turns "The_Crown_S01\E05.mkv" into
# "The Crown - S01E05.mkv", which Plex/Jellyfin parse. A file holding several
# episodes (a DVD "Play All" title) is named for its range instead,
# "E01-E03.mkv" -> "The Crown - S01E01-E03.mkv".
#
# Get-SeriesInfo returns $null for anything that doesn't look like a season
# folder - that's how every script decides "this is a movie, behave as before".
# ==============================================================================

function Get-SeriesInfo([string]$DirName) {
    if ($DirName -notmatch '^(?<show>.+?)[_ ]?S(?<season>\d{1,2})$') { return $null }
    return [pscustomobject]@{
        Show   = ($Matches.show -replace '_', ' ').Trim()
        Season = [int]$Matches.season
    }
}

# Episode tag out of a raw file name: "E05" -> one episode, "E01-E03" (or
# "E01-03") -> one file holding episodes 1 to 3, which is what a DVD "Play All"
# title is. Tag is the canonical, zero-padded form to put in the output name;
# Plex/Jellyfin read "<Show> - S01E01-E03.mkv" as all three episodes.
#
# $null for anything else, which is also how RipDisc.ps1 spots files an
# earlier disc of the same season already renamed.
function Get-EpisodeTag([string]$BaseName) {
    if ($BaseName -notmatch '^E(?<first>\d{1,3})(-E?(?<last>\d{1,3}))?$') { return $null }

    $first = [int]$Matches.first
    $last = if ($Matches.last) { [int]$Matches.last } else { $first }
    if ($last -lt $first) { return $null }

    return [pscustomobject]@{
        First = $first
        Last  = $last
        Tag   = if ($last -gt $first) { "E{0:D2}-E{1:D2}" -f $first, $last } else { "E{0:D2}" -f $first }
    }
}
