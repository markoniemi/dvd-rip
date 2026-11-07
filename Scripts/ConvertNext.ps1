# ==============================================================================
# Script: Convert queue (HandBrake + subtitle OCR) - run alongside RipDisc.ps1
#
# Scans I:\Video for subfolders (raw rips from MakeMKV). For every *.mkv in
# those subfolders that hasn't been converted yet:
#   1. Encodes it to H.265 with HandBrakeCLI, dropped as a flat file directly
#      in I:\Video (bitmap VobSub subtitles are copied through as-is for now).
#   2. OCRs each VobSub subtitle track on the RAW file via seconv.exe (Subtitle
#      Edit's CLI, tesseract engine) to SRT.
#   3. Remuxes those SRTs into the H.265 output with mkvmerge, alongside the
#      original bitmap subtitle tracks (nothing is dropped; see
#      -ReplaceBitmapSubs to change that).
#
# Output naming: a raw folder is normally a movie, and the output is named
# after the folder ("Kiki.mkv", or "Kiki - C1_t01.mkv" when the folder holds
# several files). A folder named "<Show>_S<season>" is a TV season instead:
# files in it called E01.mkv, E02.mkv, ... come out as "<Show> - S01E01.mkv",
# which Plex/Jellyfin parse. A file holding several episodes (a DVD "Play All"
# title) is named for its range, "E01-E03.mkv" -> "<Show> - S01E01-E03.mkv".
# RipDisc.ps1 -Title The_Crown_S01 -Index 1 is what produces such a folder;
# see Get-SeriesInfo in Config.ps1.
#
# Raw files are never touched or deleted - clean them up manually once you've
# checked the output.
#
# "Already converted" is tracked with a sidecar marker file next to each raw
# file: "<file>.mkv.converted". That survives reruns and doesn't care whether
# a flat output file of a similar name already exists.
#
# Requires (one-time setup):
#   - HandBrakeCLI, MKVToolNix (mkvmerge) - already in use by this pipeline
#   - Subtitle Edit 5.4+ with seconv.exe (ships as a separate CLI alongside
#     the GUI install as of v5.4.0-beta5)
#   - Tesseract OCR on PATH (winget install tesseract-ocr.tesseract) - seconv's
#     tesseract engine shells out to tesseract.exe
#
# Usage:
#   .\ConvertNext.ps1                      # drain whatever is pending, then exit
#   .\ConvertNext.ps1 -Watch                # keep polling for new raw folders
#   .\ConvertNext.ps1 -Only "Kiki"          # restrict this run to one raw subfolder
#   .\ConvertNext.ps1 -SkipSubtitles        # H.265 encode only, no OCR pass
#   .\ConvertNext.ps1 -ReplaceBitmapSubs    # drop original bitmap subs, keep only OCR'd SRT
#   .\ConvertNext.ps1 -MarkDone "Kiki"      # mark all files in that subfolder as
#                                           # already converted, without encoding
#                                           # (use for pre-existing raw folders
#                                           # whose h265 output already exists
#                                           # under a different name)
#   .\ConvertNext.ps1 -RedoSubtitles "Kiki" # redo OCR+remux on an already-converted
#                                           # file (strips the old SRT track, re-OCRs
#                                           # from the raw source) - no re-encode.
#                                           # Pass "all" to redo every converted file.
#   .\ConvertNext.ps1 -SkipPoster           # don't fetch/attach a poster image
#   .\ConvertNext.ps1 -FetchPoster "Kiki"   # (re)fetch the poster for an already-
#                                           # converted file without touching video/
#                                           # subs. Pass "all" to backfill every one.
#   .\ConvertNext.ps1 -ShowToolOutput       # also put the tools' own output on screen
#
# Console output is one line per step - encode, subs, poster, done - with a
# percentage that rewrites itself in place while HandBrake runs. Everything the
# tools print goes to a log beside the raw file instead ("E02.mkv.log"), which
# is appended to, one block per tool per run. When a step fails, the tail of
# that log is printed with it. -ShowToolOutput streams the lot to the console as
# well, as earlier versions did.
#
# Subtitle OCR covers the languages in SubtitleLanguages, which is also what
# HandBrake keeps - OCRing a track that won't be in the output is just slow -
# and each needs its Tesseract data file ("fin.traineddata"), without which
# seconv can't address the track at all.
#
# Poster images: if a .jpg/.jpeg/.png is sitting in the raw disc folder, that
# wins and gets used as-is (drop one there by hand to fix a bad TMDb guess
# up front). Otherwise it's fetched from TMDb - the tv endpoint for a season
# folder, cached as poster.jpg in the raw folder so every episode of that
# season reuses one lookup, the movie endpoint for anything else. TMDb needs a
# free API key
# saved as plain text in tmdb_api_key.txt next to this script
# (https://www.themoviedb.org/settings/api). Either way, the movie gets a
# sidecar image next to its mkv AND an embedded cover attachment in the mkv
# itself (via mkvpropedit) - best-effort, never blocks the rest of the
# pipeline on failure.
# ==============================================================================

