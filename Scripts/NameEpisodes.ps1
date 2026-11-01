# ==============================================================================
# Script: Name the raw titles in a TV season folder E01.mkv, E02.mkv, ...
#
# MakeMKV names its output by title index ("C1_t00.mkv"), and a DVD usually
# carries more titles than episodes: a "Play All" title holding several
# episodes back to back, and sometimes the same episode twice. Numbering files
# blindly in title order therefore shifts every episode after the first extra
# title, which is why RipDisc.ps1 -Index can't be trusted on its own.
#
# This script classifies the titles by arithmetic instead of by position, from
# durations and chapter boundaries read out of the files themselves:
#
#   Duplicate - same duration (within tolerance) and chapter count as a title
#               already accounted for.
#   Play All  - its duration equals the sum of a run of consecutive other
#               titles (and their chapter counts add up), OR one of its
#               chapters starts exactly where another title ends, meaning it
#               begins with that whole title and continues past it.
#   Episode   - whatever is left, numbered in title order.
#
# Nothing is guessed silently: every verdict is printed with the arithmetic
# behind it, and a title the rules can't explain is reported as Unknown and
# left alone. Dry run by default - add -Execute to apply.
#
# Usage:
#   .\NameEpisodes.ps1 -DirName The_Crown_S01                   # dry run
#   .\NameEpisodes.ps1 -DirName The_Crown_S01 -Execute          # apply
#   .\NameEpisodes.ps1 -DirName The_Crown_S01 -Index 5          # first episode is 5
#   .\NameEpisodes.ps1 -DirName The_Crown_S01 -Split -Execute   # cut Play Alls into episodes
#   .\NameEpisodes.ps1 -DirName The_Crown_S01 -Root I:\Work     # look under I:\Work, not VideoRoot
#
# Without -Index the first episode number continues from the highest E## file
# already in the folder, so the next disc of a season needs no argument.
#
# Play All titles: by default they are kept whole. One holding episodes nobody
# else covers is named for its range ("E01-E03.mkv", which ConvertNext.ps1
# turns into "<Show> - S01E01-E03.mkv"); one whose episodes all exist on their
# own is redundant and moves to _extra\ (ConvertNext.ps1 scans only the top
# level of a raw folder, so _extra\ is ignored). With -Split it is cut into
# single episodes at its chapter boundaries with mkvmerge - lossless, no
# re-encode - and the original then moves to _extra\.
#
# Duplicates always move to _extra\. Nothing is ever deleted.
# ==============================================================================

param(
    [Parameter(Mandatory = $true)][string]$DirName,
    [int]$Index = 0,
    [switch]$Split,
    [switch]$Execute,
    [string]$Root        # look under this instead of VideoRoot (a staging folder)
)

. (Join-Path $PSScriptRoot "Config.ps1")
$cfg = Get-RipConfig @{
    VideoRoot          = "I:\Video"
    MkvMerge_Exe       = "C:\Program Files\MKVToolNix\mkvmerge.exe"
    MkvExtract_Exe     = "C:\Program Files\MKVToolNix\mkvextract.exe"
    MinEpisodeSeconds  = 900    # 15 min - shorter than this isn't an episode
    MaxEpisodeSeconds  = 6000   # 100 min - longer than this is a Play All, not an episode
    DurationToleranceSeconds = 3
    StableSeconds      = 30     # ignore files a rip is still writing
}
$VideoRoot         = $cfg.VideoRoot
$MkvMerge_Exe      = $cfg.MkvMerge_Exe
$MkvExtract_Exe    = $cfg.MkvExtract_Exe
$MinEpisodeSeconds = $cfg.MinEpisodeSeconds
$MaxEpisodeSeconds = $cfg.MaxEpisodeSeconds
$Tolerance         = $cfg.DurationToleranceSeconds
$StableSeconds     = $cfg.StableSeconds

