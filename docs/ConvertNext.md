# ConvertNext.ps1

Encodes any raw rip not yet converted and OCRs its subtitles. The flags are
documented in the script:
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

There is no flag for writing one by hand any more (`-MarkDone` went in the
`simplify scripts` task). A run that finds the output file already there
marks the raw file converted and moves on, which covers the same ground; to
force it, create the `.converted` file yourself, and to redo a file, delete
both it and the output.

## Console output and the log

Between them HandBrake, seconv and mkvmerge print a few hundred lines per
file, so that goes to a log beside the raw file — `E02.mkv.log`, appended to,
one block per tool per run — and the console gets one line per step (there
used to be a `poster` line too), with the encode percentage rewriting itself
in place:

```
 Downton_Abbey_S06\E02.mkv -> Downton Abbey - S06E02.mkv
   encode  18m04s, 1,80 GB -> 0,74 GB
   subs    2 of 2 tracks OCR'd and remuxed, bitmap subs kept too
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

Redoing the OCR on a file that is already converted has no flag of its own
either (`-RedoSubtitles` went the same way): delete the output file and the
raw file's `.converted` marker, and the next run does the whole file again,
encode included.

## Posters

There are none. The script used to fetch a TMDb poster, write it beside the
mkv and attach it as the mkv's cover; that went in the `simplify scripts`
task, along with `FetchPosterPreview.ps1` and `FixPosters.ps1`. Plex and
Jellyfin fetch their own artwork, and Windows Explorer never read the
attachment or the sidecar jpg anyway (see
[tasks/first-frame.md](tasks/first-frame.md)).

Files converted before that keep the cover and the sidecar jpg they already
have. `git log` has the code if it is ever wanted back.

## Requires

- HandBrakeCLI, MKVToolNix (mkvmerge) - already in use by this pipeline
- Subtitle Edit 5.4+ with `seconv.exe` (ships as a separate CLI alongside the
  GUI install as of v5.4.0-beta5)
- Tesseract OCR on PATH (`winget install tesseract-ocr.tesseract`) - seconv's
  tesseract engine shells out to `tesseract.exe`

[InstallTools.ps1](InstallTools.md) installs the lot.
