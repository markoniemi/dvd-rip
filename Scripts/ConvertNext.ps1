<#
.SYNOPSIS
    Convert queue: encode pending raw rips to H.265 and OCR their subtitles.
    Run alongside RipDisc.ps1.

.DESCRIPTION
    Scans VideoRoot for raw rip subfolders and, for every *.mkv in them not
    yet converted, encodes it with HandBrakeCLI, OCRs each VobSub subtitle
    track with seconv.exe and remuxes the SRTs in with mkvmerge. Raw files are
    never touched or deleted.

    See docs/ConvertNext.md for the output naming rules, the .converted
    marker, the per-file log and the subtitle languages.

.PARAMETER Watch
    Keep polling for new raw folders instead of exiting when the queue drains.

.PARAMETER PollSeconds
    How long -Watch waits between looks. Default 60.

.PARAMETER SkipSubtitles
    H.265 encode only, no OCR pass.

.PARAMETER ReplaceBitmapSubs
    Drop the original bitmap subtitle tracks, keeping only the OCR'd SRT.

.PARAMETER Only
    Restrict this run to one raw subfolder, by name.

.PARAMETER ShowToolOutput
    Also put the tools' own output on screen, as well as in the log.

.EXAMPLE
    .\ConvertNext.ps1
    Drain whatever is pending, then exit.

.EXAMPLE
    .\ConvertNext.ps1 -Watch -PollSeconds 300
    Keep polling for new raw folders, five minutes apart.

.EXAMPLE
    .\ConvertNext.ps1 -Only "Kiki" -ReplaceBitmapSubs
    One raw subfolder, keeping only the OCR'd SRT tracks.

.LINK
    docs/ConvertNext.md
#>

param(
    [switch]$Watch,
    [int]$PollSeconds = 60,
    [switch]$SkipSubtitles,
    [switch]$ReplaceBitmapSubs,
    [string]$Only,
    [switch]$ShowToolOutput
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    VideoRoot         = "I:\Video"
    HandBrake_Exe     = "C:\Program Files\HandBrake\HandBrakeCLI.exe"
    Seconv_Exe        = "C:\Program Files\Subtitle Edit\seconv.exe"
    MkvMerge_Exe      = "C:\Program Files\MKVToolNix\mkvmerge.exe"
    TesseractDir      = "C:\Program Files\Tesseract-OCR"
    StableSeconds     = 30   # skip files still being written (e.g. rip in progress)
    DefaultOcrLanguage = "fin"
    AudioLanguages    = "fin,eng,jpn"   # HandBrake --audio-lang-list
    SubtitleLanguages = "fin,eng"       # HandBrake --subtitle-lang-list
}
$VideoRoot       = $cfg.VideoRoot
$HandBrake_Exe   = $cfg.HandBrake_Exe
$Seconv_Exe      = $cfg.Seconv_Exe
$MkvMerge_Exe    = $cfg.MkvMerge_Exe
$TesseractDir    = $cfg.TesseractDir
$StableSeconds   = $cfg.StableSeconds
$AudioLanguages    = $cfg.AudioLanguages
$SubtitleLanguages = $cfg.SubtitleLanguages

# seconv's tesseract engine shells out to tesseract.exe, which needs to be on PATH.
if ((Test-Path $TesseractDir) -and ($env:PATH -notlike "*$TesseractDir*")) {
    $env:PATH = "$env:PATH;$TesseractDir"
}

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