foreach ($exe in @($MkvMerge_Exe, $MkvExtract_Exe)) {
    if (-not (Test-Path $exe)) {
        Write-Host "Error: not found: $exe"
        exit 1
    }
}

if ($Root) { $VideoRoot = $Root }

$SeasonDir = Join-Path $VideoRoot $DirName
if (-not (Test-Path $SeasonDir)) {
    Write-Host "Error: folder not found: $SeasonDir"
    exit 1
}

$Series = Get-SeriesInfo $DirName
if (-not $Series) {
    Write-Host "Error: '$DirName' doesn't look like a season folder (expected <Show>_S<season>)."
    exit 1
}

function Format-Length([double]$seconds) {
    return [timespan]::FromSeconds($seconds).ToString('hh\:mm\:ss')
}

# MakeMKV encodes the title index in the file name as "_t<nn>", and that order
# is the order the titles sit on the disc. Fall back to the name when it isn't
# a MakeMKV name (a file already renamed by hand, say).
function Get-TitleOrder($file) {
    if ($file.BaseName -match '_t(\d+)$') { return [int]$Matches[1] }
    return 10000
}

# Duration, chapter count and chapter start times (seconds) of one mkv.
function Get-MkvFacts($path) {
    $json = & $MkvMerge_Exe -J "$path" 2>$null | ConvertFrom-Json
    $durationSeconds = $json.container.properties.duration / 1000000000

    $starts = @()
    foreach ($line in (& $MkvExtract_Exe "$path" chapters -s 2>$null)) {
        if ($line -match '^CHAPTER\d+=(\d+):(\d{2}):(\d{2})\.(\d{3})$') {
            $starts += ([int]$Matches[1] * 3600) + ([int]$Matches[2] * 60) + [int]$Matches[3] + ([int]$Matches[4] / 1000)
        }
    }

    return [pscustomobject]@{
        Duration     = $durationSeconds
        Chapters     = $starts.Count
        ChapterStart = $starts
    }
}

# Splits a chapter count into $count equal blocks, returning the 1-based
# chapter number each block after the first starts at - what mkvmerge
# --split chapters: wants. $null when it doesn't divide evenly.
function Get-UniformChapterSplit([int]$chapters, [int]$count) {
    if ($count -lt 2 -or $chapters -lt $count -or ($chapters % $count) -ne 0) { return $null }
    $per = $chapters / $count
    return @(1..($count - 1) | ForEach-Object { ($_ * $per) + 1 })
}

# Lengths of the blocks a chapter split would produce.
function Get-BlockLengths($facts, $splitAt) {
    $bounds = @(1) + $splitAt
    $lengths = @()
    for ($i = 0; $i -lt $bounds.Count; $i++) {
        $start = $facts.ChapterStart[$bounds[$i] - 1]
        $end = if ($i -eq $bounds.Count - 1) { $facts.Duration } else { $facts.ChapterStart[$bounds[$i + 1] - 1] }
        $lengths += ($end - $start)
    }
    return $lengths
}

function Test-EpisodeLength([double]$seconds) {
    return ($seconds -ge $MinEpisodeSeconds -and $seconds -le $MaxEpisodeSeconds)
}

# Is this the same title ripped twice? Episodes of a series run to nearly
# identical lengths - Downton Abbey season 3 disc 2 has three of them within
# six seconds of each other - so matching durations and chapter counts prove
# nothing on their own. Demand that the chapter marks line up and the files
# come out the same size, which is what two rips of one title look like.
function Test-SameTitle($a, $b) {
    if ($a.Facts.Chapters -ne $b.Facts.Chapters) { return $false }
    if ([math]::Abs($a.Facts.Duration - $b.Facts.Duration) -gt 1) { return $false }
    if ($a.File.Length -eq 0 -or $b.File.Length -eq 0) { return $false }

    $biggest = [double][math]::Max($a.File.Length, $b.File.Length)
    if (([math]::Abs($a.File.Length - $b.File.Length) / $biggest) -gt 0.01) { return $false }

    for ($i = 0; $i -lt $a.Facts.ChapterStart.Count; $i++) {
        if ([math]::Abs($a.Facts.ChapterStart[$i] - $b.Facts.ChapterStart[$i]) -gt 0.5) { return $false }
    }
    return $true
}

