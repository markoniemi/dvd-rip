<#
.SYNOPSIS
    Fetch a candidate TMDb poster into each raw disc folder that doesn't
    already have one, for review before it gets baked into the mkv.

.DESCRIPTION
    Scans every raw folder under VideoRoot and never overwrites a folder that
    already holds a jpg/jpeg/png. Needs the same tmdb_api_key.txt next to this
    script as the other scripts.

    See docs/FetchPosterPreview.md for how this fits ConvertNext.ps1 and how a
    season folder is searched.

.PARAMETER DirName
    One raw disc folder under VideoRoot, by name. Omit it and every raw folder
    missing a poster is fetched.

.PARAMETER Title
    The TMDb search term, for when the folder name is not the film's title.

.EXAMPLE
    .\FetchPosterPreview.ps1
    All raw folders missing a poster.

.EXAMPLE
    .\FetchPosterPreview.ps1 -DirName "Kiki"
    Just that one folder.

.EXAMPLE
    .\FetchPosterPreview.ps1 -DirName "Kiki" -Title "Kiki's Delivery Service"
    Search TMDb for the real title rather than the folder name.

.LINK
    docs/FetchPosterPreview.md
#>

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
