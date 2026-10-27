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
#
# Poster images: if a .jpg/.jpeg/.png is sitting in the raw disc folder, that
# wins and gets used as-is (drop one there by hand to fix a bad TMDb guess
# up front). Otherwise it's fetched from TMDb, which needs a free API key
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
    [string]$Title
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

function Get-OutputPath($dir, $raw, $multiple) {
    $outBase = if ($multiple) { "$($dir.Name) - $($raw.BaseName)" } else { $dir.Name }
    return Join-Path $VideoRoot "$outBase.mkv"
}

# Turns a raw disc folder name into a plausible movie title to search TMDb with.
function Get-MovieTitleGuess($dirName) {
    $t = $dirName -replace '_', ' '
    $t = $t -replace '\s+ekstrat$', ''       # "Prinsessa Mononoke ekstrat" (Finnish: extras disc)
    $t = $t -replace '\s+\d{4}$', ' $0'       # keep trailing year as-is, just tidy spacing
    return $t.Trim()
}

# Searches TMDb for $title and downloads its poster to $jpgPath. Best-effort:
# returns $false (and leaves no file) on any failure - never throws.
function Get-MoviePoster($title, $jpgPath) {
    if (-not $TmdbApiKey) { return $false }
    try {
        $query = [uri]::EscapeDataString($title)
        $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/movie?api_key=$TmdbApiKey&query=$query&language=fi-FI" -ErrorAction Stop
        if (-not $resp.results -or $resp.results.Count -eq 0) {
            $resp = Invoke-RestMethod -Uri "https://api.themoviedb.org/3/search/movie?api_key=$TmdbApiKey&query=$query" -ErrorAction Stop
        }
        if (-not $resp.results -or $resp.results.Count -eq 0) {
            Write-Host " No TMDb match for '$title'."
            return $false
        }

        $posterPath = $resp.results[0].poster_path
        if (-not $posterPath) {
            Write-Host " TMDb match for '$title' has no poster image."
            return $false
        }

        Invoke-WebRequest -Uri "https://image.tmdb.org/t/p/w780$posterPath" -OutFile $jpgPath -ErrorAction Stop
        Write-Host " Poster saved: $jpgPath"
        return $true
    } catch {
        Write-Host " Poster fetch failed for '$title': $_"
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
function Set-CoverArt($mkvPath, $imagePath) {
    if (-not (Test-Path $imagePath)) { return }
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

# A jpg/png already sitting in the raw disc folder (dropped there by hand)
# wins over TMDb - lets you pre-seed the right cover for discs TMDb can't
# guess from the folder name. Picks the first match if there's more than one.
function Get-LocalPosterImage($rawDirPath) {
    if (-not $rawDirPath -or -not (Test-Path $rawDirPath)) { return $null }
    return Get-ChildItem -Path (Join-Path $rawDirPath "*") -File -Include "*.jpg", "*.jpeg", "*.png" | Select-Object -First 1
}

# Best-effort: sidecar image + mkv cover attachment for one movie. Uses a
# jpg/png already in $rawDirPath if there is one, otherwise fetches from
# TMDb. Never blocks the caller on failure.
function Add-PosterArt($dirName, $targetMkvPath, $rawDirPath) {
    if ($SkipPoster) { return }

    $localImage = Get-LocalPosterImage $rawDirPath
    if ($localImage) {
        $posterPath = [System.IO.Path]::ChangeExtension($targetMkvPath, $localImage.Extension.TrimStart('.'))
        Copy-Item -Path $localImage.FullName -Destination $posterPath -Force
        Write-Host " Using local poster image: $($localImage.FullName)"
        Set-CoverArt $targetMkvPath $posterPath
        return
    }

    if (-not $TmdbApiKey) { return }

    $jpgPath = [System.IO.Path]::ChangeExtension($targetMkvPath, "jpg")
    $title = Get-MovieTitleGuess $dirName

    if (-not (Get-MoviePoster $title $jpgPath)) { return }
    Set-CoverArt $targetMkvPath $jpgPath
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
function Add-OcrSubtitles($rawPath, $targetMkvPath) {
    $json = & $MkvMerge_Exe -J "$rawPath" 2>$null | ConvertFrom-Json
    $subTracks = $json.tracks | Where-Object { $_.type -eq "subtitles" }
    if (-not $subTracks) { return }

    $ocrDir = Join-Path $env:TEMP "seconv_$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $ocrDir | Out-Null

    try {
        foreach ($track in $subTracks) {
            # seconv's --track-number is 1-based across all tracks (mkvmerge's 0-based id + 1)
            $trackNumber = $track.id + 1
            $lang = $track.properties.language
            if (-not $lang -or $lang -eq "und") { $lang = $DefaultOcrLanguage }

            Write-Host " Running subtitle OCR on: $rawPath (track #$trackNumber, lang $lang)"
            & $Seconv_Exe "$rawPath" subrip --track-number:$trackNumber --ocr-engine:tesseract --ocr-language:$lang --output-folder:"$ocrDir" --overwrite 2>&1 |
                ForEach-Object { Write-Host "   $_" }

            if ($LASTEXITCODE -ne 0) {
                Write-Host " seconv OCR failed (exit $LASTEXITCODE) on track #$trackNumber - skipping that track."
            }
        }

        $srtFiles = Get-ChildItem -Path $ocrDir -Filter "*.srt" -File
        if (-not $srtFiles) {
            Write-Host " seconv produced no SRT files - keeping bitmap subs only."
            return
        }

        $remuxArgs = @("-o", "$targetMkvPath.withsubs.tmp.mkv")
        if ($ReplaceBitmapSubs) { $remuxArgs += "--no-subtitles" }
        $remuxArgs += "$targetMkvPath"

        foreach ($srt in $srtFiles) {
            # seconv names output "<rawBaseName>.<lang>.srt"
            $lang = "und"
            if ($srt.BaseName -match '\.([a-z]{2,3})$') { $lang = $Matches[1] }
            $remuxArgs += @("--language", "0:$lang", "--track-name", "0:$lang (OCR)", $srt.FullName)
        }

        $tempOut = "$targetMkvPath.withsubs.tmp.mkv"
        & $MkvMerge_Exe @remuxArgs | ForEach-Object { Write-Host "   $_" }

        # mkvmerge exit codes: 0 = ok, 1 = ok with warnings, 2 = failure
        if ($LASTEXITCODE -le 1 -and (Test-Path $tempOut)) {
            Move-Item -Path $tempOut -Destination $targetMkvPath -Force
            Write-Host " OCR subtitles remuxed into: $targetMkvPath"
        } else {
            Write-Host " mkvmerge remux failed (exit $LASTEXITCODE) - keeping bitmap subs only."
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

            Write-Host "====================================================="
            Write-Host " Redoing subtitles: $outPath"
            Write-Host "====================================================="

            $stripped = "$outPath.stripped.tmp.mkv"
            if ($vobsubIds) {
                & $MkvMerge_Exe -o "$stripped" -s ($vobsubIds -join ",") "$outPath" | Out-Null
            } else {
                & $MkvMerge_Exe -o "$stripped" --no-subtitles "$outPath" | Out-Null
            }

            if ($LASTEXITCODE -gt 1 -or -not (Test-Path $stripped)) {
                Write-Host " Failed to strip old subtitle track (exit $LASTEXITCODE) - skipping."
                Remove-Item -Path $stripped -Force -ErrorAction SilentlyContinue
                continue
            }

            Add-OcrSubtitles -rawPath $raw.FullName -targetMkvPath $stripped

            Move-Item -Path $stripped -Destination $outPath -Force
            Write-Host " Done: $outPath"
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

            Write-Host "====================================================="
            Write-Host " Fetching poster for: $outPath"
            Write-Host "====================================================="

            $posterTitle = if ($Title) { $Title } else { $dir.Name }
            Add-PosterArt -dirName $posterTitle -targetMkvPath $outPath -rawDirPath $dir.FullName
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

            Write-Host "====================================================="
            Write-Host " Converting: $($raw.FullName)"
            Write-Host " Output    : $outPath"
            Write-Host "====================================================="

            & $HandBrake_Exe -i "$($raw.FullName)" -o "$outPath" `
              -e x265 -q 22 `
              --audio-lang-list $AudioLanguages --all-audio --aencoder copy `
              --subtitle-lang-list $SubtitleLanguages --all-subtitles

            if ($LASTEXITCODE -eq 0 -and (Test-Path $outPath)) {
                Write-Host " H.265 encode done: $outPath"

                if (-not $SkipSubtitles) {
                    Add-OcrSubtitles -rawPath $raw.FullName -targetMkvPath $outPath
                }

                Add-PosterArt -dirName $dir.Name -targetMkvPath $outPath -rawDirPath $dir.FullName

                New-Item -ItemType File -Path $marker -Force | Out-Null
                Write-Host " Done: $outPath"
            } else {
                Write-Host " HandBrake failed (exit $LASTEXITCODE) on $($raw.FullName) - will retry next run."
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