function Test-AllEpisodeLength($lengths) {
    return (@($lengths | Where-Object { -not (Test-EpisodeLength $_) }).Count -eq 0)
}

# Where to cut a file named for a range of episodes. E01-E03 with 18 chapters
# is three blocks of 6, so split at 7 and 13. But the chapters don't always
# divide evenly - a feature-length opener carries more of them (Downton Abbey
# season 3 opens with 8 chapters, then 6 and 6, for 20 in all). In that case,
# if one of the episodes already exists on its own and this file opens with it,
# peel that off at the chapter where it ends and divide the rest evenly.
# Returns the 1-based chapter numbers to split before, or $null.
function Get-RangeSplit($item, $all, [int]$count) {
    if ($count -lt 2) { return $null }

    $uniform = Get-UniformChapterSplit $item.Facts.Chapters $count
    if ($uniform -and (Test-AllEpisodeLength (Get-BlockLengths $item.Facts $uniform))) { return $uniform }

    foreach ($other in $all) {
        if ($other -eq $item -or $other.Facts.Chapters -ge $item.Facts.Chapters) { continue }

        # A chapter that starts exactly where $other ends means this file opens
        # with the whole of $other.
        $anchor = $null
        for ($c = 1; $c -lt $item.Facts.ChapterStart.Count; $c++) {
            if ([math]::Abs($item.Facts.ChapterStart[$c] - $other.Facts.Duration) -le $Tolerance) {
                $anchor = $c + 1
                break
            }
        }
        if (-not $anchor) { continue }

        $rest = $item.Facts.Chapters - ($anchor - 1)
        if (($rest % ($count - 1)) -ne 0) { continue }
        $per = $rest / ($count - 1)

        $splitAt = @($anchor)
        for ($b = 1; $b -lt ($count - 1); $b++) { $splitAt += ($anchor + ($b * $per)) }

        if (Test-AllEpisodeLength (Get-BlockLengths $item.Facts $splitAt)) { return $splitAt }
    }

    return $null
}

# ------------------------------------------------------------------ read files

$files = Get-ChildItem -Path $SeasonDir -Filter "*.mkv" -File |
    Sort-Object @{ Expression = { Get-TitleOrder $_ } }, Name

if (-not $files) {
    Write-Host "No mkv files directly in $SeasonDir."
    exit 0
}

Write-Host "====================================================="
Write-Host " $($Series.Show) - season $($Series.Season)"
Write-Host " Folder: $SeasonDir"
Write-Host "====================================================="

# A rip may still be running into this very folder (RipDisc.ps1 -Title reuses
# it for the next disc of the season). A half-written file reads as zero length
# with no chapters, which would classify as nonsense - leave it for next time.
$busy = @($files | Where-Object { $_.LastWriteTime -gt (Get-Date).AddSeconds(-$StableSeconds) })
foreach ($file in $busy) {
    Write-Host " Skipping (still being written): $($file.Name)"
}
$files = @($files | Where-Object { $busy -notcontains $_ })

if (-not $files) {
    Write-Host ""
    Write-Host "Nothing settled enough to look at yet."
    exit 0
}

$items = @()
foreach ($file in $files) {
    $facts = Get-MkvFacts $file.FullName
    $items += [pscustomobject]@{
        File     = $file
        Facts    = $facts
        Tag      = Get-EpisodeTag $file.BaseName   # non-null if already named
        Kind     = $null
        Evidence = ""
        Episodes = @()        # episode numbers this file covers
        Covers   = @()        # for a Play All: names of the titles it is made of
        Extra    = 0          # for a Play All found by anchor: episodes beyond the anchored one
        SplitAt  = $null
        Target   = $null
    }
}