param(
    [switch]$Watch,
    [int]$PollSeconds = 60,
    [string]$MarkDone,
    [switch]$SkipSubtitles,
    [switch]$ReplaceBitmapSubs,
    [string]$Only,
    [string]$RedoSubtitles,
    [switch]$SkipPoster,
    [string]$FetchPoster,
    [string]$Title,
    [switch]$ShowToolOutput
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    VideoRoot         = "I:\Video"
    HandBrake_Exe     = "C:\Program Files\HandBrake\HandBrakeCLI.exe"
    Seconv_Exe        = "C:\Program Files\Subtitle Edit\seconv.exe"
    MkvMerge_Exe      = "C:\Program Files\MKVToolNix\mkvmerge.exe"
    MkvPropEdit_Exe   = "C:\Program Files\MKVToolNix\mkvpropedit.exe"
    TesseractDir      = "C:\Program Files\Tesseract-OCR"
    TmdbApiKeyFile    = Join-Path $PSScriptRoot "tmdb_api_key.txt"
    StableSeconds     = 30   # skip files still being written (e.g. rip in progress)
    DefaultOcrLanguage = "fin"
    AudioLanguages    = "fin,eng,jpn"   # HandBrake --audio-lang-list
    SubtitleLanguages = "fin,eng"       # HandBrake --subtitle-lang-list
}
$VideoRoot       = $cfg.VideoRoot
$HandBrake_Exe   = $cfg.HandBrake_Exe
$Seconv_Exe      = $cfg.Seconv_Exe
$MkvMerge_Exe    = $cfg.MkvMerge_Exe
$MkvPropEdit_Exe = $cfg.MkvPropEdit_Exe
$TesseractDir    = $cfg.TesseractDir
$TmdbApiKeyFile  = $cfg.TmdbApiKeyFile
$StableSeconds   = $cfg.StableSeconds
$AudioLanguages    = $cfg.AudioLanguages
$SubtitleLanguages = $cfg.SubtitleLanguages

# seconv's tesseract engine shells out to tesseract.exe, which needs to be on PATH.
if ((Test-Path $TesseractDir) -and ($env:PATH -notlike "*$TesseractDir*")) {
    $env:PATH = "$env:PATH;$TesseractDir"
}

$TmdbApiKey = $null
if (Test-Path $TmdbApiKeyFile) { $TmdbApiKey = (Get-Content $TmdbApiKeyFile -Raw).Trim() }

function Get-MarkerPath($file) { "$($file.FullName).converted" }

# HandBrake, seconv and mkvmerge between them print a few hundred lines per
# file - scan tables, x265 settings, a progress line per percent - which buries
# the three facts worth seeing. All of it goes to a log beside the raw file
# instead: "E02.mkv.log", appended to, one block per tool per run. The console
# gets one line per step, and the tail of the log if something fails.
# -ShowToolOutput puts the whole lot back on screen as well.
function Get-LogPath($file) { "$($file.FullName).log" }

function Write-Log($logPath, $text) {
    if ($logPath) { Add-Content -LiteralPath $logPath -Value $text -Encoding utf8 }
}

function Write-Step($label, $text) { Write-Host ("   {0,-7} {1}" -f $label, $text) }

