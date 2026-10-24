# dvd-rip

Rips DVDs/Blu-rays, encodes to H.265, OCRs subtitles, and tags the result
with a TMDb poster. PowerShell scripts, Windows only.

Pipeline: `RipDisc.ps1` (disc → raw mkv) → `ConvertNext.ps1` (raw mkv →
H.265 + OCR'd subs + poster). `FixPoster.ps1` fixes a wrong/missing poster
afterwards.

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
`I:\Video`.

**Convert pending rips** — encodes any raw rip not yet converted, OCRs its
subtitles, and attaches a TMDb poster:

```bash
.\Scripts\ConvertNext.ps1
```

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

**Fix a poster** — disc folder names don't always match TMDb's title, so
the auto-guessed poster can be wrong. Once you have a better image saved
locally (e.g. picked by hand from TMDb):

```bash
.\Scripts\FixPoster.ps1 -MkvPath "I:\Video\Kiki.mkv" -ImagePath "C:\Downloads\poster.jpg"
```

Removes the old cover attachment, copies the given image in as the
sidecar jpg/png, and re-attaches it to the mkv. Accepts `.jpg`/`.jpeg`/`.png`.