# --------------------------------------------------------------- classify them

# Files already named E## / E##-E## are taken as given - the human named them,
# and on a second disc of a season they're the episodes from earlier discs.
foreach ($item in $items) {
    if (-not $item.Tag) { continue }
    $item.Kind = if ($item.Tag.Last -gt $item.Tag.First) { "PlayAll" } else { "Episode" }
    $item.Episodes = @($item.Tag.First..$item.Tag.Last)
    $item.Evidence = "already named $($item.Tag.Tag)"

    # A range name states how many episodes are in there, which is the one
    # piece of information the arithmetic can't always recover on its own (see
    # the "several readings" case below). Take it as given and work out the
    # chapter boundaries from it.
    if ($item.Tag.Last -gt $item.Tag.First) {
        $count = $item.Tag.Last - $item.Tag.First + 1
        $splitAt = Get-RangeSplit $item $items $count
        if (-not $splitAt) {
            $item.Evidence += "; $($item.Facts.Chapters) chapters don't resolve into $count episode-length blocks, so it can't be split"
        } else {
            $lengths = Get-BlockLengths $item.Facts $splitAt
            $item.SplitAt = $splitAt
            $item.Evidence += "; cut at ch $($splitAt -join ',') = $(($lengths | ForEach-Object { Format-Length $_ }) -join ' + ')"
        }
    }
}

$unnamed = @($items | Where-Object { -not $_.Tag })

# Duplicate: same length and chapter count as something already seen.
foreach ($item in $unnamed) {
    foreach ($other in $items) {
        if ($other -eq $item -or $other.Kind -eq "Duplicate") { continue }
        if (Test-SameTitle $item $other) {
            # Keep the first one in title order, flag this as the copy.
            if ($items.IndexOf($other) -lt $items.IndexOf($item)) {
                $item.Kind = "Duplicate"
                $item.Evidence = "same chapter marks and size as $($other.File.Name)"
                break
            }
        }
    }
}

# Play All, rule 1: duration equals the sum of a run of consecutive other
# titles, and the chapter counts add up too.
$candidates = @($items | Where-Object { -not $_.Kind })
foreach ($item in $candidates) {
    if ($item.Kind) { continue }
    $others = @($candidates | Where-Object { $_ -ne $item })
    for ($i = 0; $i -lt $others.Count -and -not $item.Kind; $i++) {
        $sumDuration = 0.0
        $sumChapters = 0
        for ($j = $i; $j -lt $others.Count; $j++) {
            $sumDuration += $others[$j].Facts.Duration
            $sumChapters += $others[$j].Facts.Chapters
            if ($j -eq $i) { continue }   # a run of one is just the title itself

            if ([math]::Abs($sumDuration - $item.Facts.Duration) -le $Tolerance -and
                $sumChapters -eq $item.Facts.Chapters) {
                $parts = @($others[$i..$j] | ForEach-Object { $_.File.Name })
                $item.Kind = "PlayAll"
                $item.Evidence = "length and chapters equal $($parts -join ' + ')"
                $item.Covers = $parts
                $item.SplitAt = @()
                $offset = 0
                for ($k = $i; $k -lt $j; $k++) {
                    $offset += $others[$k].Facts.Chapters
                    $item.SplitAt += ($offset + 1)
                }
                break
            }
        }
    }
}