# One line, rewritten in place, for a step that takes minutes. Cleared by the
# Write-Step that reports the result.
function Write-StepProgress($label, $text) {
    Write-Host -NoNewline ("`r   {0,-7} {1}" -f $label, $text.PadRight(60))
}
function Clear-StepProgress { Write-Host -NoNewline ("`r{0}`r" -f (" " * 72)) }

# Runs a tool with its output going to $logPath, and returns its exit code.
# With -Progress, HandBrake's "Encoding: task 1 of 1, 42.00 %" lines are kept
# off the log and shown as a single percentage that updates in place.
function Invoke-Logged($exe, $toolArgs, $logPath, $label, [switch]$Progress) {
    Write-Log $logPath ""
    Write-Log $logPath "=== $label  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log $logPath ("$exe " + ($toolArgs -join ' '))

    # stderr goes to a file of its own rather than through 2>&1: PowerShell 5.1
    # wraps a native command's stderr in ErrorRecords, which renders every blank
    # line as "System.Management.Automation.RemoteException" and sets $? to
    # false even when the tool exited 0. HandBrake writes everything but the
    # progress line there, so that detail matters.
    $errFile = [System.IO.Path]::GetTempFileName()
    $showed = $false
    $code = -1
    # Percent steps, not every line: HandBrake emits a few hundred of them, and
    # a terminal that doesn't honour the carriage return would scroll all of it.
    $lastPct = -5
    try {
        & $exe @toolArgs 2> $errFile | ForEach-Object {
            $line = [string]$_
            if ($Progress -and $line -match 'task \d+ of \d+, ([\d.]+) %') {
                $pct = [int][double]$Matches[1]
                if ($pct -ge ($lastPct + 5) -or $pct -eq 100) {
                    $lastPct = $pct
                    Write-StepProgress $label ("{0,3} %" -f $pct)
                    $showed = $true
                }
                return
            }
            Write-Log $logPath $line
            if ($ShowToolOutput) { Write-Host "   $line" }
        }
        $code = $LASTEXITCODE
    } finally {
        if ($showed) { Clear-StepProgress }
        if (Test-Path $errFile) {
            Get-Content -LiteralPath $errFile | ForEach-Object {
                Write-Log $logPath $_
                if ($ShowToolOutput) { Write-Host "   $_" }
            }
            Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Log $logPath "exit $code"
    return $code
}

function Show-LogTail($logPath, $count = 15) {
    if (-not $logPath -or -not (Test-Path $logPath)) { return }
    Write-Host "   log      $logPath"
    Get-Content -LiteralPath $logPath -Tail $count | ForEach-Object { Write-Host "   | $_" }
}

function Format-Duration([timespan]$span) {
    if ($span.TotalHours -ge 1) { return $span.ToString("h\hmm\m") }
    if ($span.TotalMinutes -ge 1) { return $span.ToString("m\mss\s") }
    return $span.ToString("s\s")
}

# Flat output name for one raw file. A TV season folder (see Get-SeriesInfo in
# Config.ps1) holding E05.mkv gives "The Crown - S01E05.mkv", and E01-E03.mkv
# gives "The Crown - S01E01-E03.mkv"; anything else keeps the old behavior -
# the folder name, plus the raw file name when the folder holds more than one
# file.
function Get-OutputPath($dir, $raw, $multiple) {
    $series = Get-SeriesInfo $dir.Name
    $episode = Get-EpisodeTag $raw.BaseName
    if ($series -and $episode) {
        $outBase = "{0} - S{1:D2}{2}" -f $series.Show, $series.Season, $episode.Tag
    } elseif ($multiple) {
        $outBase = "$($dir.Name) - $($raw.BaseName)"
    } else {
        $outBase = $dir.Name
    }
    return Join-Path $VideoRoot "$outBase.mkv"
}

# Turns a raw disc folder name into a plausible movie title to search TMDb with.
function Get-MovieTitleGuess($dirName) {
    $t = $dirName -replace '_', ' '
    $t = $t -replace '\s+ekstrat$', ''       # "Prinsessa Mononoke ekstrat" (Finnish: extras disc)
    $t = $t -replace '\s+\d{4}$', ' $0'       # keep trailing year as-is, just tidy spacing
    return $t.Trim()
}

# Searches TMDb for $title and downloads its poster to $jpgPath. $searchType is
# the TMDb endpoint to use: "movie", or "tv" for a series. Best-effort: returns
# $false (and leaves no file) on any failure - never throws.
function Get-MoviePoster($title, $jpgPath, $searchType = "movie") {
    if (-not $TmdbApiKey) { return $false }
    try {
        $query = [uri]::EscapeDataString($title)
        $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/$searchType`?api_key=$TmdbApiKey&query=$query&language=fi-FI" -ErrorAction Stop
        if (-not $resp.results -or $resp.results.Count -eq 0) {
            $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/$searchType`?api_key=$TmdbApiKey&query=$query" -ErrorAction Stop
        }
        if (-not $resp.results -or $resp.results.Count -eq 0) {
            Write-Step "poster" "no TMDb match for '$title'"
            return $false
        }

        $posterPath = $resp.results[0].poster_path
        if (-not $posterPath) {
            Write-Step "poster" "TMDb match for '$title' has no poster image"
            return $false
        }

        Invoke-WebRequest -Uri "https://image.tmdb.org/t/p/w780$posterPath" -OutFile $jpgPath -ErrorAction Stop
        return $true
    } catch {
        Write-Step "poster" "TMDb fetch failed for '$title': $_"
        return $false
    }
}

function Get-ImageMimeType($ext) {
    switch ($ext.TrimStart('.').ToLowerInvariant()) {
        "jpg"  { return "image/jpeg" }
        "jpeg" { return "image/jpeg" }
        "png"  { return "image/png" }
        default { return $null }
    }
}

# Attaches $imagePath into $mkvPath as a "cover.<ext>" attachment, replacing
# any previous cover (jpg or png) so reruns/format switches don't pile up
# duplicates.
function Set-CoverArt($mkvPath, $imagePath, $logPath) {
    if (-not (Test-Path $imagePath)) { return $false }
    $ext = [System.IO.Path]::GetExtension($imagePath).TrimStart('.').ToLowerInvariant()
    $mimeType = Get-ImageMimeType $ext
    if (-not $mimeType) {
        Write-Step "poster" "unsupported image type '.$ext' - not attaching"
        return $false
    }
    $propArgs = @("$mkvPath", "--delete-attachment", "name:cover.jpg", "--delete-attachment", "name:cover.png",
                  "--attachment-name", "cover.$ext", "--attachment-mime-type", $mimeType,
                  "--add-attachment", "$imagePath")
    # mkvpropedit, like mkvmerge: 0 = ok, 1 = ok with warnings (it warns when
    # there was no old cover to delete, which is the normal first-time case),
    # 2 = failure.
    $code = Invoke-Logged $MkvPropEdit_Exe $propArgs $logPath "mkvpropedit (cover art)"
    if ($code -gt 1) {
        Write-Step "poster" "mkvpropedit failed (exit $code) - cover not attached"
        Show-LogTail $logPath 8
        return $false
    }
    return $true
}

# A jpg/png already sitting in the raw disc folder (dropped there by hand)
# wins over TMDb - lets you pre-seed the right cover for discs TMDb can't
# guess from the folder name. Picks the first match if there's more than one.
function Get-LocalPosterImage($rawDirPath) {
    if (-not $rawDirPath -or -not (Test-Path $rawDirPath)) { return $null }
    return Get-ChildItem -Path (Join-Path $rawDirPath "*") -File -Include "*.jpg", "*.jpeg", "*.png" | Select-Object -First 1
}

# One poster for a whole TV season, fetched once and cached in the raw folder
# as poster.jpg - the same file FetchPosterPreview.ps1 writes and
# Get-LocalPosterImage looks for, so the remaining episodes of the season reuse
# it instead of hitting TMDb once per file. Returns the cached file, or $null.
function Get-SeriesPosterImage($show, $rawDirPath) {
    if (-not $rawDirPath -or -not (Test-Path $rawDirPath)) { return $null }
    $posterFile = Join-Path $rawDirPath "poster.jpg"
    if (-not (Get-MoviePoster $show $posterFile "tv")) {
        # A download that died halfway would otherwise leave a broken poster.jpg
        # behind, and every later episode of the season would reuse it.
        Remove-Item -Path $posterFile -Force -ErrorAction SilentlyContinue
        return $null
    }
    return Get-Item -LiteralPath $posterFile
}

# Best-effort: sidecar image + mkv cover attachment for one movie or episode.
# Uses a jpg/png already in $rawDirPath if there is one; otherwise fetches from
# TMDb - the tv endpoint for a season folder (see Get-SeriesInfo in Config.ps1),
# the movie endpoint for anything else. Never blocks the caller on failure.
function Add-PosterArt($dirName, $targetMkvPath, $rawDirPath, $logPath) {
    if ($SkipPoster) { return }

    $localImage = Get-LocalPosterImage $rawDirPath

    # A season folder gets one series poster, cached as poster.jpg, which the
    # local-image branch below then uses for this and every later episode.
    if (-not $localImage -and $TmdbApiKey) {
        $series = Get-SeriesInfo $dirName
        if ($series) { $localImage = Get-SeriesPosterImage $series.Show $rawDirPath }
    }

    if ($localImage) {
        $posterPath = [System.IO.Path]::ChangeExtension($targetMkvPath, $localImage.Extension.TrimStart('.'))
        Copy-Item -Path $localImage.FullName -Destination $posterPath -Force
        if (Set-CoverArt $targetMkvPath $posterPath $logPath) {
            Write-Step "poster" "$($localImage.Name) attached"
        }
        return
    }

    if (-not $TmdbApiKey) { return }

    # Season folder with no poster: the tv lookup above already failed, and a
    # movie search for "The_Crown_S01" would only find nonsense.
    if (Get-SeriesInfo $dirName) { return }

    $jpgPath = [System.IO.Path]::ChangeExtension($targetMkvPath, "jpg")
    $title = Get-MovieTitleGuess $dirName

    if (-not (Get-MoviePoster $title $jpgPath)) { return }
    if (Set-CoverArt $targetMkvPath $jpgPath $logPath) {
        Write-Step "poster" "TMDb poster for '$title' attached"
    }
}

if ($MarkDone) {
    $dir = Join-Path $VideoRoot $MarkDone
    if (!(Test-Path $dir)) {
        Write-Host "Error: folder not found: $dir"
        exit 1
    }
    $files = Get-ChildItem -Path $dir -Filter "*.mkv" -File
    foreach ($f in $files) {
        New-Item -ItemType File -Path (Get-MarkerPath $f) -Force | Out-Null
        Write-Host " Marked converted: $($f.FullName)"
    }
    exit 0
}

# Default OCR language when a track's own language tag is missing/"und".
# This pipeline is mostly Finnish discs, so that's the sane fallback.
$DefaultOcrLanguage = $cfg.DefaultOcrLanguage

# OCRs every subtitle track of $rawPath via seconv (one call per track, with
# --ocr-language set from that track's own language tag - letting seconv pick
# automatically silently falls back to English and drops scandinavian
# characters), then remuxes the resulting SRTs into $targetMkvPath (the
# HandBrake output) with mkvmerge. Best-effort: any failure here is logged and
# swallowed - the H.265 encode itself already succeeded and shouldn't be held
# hostage by a bad OCR pass.
function Add-OcrSubtitles($rawPath, $targetMkvPath, $logPath) {
    $json = & $MkvMerge_Exe -J "$rawPath" 2>$null | ConvertFrom-Json
    $subTracks = @($json.tracks | Where-Object { $_.type -eq "subtitles" })
    if (-not $subTracks) { return }

    # Only the languages HandBrake keeps are worth OCRing: --subtitle-lang-list
    # drops the rest, so an SRT for them would sit beside no bitmap track. It
    # also saves the OCR pass on a disc carrying ten languages.
    $wanted = @($SubtitleLanguages -split ',' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
    $subTracks = @($subTracks | Where-Object {
        $l = $_.properties.language
        if (-not $l -or $l -eq "und") { $l = $DefaultOcrLanguage }
        $wanted -contains $l.ToLowerInvariant()
    })
    if (-not $subTracks) {
        Write-Step "subs" "no $($wanted -join '/') subtitle track in the raw file - nothing to OCR"
        return
    }

    $ocrDir = Join-Path $env:TEMP "seconv_$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $ocrDir | Out-Null

    try {
        $failed = 0
        $n = 0
        $ocrResults = @()
        foreach ($track in $subTracks) {
            # seconv's --track-number is the Matroska track number, which is
            # mkvmerge's 0-based id + 1.
            $trackNumber = $track.id + 1
            $lang = $track.properties.language
            if (-not $lang -or $lang -eq "und") { $lang = $DefaultOcrLanguage }
            $n++

            # seconv can only address a track whose language Tesseract has data
            # for; without it, it reports "No subtitle tracks matched", which
            # says nothing about the real problem.
            $trained = Join-Path $TesseractDir "tessdata\$lang.traineddata"
            if (-not (Test-Path $trained)) {
                Write-Step "subs" "no $lang.traineddata in Tesseract - track #$trackNumber ($lang) can't be OCR'd"
                Write-Log $logPath "skipped track #$trackNumber ($lang): $trained not found"
                $failed++
                continue
            }

            # OCR of a 47 minute track takes minutes, so say which one is running.
            Write-StepProgress "subs" ("OCR track {0} of {1} ({2})" -f $n, $subTracks.Count, $lang)
            # Each track gets its own output folder: seconv names its output
            # "<rawBaseName>.<lang>.srt", so two tracks of the same language
            # (e.g. full Finnish + a forced/partial Finnish track) would
            # otherwise overwrite each other and only the last one survives.
            $trackDir = Join-Path $ocrDir "t$trackNumber"
            New-Item -ItemType Directory -Path $trackDir -Force | Out-Null
            $seconvArgs = @("$rawPath", "subrip", "--track-number:$trackNumber", "--ocr-engine:tesseract",
                            "--ocr-language:$lang", "--output-folder:$trackDir", "--overwrite")
            $code = Invoke-Logged $Seconv_Exe $seconvArgs $logPath "seconv OCR track #$trackNumber ($lang)"
            if ($code -ne 0) {
                Clear-StepProgress
                Write-Step "subs" "seconv failed (exit $code) on track #$trackNumber ($lang) - that track is skipped"
                $failed++
                continue
            }
            $srt = Get-ChildItem -Path $trackDir -Filter "*.srt" -File | Select-Object -First 1
            if ($srt) {
                $cues = @(Get-Content -LiteralPath $srt.FullName -Encoding UTF8 | Where-Object { $_ -match '-->' }).Count
                $ocrResults += [pscustomobject]@{ Path = $srt.FullName; Lang = $lang; TrackNumber = $trackNumber; Cues = $cues }
            }
        }
        Clear-StepProgress

        $srtFiles = @($ocrResults)
        if (-not $srtFiles) {
            Write-Step "subs" "no SRT came out of seconv - bitmap subs kept as they are"
            Show-LogTail $logPath 8
            return
        }

        $remuxArgs = @("-o", "$targetMkvPath.withsubs.tmp.mkv")
        if ($ReplaceBitmapSubs) { $remuxArgs += "--no-subtitles" }
        $remuxArgs += "$targetMkvPath"

        foreach ($srt in $srtFiles) {
            $lang = $srt.Lang
            $name = "$lang (OCR)"
            $flags = @()
            # Several tracks in one language: the biggest one is the full
            # subtitle, a much smaller one is typically forced/partial
            # (signs, foreign dialogue) - name it so and keep it non-default.
            $sameLang = @($srtFiles | Where-Object { $_.Lang -eq $lang })
            if ($sameLang.Count -gt 1) {
                $primary = $sameLang | Sort-Object -Property Cues -Descending | Select-Object -First 1
                if ($srt.TrackNumber -eq $primary.TrackNumber) {
                    # the full track keeps the plain "<lang> (OCR)" name
                } elseif ($srt.Cues -lt [math]::Max(1, $primary.Cues * 0.2)) {
                    $name = "$lang (OCR, forced)"
                    $flags = @("--forced-display-flag", "0:yes", "--default-track-flag", "0:no")
                } else {
                    $name = "$lang (OCR, track $($srt.TrackNumber))"
                }
            }
            $remuxArgs += @("--language", "0:$lang", "--track-name", "0:$name") + $flags + @($srt.Path)
        }

        $tempOut = "$targetMkvPath.withsubs.tmp.mkv"
        Write-StepProgress "subs" "remuxing $($srtFiles.Count) SRT into the output"
        $code = Invoke-Logged $MkvMerge_Exe $remuxArgs $logPath "mkvmerge (remux OCR subtitles)"
        Clear-StepProgress

        # mkvmerge exit codes: 0 = ok, 1 = ok with warnings, 2 = failure
        if ($code -le 1 -and (Test-Path $tempOut)) {
            Move-Item -Path $tempOut -Destination $targetMkvPath -Force
            $of = if ($failed) { " ($failed track(s) failed)" } else { "" }
            $kept = if ($ReplaceBitmapSubs) { "bitmap subs dropped" } else { "bitmap subs kept too" }
            Write-Step "subs" ("{0} of {1} tracks OCR'd and remuxed, {2}{3}" -f $srtFiles.Count, $subTracks.Count, $kept, $of)
        } else {
            Write-Step "subs" "mkvmerge remux failed (exit $code) - bitmap subs kept as they are"
            Show-LogTail $logPath 8
            Remove-Item -Path $tempOut -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -Path $ocrDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($RedoSubtitles) {
    $targetDirs = Get-ChildItem -Path $VideoRoot -Directory | Sort-Object Name
    if ($RedoSubtitles -ne "all") { $targetDirs = $targetDirs | Where-Object { $_.Name -eq $RedoSubtitles } }
    if (-not $targetDirs) {
        Write-Host "Error: folder not found: $RedoSubtitles"
        exit 1
    }

    foreach ($dir in $targetDirs) {
        $rawFiles = Get-ChildItem -Path $dir.FullName -Filter "*.mkv" -File
        if (-not $rawFiles) { continue }
        $multiple = $rawFiles.Count -gt 1

        foreach ($raw in $rawFiles) {
            if (-not (Test-Path (Get-MarkerPath $raw))) {
                Write-Host " Skipping (not converted yet): $($raw.FullName)"
                continue
            }

            $outPath = Get-OutputPath $dir $raw $multiple
            if (-not (Test-Path $outPath)) {
                Write-Host " Skipping (output file missing): $outPath"
                continue
            }

            $json = & $MkvMerge_Exe -J "$outPath" 2>$null | ConvertFrom-Json
            $vobsubIds = $json.tracks | Where-Object { $_.type -eq "subtitles" -and $_.codec -eq "VobSub" } | ForEach-Object { $_.id }
            $hasSrt = $json.tracks | Where-Object { $_.type -eq "subtitles" -and $_.codec -ne "VobSub" }

            if (-not $hasSrt) {
                Write-Host " No OCR'd subtitle track found, nothing to redo: $outPath"
                continue
            }

            $logPath = Get-LogPath $raw
            Write-Host ""
            Write-Host " redoing subtitles: $(Split-Path $outPath -Leaf)"
            Write-Log $logPath ("##### ConvertNext -RedoSubtitles $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $outPath")

            $stripped = "$outPath.stripped.tmp.mkv"
            $stripArgs = if ($vobsubIds) {
                @("-o", "$stripped", "-s", ($vobsubIds -join ","), "$outPath")
            } else {
                @("-o", "$stripped", "--no-subtitles", "$outPath")
            }
            $code = Invoke-Logged $MkvMerge_Exe $stripArgs $logPath "mkvmerge (strip old subtitle tracks)"

            if ($code -gt 1 -or -not (Test-Path $stripped)) {
                Write-Step "subs" "could not strip the old subtitle track (exit $code) - skipped"
                Show-LogTail $logPath 8
                Remove-Item -Path $stripped -Force -ErrorAction SilentlyContinue
                continue
            }

            Add-OcrSubtitles -rawPath $raw.FullName -targetMkvPath $stripped -logPath $logPath

            Move-Item -Path $stripped -Destination $outPath -Force
            Write-Step "done" $outPath
        }
    }
    exit 0
}

if ($FetchPoster) {
    $targetDirs = Get-ChildItem -Path $VideoRoot -Directory | Sort-Object Name
    if ($FetchPoster -ne "all") { $targetDirs = $targetDirs | Where-Object { $_.Name -eq $FetchPoster } }
    if (-not $targetDirs) {
        Write-Host "Error: folder not found: $FetchPoster"
        exit 1
    }

    foreach ($dir in $targetDirs) {
        $rawFiles = Get-ChildItem -Path $dir.FullName -Filter "*.mkv" -File
        if (-not $rawFiles) { continue }
        $multiple = $rawFiles.Count -gt 1

        foreach ($raw in $rawFiles) {
            if (-not (Test-Path (Get-MarkerPath $raw))) {
                Write-Host " Skipping (not converted yet): $($raw.FullName)"
                continue
            }

            $outPath = Get-OutputPath $dir $raw $multiple
            if (-not (Test-Path $outPath)) {
                Write-Host " Skipping (output file missing): $outPath"
                continue
            }

            Write-Host ""
            Write-Host " poster for: $(Split-Path $outPath -Leaf)"
            $posterTitle = if ($Title) { $Title } else { $dir.Name }
            Add-PosterArt -dirName $posterTitle -targetMkvPath $outPath -rawDirPath $dir.FullName -logPath (Get-LogPath $raw)
        }
    }
    exit 0
}

function Invoke-ConvertPass {
    $didWork = $false
    $rawDirs = Get-ChildItem -Path $VideoRoot -Directory | Sort-Object Name
    if ($Only) { $rawDirs = $rawDirs | Where-Object { $_.Name -eq $Only } }

    foreach ($dir in $rawDirs) {
        $rawFiles = Get-ChildItem -Path $dir.FullName -Filter "*.mkv" -File
        if (-not $rawFiles) { continue }

        $multiple = $rawFiles.Count -gt 1

        foreach ($raw in $rawFiles) {
            $marker = Get-MarkerPath $raw
            if (Test-Path $marker) { continue }

            if ($raw.LastWriteTime -gt (Get-Date).AddSeconds(-$StableSeconds)) {
                Write-Host " Skipping (still being written): $($raw.FullName)"
                continue
            }

            $didWork = $true

            $outPath = Get-OutputPath $dir $raw $multiple

            if (Test-Path $outPath) {
                Write-Host " Output already exists, skipping encode and marking done: $outPath"
                New-Item -ItemType File -Path $marker -Force | Out-Null
                continue
            }

            $logPath = Get-LogPath $raw
            Write-Host ""
            Write-Host " $($dir.Name)\$($raw.Name) -> $(Split-Path $outPath -Leaf)"
            Write-Log $logPath ("##### ConvertNext $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($raw.FullName) -> $outPath")

            $hbArgs = @("-i", "$($raw.FullName)", "-o", "$outPath",
                        "--verbose=0", "-e", "x265", "-q", "22",
                        "--audio-lang-list", $AudioLanguages, "--all-audio", "--aencoder", "copy",
                        "--subtitle-lang-list", $SubtitleLanguages, "--all-subtitles")
            $started = Get-Date
            $code = Invoke-Logged $HandBrake_Exe $hbArgs $logPath "encode" -Progress

            if ($code -eq 0 -and (Test-Path $outPath)) {
                Write-Step "encode" ("{0}, {1:N2} GB -> {2:N2} GB" -f `
                    (Format-Duration ((Get-Date) - $started)), ($raw.Length / 1GB), ((Get-Item $outPath).Length / 1GB))

                if (-not $SkipSubtitles) {
                    Add-OcrSubtitles -rawPath $raw.FullName -targetMkvPath $outPath -logPath $logPath
                }

                Add-PosterArt -dirName $dir.Name -targetMkvPath $outPath -rawDirPath $dir.FullName -logPath $logPath

                New-Item -ItemType File -Path $marker -Force | Out-Null
                Write-Step "done" $outPath
            } else {
                Write-Step "encode" "HandBrake failed (exit $code) - will retry next run"
                Show-LogTail $logPath 15
                Remove-Item -Path $outPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

    return $didWork
}

do {
    $work = Invoke-ConvertPass
    if (-not $work) {
        Write-Host "No pending raw files to convert."
    }
    if ($Watch) {
        Write-Host "Waiting $PollSeconds s for new raw folders... (Ctrl+C to stop)"
        Start-Sleep -Seconds $PollSeconds
    }
} while ($Watch)
