# ConvertNext.ps1

Encodes any raw rip not yet converted, OCRs its subtitles, and attaches a
TMDb poster. The flags are documented in the script:
`Get-Help .\Scripts\ConvertNext.ps1 -Full`.

```powershell
.\Scripts\ConvertNext.ps1
```

Scans `I:\Video` for subfolders (raw rips from MakeMKV). For every `*.mkv` in
those subfolders that hasn't been converted yet:

1. Encodes it to H.265 with HandBrakeCLI, dropped as a flat file directly in
   `I:\Video` (bitmap VobSub subtitles are copied through as-is for now).
2. OCRs each VobSub subtitle track on the RAW file via `seconv.exe` (Subtitle
   Edit's CLI, tesseract engine) to SRT.
3. Remuxes those SRTs into the H.265 output with mkvmerge, alongside the
   original bitmap subtitle tracks (nothing is dropped; see
   `-ReplaceBitmapSubs` to change that).

Raw files are never touched or deleted - clean them up manually once you've
checked the output.

## Output naming

A raw folder is normally a movie, and the output is named after the folder
(`Kiki.mkv`, or `Kiki - C1_t01.mkv` when the folder holds several files). A
folder named `<Show>_S<season>` is a TV season instead: files in it called
`E01.mkv`, `E02.mkv`, ... come out as `<Show> - S01E01.mkv`, which
Plex/Jellyfin parse. A file holding several episodes (a DVD "Play All" title)
is named for its range, `E01-E03.mkv` -> `<Show> - S01E01-E03.mkv`, which Plex
reads as all three. `RipDisc.ps1 -Title The_Crown_S01 -Index 1` is what
produces such a folder; see `Get-SeriesInfo` in `Config.ps1`.

## The .converted marker

"Already converted" is tracked with a sidecar marker file next to each raw
file: `<file>.mkv.converted`. That survives reruns and doesn't care whether a
flat output file of a similar name already exists.

## Console output and the log

Between them HandBrake, seconv and mkvmerge print a few hundred lines per
file, so that goes to a log beside the raw file — `E02.mkv.log`, appended to,
one block per tool per run — and the console gets one line per step, with the
encode percentage rewriting itself in place:

```
 Downton_Abbey_S06\E02.mkv -> Downton Abbey - S06E02.mkv
   encode  18m04s, 1,80 GB -> 0,74 GB
   subs    2 of 2 tracks OCR'd and remuxed, bitmap subs kept too
   poster  poster.jpg attached
   done    I:\Video\Downton Abbey - S06E02.mkv
```

A step that fails prints the tail of the log with it. `-ShowToolOutput`
streams everything to the console as well, as earlier versions did.

## Subtitles

OCR covers the languages in `SubtitleLanguages` — the same ones HandBrake
keeps, since an SRT for a track that isn't in the output is just a slow way to
produce nothing. Each needs its Tesseract data file: with only
`eng.traineddata` and `fin.traineddata` installed, `seconv` cannot address a
Danish or Dutch track at all (it reports "No subtitle tracks matched", which
says nothing about the real cause), so the script checks for the file first
and names what's missing.

By default the OCR'd SRT tracks are added *alongside* the original bitmap
(VobSub) ones, so nothing is lost; `-ReplaceBitmapSubs` drops the bitmaps and
keeps the text.

## Posters

If a `.jpg`/`.jpeg`/`.png` is sitting in the raw disc folder, that wins and
gets used as-is (drop one there by hand to fix a bad TMDb guess up front, or
see [FetchPosterPreview.ps1](FetchPosterPreview.md)). Otherwise it's fetched
from TMDb - the tv endpoint for a season folder, cached as `poster.jpg` in the
raw folder so every episode of that season reuses one lookup, the movie
endpoint for anything else. TMDb needs a free API key saved as plain text in
`tmdb_api_key.txt` next to the scripts
(https://www.themoviedb.org/settings/api; see
[Configuration.md](Configuration.md)).

Either way, the movie gets a sidecar image next to its mkv AND an embedded
cover attachment in the mkv itself (via mkvpropedit) - best-effort, never
blocks the rest of the pipeline on failure. Windows Explorer reads neither;
see [tasks/first-frame.md](tasks/first-frame.md) for why that was left alone.

`-Title` only applies to `-FetchPoster` — it is the TMDb search term, for when
the folder name isn't the film's title. In a normal convert run the folder
name is used.

## Requires

- HandBrakeCLI, MKVToolNix (mkvmerge) - already in use by this pipeline
- Subtitle Edit 5.4+ with `seconv.exe` (ships as a separate CLI alongside the
  GUI install as of v5.4.0-beta5)
- Tesseract OCR on PATH (`winget install tesseract-ocr.tesseract`) - seconv's
  tesseract engine shells out to `tesseract.exe`

[InstallTools.ps1](InstallTools.md) installs the lot.