# Play All, rule 2: one of its chapters starts exactly where another title
# ends, so it opens with that whole title and runs past it. The remainder is
# then divided into equal chapter blocks, and accepted only if every block
# comes out episode-length.
foreach ($item in @($items | Where-Object { -not $_.Kind })) {
    if (Test-EpisodeLength $item.Facts.Duration) { continue }   # it's just a long episode

    foreach ($other in $items) {
        if ($other -eq $item -or $other.Kind -eq "Duplicate") { continue }
        if ($other.Facts.Duration -ge $item.Facts.Duration) { continue }

        $anchor = $null
        for ($c = 1; $c -lt $item.Facts.ChapterStart.Count; $c++) {
            if ([math]::Abs($item.Facts.ChapterStart[$c] - $other.Facts.Duration) -le $Tolerance) {
                $anchor = $c + 1   # 1-based chapter number where the next episode starts
                break
            }
        }
        if (-not $anchor) { continue }

        $restChapters = $item.Facts.Chapters - ($anchor - 1)
        $restSeconds = $item.Facts.Duration - $other.Facts.Duration

        # How many episodes fill the remainder? Try every count whose blocks
        # divide the chapters evenly and come out episode-length. More than one
        # count can fit - 18 chapters over 2:20 is three 47 minute episodes or
        # two 70 minute ones, and no arithmetic on this disc alone can tell
        # which. Say so rather than pick one.
        $readings = @()
        for ($count = 1; $count -le 6; $count++) {
            if (($restChapters % $count) -ne 0) { continue }
            $per = $restChapters / $count
            $bounds = @(1..$count | ForEach-Object { $anchor + (($_ - 1) * $per) })
            $lengths = @()
            for ($b = 0; $b -lt $bounds.Count; $b++) {
                $start = $item.Facts.ChapterStart[$bounds[$b] - 1]
                $end = if ($b -eq $bounds.Count - 1) { $item.Facts.Duration } else { $item.Facts.ChapterStart[$bounds[$b + 1] - 1] }
                $lengths += ($end - $start)
            }
            if (@($lengths | Where-Object { -not (Test-EpisodeLength $_) }).Count -eq 0) {
                $readings += [pscustomobject]@{ Count = $count; Bounds = $bounds; Lengths = $lengths }
            }
        }

        if ($readings.Count -eq 0) { continue }

        if ($readings.Count -gt 1) {
            $options = @($readings | ForEach-Object {
                "{0}x{1}ch ({2})" -f $_.Count, ($restChapters / $_.Count), (($_.Lengths | ForEach-Object { Format-Length $_ }) -join '+')
            })
            $item.Kind = "Unknown"
            $item.Evidence = ("starts with {0} at chapter {1}, but the remaining {2} chapters fit several readings: {3} - rename it E<first>-E<last>.mkv to settle it" -f `
                $other.File.Name, $anchor, $restChapters, ($options -join ' | '))
            break
        }

        $reading = $readings[0]
        $item.Kind = "PlayAll"
        $item.Evidence = ("starts with {0} (chapter {1} at {2}), then {3} x {4} ch" -f `
            $other.File.Name, $anchor, (Format-Length $other.Facts.Duration), $reading.Count, ($restChapters / $reading.Count))
        $item.Covers = @($other.File.Name)
        $item.Extra = $reading.Count
        $item.SplitAt = @($reading.Bounds | Where-Object { $_ -gt 1 })
        break
    }
}

# Anything left that is episode-length is an episode; anything else is beyond
# these rules and gets left alone.
foreach ($item in @($items | Where-Object { -not $_.Kind })) {
    if (Test-EpisodeLength $item.Facts.Duration) {
        $item.Kind = "Episode"
    } else {
        $item.Kind = "Unknown"
        $item.Evidence = "$(Format-Length $item.Facts.Duration) is outside episode length, and no run of titles adds up to it"
    }
}

# ------------------------------------------------------- assign episode numbers

$taken = @{}
foreach ($item in $items) {
    foreach ($ep in $item.Episodes) { $taken[$ep] = $true }
}

# [int] matters: Measure-Object hands back a Double, and "{0:D2}" refuses the
# D format on anything non-integral.
[int]$next = if ($Index -gt 0) {
    $Index
} elseif ($taken.Keys.Count -gt 0) {
    [int](($taken.Keys | Measure-Object -Maximum).Maximum) + 1
} else {
    1
}

foreach ($item in $items) {
    if ($item.Kind -ne "Episode" -or $item.Episodes.Count -gt 0) { continue }
    while ($taken.ContainsKey($next)) { $next++ }
    $item.Episodes = @($next)
    $taken[$next] = $true
    $next++
}

# A Play All found by rule 1 or 2 covers the titles it is made of, so its
# episode span comes from theirs - not from wherever the counter happens to be.
foreach ($item in $items) {
    if ($item.Kind -ne "PlayAll" -or $item.Episodes.Count -gt 0) { continue }

    $blocks = if ($item.SplitAt) { $item.SplitAt.Count + 1 } else { 0 }
    if ($blocks -lt 2 -or $item.Covers.Count -eq 0) {
        $item.Kind = "Unknown"
        $item.Evidence += " (couldn't work out which episodes it holds)"
        continue
    }

    $covered = @()
    foreach ($name in $item.Covers) {
        $source = @($items | Where-Object { $_.File.Name -eq $name })
        if ($source) { $covered += $source[0].Episodes }
    }
    if (-not $covered) {
        $item.Kind = "Unknown"
        $item.Evidence += " (the titles it holds have no episode numbers)"
        continue
    }

    $first = ($covered | Measure-Object -Minimum).Minimum
    if ($item.Extra -gt 0) {
        # Anchor rule: it opens with that one title and runs $Extra episodes on
        # past it, and those episodes exist nowhere else - reserve their numbers.
        $covered = @($first..($first + $item.Extra))
    }

    $item.Episodes = @($covered | Sort-Object)
    foreach ($ep in $item.Episodes) {
        $taken[$ep] = $true
        if ($ep -ge $next) { $next = $ep + 1 }
    }
}

# A long title the rules above couldn't place may still be a Play All of
# episodes that now have numbers - including ones named on an earlier disc.
# Those rules compare titles in disc order, and a file renamed by an earlier
# run has no title index left to sort by, so check against episode numbers
# instead. This is what spots that a season's "Play All" is redundant once its
# episodes are all named.
$numbered = @($items | Where-Object { $_.Kind -eq "Episode" -and $_.Episodes.Count -eq 1 } |
    Sort-Object { $_.Episodes[0] })

foreach ($item in @($items | Where-Object { $_.Kind -eq "Unknown" })) {
    for ($i = 0; $i -lt $numbered.Count -and $item.Kind -eq "Unknown"; $i++) {
        $sumDuration = 0.0
        $sumChapters = 0
        for ($j = $i; $j -lt $numbered.Count; $j++) {
            # The run has to be consecutive episodes, not any old selection.
            if ($j -gt $i -and $numbered[$j].Episodes[0] -ne ($numbered[$j - 1].Episodes[0] + 1)) { break }

            $sumDuration += $numbered[$j].Facts.Duration
            $sumChapters += $numbered[$j].Facts.Chapters
            if ($j -eq $i) { continue }

            if ([math]::Abs($sumDuration - $item.Facts.Duration) -le $Tolerance -and
                $sumChapters -eq $item.Facts.Chapters) {
                $item.Kind = "PlayAll"
                $item.Episodes = @($numbered[$i].Episodes[0]..$numbered[$j].Episodes[0])
                $item.Covers = @($numbered[$i..$j] | ForEach-Object { $_.File.Name })
                $item.Evidence = "length and chapters equal $($item.Covers -join ' + ')"

                $item.SplitAt = @()
                $offset = 0
                for ($k = $i; $k -lt $j; $k++) {
                    $offset += $numbered[$k].Facts.Chapters
                    $item.SplitAt += ($offset + 1)
                }
                break
            }
        }
    }
}

# ---------------------------------------------------------------- plan targets

$extraDir = Join-Path $SeasonDir "_extra"

foreach ($item in $items) {
    switch ($item.Kind) {
        "Episode" {
            $item.Target = Join-Path $SeasonDir ("E{0:D2}.mkv" -f $item.Episodes[0])
        }
        "Duplicate" {
            $item.Target = Join-Path $extraDir ("{0}_duplicate.mkv" -f $item.File.BaseName)
        }
        "PlayAll" {
            $first = $item.Episodes[0]
            $last = $item.Episodes[-1]
            $tag = "E{0:D2}-E{1:D2}" -f $first, $last

            # Redundant if every episode it holds also exists on its own - then
            # it just moves aside, and splitting it would remux gigabytes into
            # files that are already there.
            $singles = @($items | Where-Object { $_.Kind -eq "Episode" } | ForEach-Object { $_.Episodes[0] })
            $missing = @($item.Episodes | Where-Object { $singles -notcontains $_ })

            if ($missing.Count -eq 0) {
                $item.SplitAt = $null
                $item.Evidence += "; every episode in it exists on its own"
                $item.Target = Join-Path $extraDir ("PlayAll_{0}.mkv" -f $tag)
            } elseif ($Split -and $item.SplitAt) {
                $item.Target = Join-Path $extraDir ("PlayAll_{0}.mkv" -f $tag)
            } else {
                $item.Target = Join-Path $SeasonDir "$tag.mkv"
            }
        }
        default { $item.Target = $null }
    }
}

# ----------------------------------------------------------------- print a plan

Write-Host ""
Write-Host "--- titles ---"
foreach ($item in $items) {
    Write-Host (" {0,-16} {1}  {2,3} ch  {3,-9} {4}" -f `
        $item.File.Name, (Format-Length $item.Facts.Duration), $item.Facts.Chapters, $item.Kind, $item.Evidence)
}

Write-Host ""
Write-Host "--- plan ---"
$actions = @()
foreach ($item in $items) {
    if ($item.Kind -eq "Unknown") {
        Write-Host (" {0,-16} LEFT ALONE - {1}" -f $item.File.Name, $item.Evidence)
        continue
    }

    if (-not $item.Target) {
        Write-Host (" {0,-16} LEFT ALONE - classified {1} but no name was worked out for it" -f $item.File.Name, $item.Kind)
        continue
    }

    if ($item.Kind -eq "PlayAll" -and $Split -and $item.SplitAt) {
        $lengths = Get-BlockLengths $item.Facts $item.SplitAt
        for ($i = 0; $i -lt $item.Episodes.Count; $i++) {
            $ep = $item.Episodes[$i]
            $len = if ($i -lt $lengths.Count) { Format-Length $lengths[$i] } else { "?" }
            $epPath = Join-Path $SeasonDir ("E{0:D2}.mkv" -f $ep)
            if (Test-Path -LiteralPath $epPath) {
                Write-Host ("   part {0} ({1}) -> E{2:D2}.mkv already exists, skipping that piece" -f ($i + 1), $len, $ep)
            } else {
                Write-Host ("   part {0} ({1}) -> E{2:D2}.mkv" -f ($i + 1), $len, $ep)
            }
        }
        Write-Host (" {0,-16} SPLIT at chapters {1}, original -> _extra\{2}" -f `
            $item.File.Name, ($item.SplitAt -join ','), (Split-Path $item.Target -Leaf))
        $actions += $item
        continue
    }

    if ($item.File.FullName -eq $item.Target) {
        Write-Host (" {0,-16} already correct" -f $item.File.Name)
        continue
    }

    $rel = $item.Target.Substring($SeasonDir.Length + 1)
    Write-Host (" {0,-16} -> {1}" -f $item.File.Name, $rel)
    $actions += $item
}

