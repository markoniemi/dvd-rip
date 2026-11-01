# ==============================================================================
# Script: Fetch a candidate TMDb poster into each raw disc folder that
# doesn't already have one, for review before it gets baked into the mkv.
#
# ConvertNext.ps1 uses a jpg/png already sitting in the raw disc folder as
# the poster instead of asking TMDb (see its header comment). This script is
# how you get a candidate image into those folders so you can look at it -
# and swap it for a different file, or delete it - before running
# ConvertNext.ps1.
#
# Scans every raw folder under VideoRoot and skips any that already has a
# jpg/jpeg/png in it (whether from a previous run of this script or dropped
# in by hand) - it never overwrites an existing candidate.
#
# Usage:
#   .\FetchPosterPreview.ps1                                    # all raw folders missing a poster
#   .\FetchPosterPreview.ps1 -DirName "Kiki"                    # just that one folder
#   .\FetchPosterPreview.ps1 -DirName "Kiki" -Title "Kiki's Delivery Service"
#
# A "<Show>_S<season>" folder (see Get-SeriesInfo in Config.ps1) is searched on
# TMDb's tv endpoint under the show name - one poster.jpg for the whole season,
# which every episode of it then reuses.
#
# Requires the same tmdb_api_key.txt next to this script as the other scripts.
# ==============================================================================

param(
    [string]$DirName,
    [string]$Title
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    VideoRoot      = "I:\Video"
    TmdbApiKeyFile = Join-Path $PSScriptRoot "tmdb_api_key.txt"
}
$VideoRoot      = $cfg.VideoRoot
$TmdbApiKeyFile = $cfg.TmdbApiKeyFile

if (!(Test-Path $TmdbApiKeyFile)) {
    Write-Host "Error: TMDb API key file not found: $TmdbApiKeyFile"
    exit 1
}
$TmdbApiKey = (Get-Content $TmdbApiKeyFile -Raw).Trim()

# Same cleanup ConvertNext.ps1 uses to turn a disc folder name into a search title.
function Get-MovieTitleGuess($dirName) {
    $t = $dirName -replace '_', ' '
    $t = $t -replace '\s+ekstrat$', ''       # "Prinsessa Mononoke ekstrat" (Finnish: extras disc)
    $t = $t -replace '\s+\d{4}$', ' $0'       # keep trailing year as-is, just tidy spacing
    return $t.Trim()
}

# Same lookup ConvertNext.ps1 uses to decide a raw folder already has a poster.
function Get-LocalPosterImage($dirPath) {
    return Get-ChildItem -Path (Join-Path $dirPath "*") -File -Include "*.jpg", "*.jpeg", "*.png" | Select-Object -First 1
}

# Searches TMDb for $title and saves the first match's poster as "poster.jpg"
# in $dirPath. $searchType is the TMDb endpoint: "movie", or "tv" for a series.
# Best-effort: logs and returns on any failure.
function Save-PosterPreview($dirPath, $title, $searchType = "movie") {
    try {
        $query = [uri]::EscapeDataString($title)
        $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/$searchType`?api_key=$TmdbApiKey&query=$query&language=fi-FI" -ErrorAction Stop
        if (-not $resp.results -or $resp.results.Count -eq 0) {
            $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/$searchType`?api_key=$TmdbApiKey&query=$query" -ErrorAction Stop
        }
    } catch {
        Write-Host " TMDb search failed for '$title': $_"
        return
    }

    if (-not $resp.results -or $resp.results.Count -eq 0) {
        Write-Host " No TMDb match for '$title'."
        return
    }

    # tv results carry name/first_air_date where movie results carry title/release_date.
    $match = $resp.results[0]
    $matchName = if ($match.title) { $match.title } else { $match.name }
    $matchDate = if ($match.release_date) { $match.release_date } else { $match.first_air_date }

    $posterPath = $match.poster_path
    if (-not $posterPath) {
        Write-Host " TMDb match '$matchName' ($matchDate) has no poster image."
        return
    }

    $posterFile = Join-Path $dirPath "poster.jpg"
    try {
        Invoke-WebRequest -Uri "https://image.tmdb.org/t/p/w780$posterPath" -OutFile $posterFile -ErrorAction Stop
    } catch {
        Write-Host " Poster download failed: $_"
        return
    }

    Write-Host " TMDb match: $matchName ($matchDate)"
    Write-Host " Poster saved: $posterFile"
}

$targetDirs = Get-ChildItem -Path $VideoRoot -Directory | Sort-Object Name
if ($DirName) { $targetDirs = $targetDirs | Where-Object { $_.Name -eq $DirName } }
if (-not $targetDirs) {
    Write-Host "Error: folder not found: $DirName"
    exit 1
}

foreach ($dir in $targetDirs) {
    $existing = Get-LocalPosterImage $dir.FullName
    if ($existing) {
        Write-Host " Already has a poster, skipping: $($existing.FullName)"
        continue
    }

    Write-Host " Fetching poster preview for: $($dir.FullName)"

    # A "<Show>_S<season>" folder is a TV season - search the tv endpoint for
    # the show name, not the movie endpoint for "The_Crown_S01".
    $series = Get-SeriesInfo $dir.Name
    if ($Title) {
        $searchTitle = $Title
        $searchType = if ($series) { "tv" } else { "movie" }
    } elseif ($series) {
        $searchTitle = $series.Show
        $searchType = "tv"
    } else {
        $searchTitle = Get-MovieTitleGuess $dir.Name
        $searchType = "movie"
    }

    Save-PosterPreview $dir.FullName $searchTitle $searchType
}

Write-Host ""
Write-Host "Check each poster.jpg, replace it, or delete it - whatever's left in a raw folder when ConvertNext.ps1 runs becomes that mkv's cover."
