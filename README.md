# dvd-rip

Rips DVDs/Blu-rays, encodes to H.265, OCRs subtitles, and tags the result
with a TMDb poster. PowerShell scripts, Windows only.

Pipeline: `RipDisc.ps1` (disc → raw mkv) → `ConvertNext.ps1` (raw mkv →
H.265 + OCR'd subs + poster). `FixPosters.ps1` re-applies posters to
already-converted files afterwards.

## 1. Install required tools

Run this to install everything via winget in one go:

```bash
.\Scripts\InstallTools.ps1
```

Skips anything already installed. Flags to skip individual tools:
`-SkipMakeMKV`, `-SkipHandBrake`, `-SkipMkvToolNix`, `-SkipSubtitleEdit`,
`-SkipTesseract`. It warns if Subtitle Edit's winget build is older than
5.4.0-beta5 (needed for `seconv.exe`) — if so, grab a newer installer
manually from [nikse.dk](https://www.nikse.dk/subtitleedit).

Or install manually:

| Tool | Used for | Install |
|---|---|---|
| [MakeMKV](https://www.makemkv.com/) | Ripping the disc | Download installer from makemkv.com |
| [HandBrakeCLI](https://handbrake.fr/downloads2.php) | H.265 encode | `winget install HandBrake.HandBrake.CLI` |
| [MKVToolNix](https://mkvtoolnix.download/) | `mkvmerge`/`mkvpropedit` (remux subs, attach poster) | `winget install MoritzBunkus.MKVToolNix` |
| [Subtitle Edit](https://www.nikse.dk/subtitleedit) 5.4+ | `seconv.exe` CLI, OCRs bitmap (VobSub) subtitles | Download installer from nikse.dk (ships `seconv.exe` alongside the GUI from v5.4.0-beta5 on) |
| [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) | OCR engine `seconv` shells out to | `winget install tesseract-ocr.tesseract` |

After installing, confirm the exe paths match what's in
[`Scripts/config.example.json`](Scripts/config.example.json) — if any tool
installed somewhere else, override it in your own `config.json` (see
step 3).

## 2. Get a TMDb API key

1. Create a free account at [themoviedb.org](https://www.themoviedb.org/).
2. Go to **Settings → API** ([themoviedb.org/settings/api](https://www.themoviedb.org/settings/api)) and request a free API key (choose "Developer" use).
3. Save the key as plain text in `Scripts/tmdb_api_key.txt` (just the key, nothing else). This file is gitignored — never commit it.

Posters are best-effort: if the key is missing, `ConvertNext.ps1` still
runs, it just skips the poster step.

## 3. Configure (optional)

Defaults live in each script and point at the usual install paths and
`I:\Video`. To override anything (drive letter, tool paths, video folder,
etc.) without editing the scripts:

```bash
Copy-Item Scripts\config.example.json Scripts\config.json
```

Edit `Scripts\config.json` and change only the keys you need — anything
you leave out keeps its script default. `config.json` is gitignored (it's
machine-specific), so this never gets committed.

## 4. Running the scripts

**Rip a disc** — put the disc in the drive, then:

```bash
.\Scripts\RipDisc.ps1
```

Rips the main feature(s) with MakeMKV into a new subfolder under
`I:\Video`, named after the disc label.

Disc labels are often useless (`G7_67158D1`), so name the folder yourself:

```bash
.\Scripts\RipDisc.ps1 -Title Kikis_Delivery_Service
```

**TV series** — a folder named `<Show>_S<season>` holds a whole season, and
`-Index` is the first episode number on the disc in the drive:

```bash
.\Scripts\RipDisc.ps1 -Title The_Crown_S01 -Index 1   # disc 1 -> E01.mkv, E02.mkv
.\Scripts\RipDisc.ps1 -Title The_Crown_S01 -Index 3   # disc 2 -> E03.mkv, E04.mkv
```

With `-Title` an existing folder is reused, so every disc of the season
lands in one folder; without it, a timestamp suffix keeps earlier rips
intact. `ConvertNext.ps1` turns `The_Crown_S01\E05.mkv` into
`The Crown - S01E05.mkv`, which Plex/Jellyfin parse.

MakeMKV names its files after the disc volume label (`C1_t00.mkv`), and
discs of one season often carry the *same* label, so disc 2 would
otherwise write over disc 1. Each rip therefore lands in a `_rip`
subfolder first and is moved up afterwards (a rename, not a copy); a name
already taken gets a disc counter, `C1_d2_t00.mkv`. Nothing is
overwritten, and only this disc's files are renamed by `-Index`, so
unrenamed titles from an earlier disc are left where they are. Both
`_rip` and the counter are invisible to the rest of the pipeline.

`-Index` numbers the files in MakeMKV title order, which is *usually*
episode order — a "Play All" title or a bonus feature longer than
`MinLengthSeconds` shifts everything by one. Every rip appends the disc's
title table (duration, chapter count, source VOB, and whether
`--minlength` keeps it) to `titles.txt` in the output folder; check it
against the renames the script prints before converting. If `-Index` was
wrong, rename the files by hand — the episode number lives in the raw
file name, so `ConvertNext.ps1` picks up the correction. A "Play All"
title that holds several episodes can be kept whole and named for its
range instead: `E01-E03.mkv`.

Note that `MinLengthSeconds` (3000 in `config.example.json`, 3600 by
default) drops TV episodes — a 47-minute episode is only 2820 s. Lower it
in `config.json` to about `1200` before ripping a series, and check
`titles.txt` to see what that lets through.

**Name a season's titles by arithmetic** — rather than trusting title
order, `NameEpisodes.ps1` reads durations and chapter marks out of the
files and works out what each one is:

```bash
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01                  # dry run
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Execute         # apply
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Split -Execute  # cut Play Alls up
```

It numbers what's left over, continuing from the highest `E##` already in
the folder, and sets aside what isn't an episode: a title ripped twice, a
Play All whose episodes all exist on their own, a standalone episode that a
Play All also holds (that file keeps the number, the Play All's copy of it
goes to `_extra\`). Episode numbers are only assigned where the arithmetic
is decisive. A file far longer than the episodes around it — a Christmas
special, or two episodes no rule could separate — is reported and left
alone rather than numbered. Rename it `E09.mkv` or `E07-E08.mkv` by hand
and the next run takes that as given. Nothing is ever deleted, every move
goes to `rename-log.txt`, and dry run is the default.

Run it per disc rather than once at the end of a season: title order is
only meaningful within one disc.

**Convert pending rips** — encodes any raw rip not yet converted, OCRs its
subtitles, and attaches a TMDb poster:

```bash
.\Scripts\ConvertNext.ps1
```

Output is named after the raw folder (`Kiki.mkv`, or `Kiki - C1_t01.mkv`
when the folder holds several files). A `<Show>_S<season>` folder is
treated as a TV season instead: `E01.mkv` in it comes out as
`<Show> - S01E01.mkv`. A file holding several episodes — a DVD "Play All"
title — is named for its range, `E01-E03.mkv` →
`<Show> - S01E01-E03.mkv`, which Plex reads as all three. The poster comes
from TMDb's tv endpoint —
fetched once per season, cached as `poster.jpg` in the raw folder so every
episode reuses it.

Useful flags:

```bash
.\Scripts\ConvertNext.ps1 -Watch                # keep polling for new raw folders
.\Scripts\ConvertNext.ps1 -Only "Kiki"          # restrict to one raw subfolder
.\Scripts\ConvertNext.ps1 -SkipSubtitles        # H.265 encode only, no OCR
.\Scripts\ConvertNext.ps1 -SkipPoster           # don't fetch/attach a poster
.\Scripts\ConvertNext.ps1 -FetchPoster "Kiki"   # (re)fetch poster only, pass "all" for every converted file
.\Scripts\ConvertNext.ps1 -RedoSubtitles "Kiki" # redo OCR+remux, pass "all" for every converted file
.\Scripts\ConvertNext.ps1 -MarkDone "Kiki"      # mark a folder converted without encoding
```

**Preview posters before converting** — fetch a TMDb candidate into every
raw disc folder that doesn't already have one, so you can check (or swap)
it before `ConvertNext.ps1` bakes it into the mkv (which uses any jpg/png
already sitting there instead of asking TMDb):

```bash
.\Scripts\FetchPosterPreview.ps1                                     # all raw folders missing a poster
.\Scripts\FetchPosterPreview.ps1 -DirName "Kiki"                     # just that one
.\Scripts\FetchPosterPreview.ps1 -DirName "Kiki" -Title "Kiki's Delivery Service"
```

Never overwrites a folder that already has an image. Saves as
`poster.jpg` otherwise. Delete or replace it there if it's wrong —
whatever's left when you run `ConvertNext.ps1` becomes the cover.

**Fix posters** — disc folder names don't always match TMDb's title, so
the auto-guessed poster can be wrong. Drop a better image into the raw
disc folder (replacing the one already there) and re-apply it:

```bash
.\Scripts\FixPosters.ps1                  # every converted file with a poster in its raw folder
.\Scripts\FixPosters.ps1 -DirName "Kiki"  # just that one raw folder
```

Walks every raw folder under `VideoRoot`, and for each raw mkv that is
marked converted and whose converted output exists, copies that folder's
jpg/jpeg/png next to the converted mkv (named after it) and re-attaches it
as the mkv's cover, replacing the old attachment. Raw folders with no
image, files not yet converted, and files whose converted output is
missing are all skipped — nothing is fetched from TMDb here. Accepts
`.jpg`/`.jpeg`/`.png`.