if (-not $actions) {
    Write-Host ""
    Write-Host "Nothing to do."
    exit 0
}

if (-not $Execute) {
    Write-Host ""
    Write-Host "Dry run. Re-run with -Execute to apply."
    if (-not $Split -and @($items | Where-Object { $_.Kind -eq 'PlayAll' -and $_.SplitAt }).Count -gt 0) {
        Write-Host "Add -Split to cut the Play All titles into single episodes instead of keeping them whole."
    }
    exit 0
}

# ------------------------------------------------------------------- apply it

# Refuse to start if a rename would land on a file that's already there.
$blockers = @()
foreach ($item in $actions) {
    if ($item.Kind -eq "PlayAll" -and $Split -and $item.SplitAt) { continue }
    if ((Test-Path -LiteralPath $item.Target) -and $item.Target -ne $item.File.FullName) {
        $blockers += "target already exists: $($item.Target)"
    }
}
if ($blockers) {
    Write-Host ""
    $blockers | ForEach-Object { Write-Host " $_" }
    Write-Host "Nothing moved."
    exit 1
}

$log = Join-Path $SeasonDir "rename-log.txt"
Add-Content -Path $log -Value "# NameEpisodes $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  Index=$Index Split=$($Split.IsPresent)"

Write-Host ""
Write-Host "--- applying ---"
foreach ($item in $actions) {
    if (-not (Test-Path $extraDir) -and $item.Target -like "$extraDir*") {
        New-Item -ItemType Directory -Path $extraDir | Out-Null
    }

    if ($item.Kind -eq "PlayAll" -and $Split -and $item.SplitAt) {
        $stem = Join-Path $SeasonDir ("$($item.File.BaseName)_part.mkv")
        & $MkvMerge_Exe -o "$stem" --split "chapters:$($item.SplitAt -join ',')" "$($item.File.FullName)" |
            ForEach-Object { Write-Host "   $_" }

        if ($LASTEXITCODE -gt 1) {
            Write-Host " mkvmerge failed (exit $LASTEXITCODE) on $($item.File.Name) - leaving it alone."
            continue
        }

        $parts = @(Get-ChildItem -Path $SeasonDir -Filter "$($item.File.BaseName)_part-*.mkv" -File | Sort-Object Name)
        if ($parts.Count -ne $item.Episodes.Count) {
            Write-Host (" expected {0} parts, got {1} - leaving them as {2}_part-*.mkv for you to check." -f `
                $item.Episodes.Count, $parts.Count, $item.File.BaseName)
            continue
        }

        for ($i = 0; $i -lt $parts.Count; $i++) {
            $epName = "E{0:D2}.mkv" -f $item.Episodes[$i]
            $epPath = Join-Path $SeasonDir $epName
            if (Test-Path -LiteralPath $epPath) {
                # That episode already exists on its own - this piece is a copy.
                $spare = Join-Path $extraDir ("{0}_from_{1}" -f $epName, $item.File.Name)
                Move-Item -LiteralPath $parts[$i].FullName -Destination $spare
                Add-Content -Path $log -Value "$($item.File.Name) part $($i+1) -> _extra\$(Split-Path $spare -Leaf) (E$('{0:D2}' -f $item.Episodes[$i]) already existed)"
                Write-Host ("   part {0} -> _extra\{1}" -f ($i + 1), (Split-Path $spare -Leaf))
            } else {
                Move-Item -LiteralPath $parts[$i].FullName -Destination $epPath
                Add-Content -Path $log -Value "$($item.File.Name) part $($i+1) -> $epName"
                Write-Host ("   part {0} -> {1}" -f ($i + 1), $epName)
            }
        }

        Move-Item -LiteralPath $item.File.FullName -Destination $item.Target
        Add-Content -Path $log -Value "$($item.File.Name) -> _extra\$(Split-Path $item.Target -Leaf)"
        Write-Host (" {0} -> _extra\{1}" -f $item.File.Name, (Split-Path $item.Target -Leaf))
        continue
    }

    Move-Item -LiteralPath $item.File.FullName -Destination $item.Target
    Add-Content -Path $log -Value "$($item.File.Name) -> $($item.Target.Substring($SeasonDir.Length + 1))"
    Write-Host (" {0,-16} -> {1}" -f $item.File.Name, $item.Target.Substring($SeasonDir.Length + 1))
}

Write-Host ""
Write-Host "Log: $log"
