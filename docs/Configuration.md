# Configuration

This file is the one home for the config keys. `Scripts/config.example.json`
is a copyable starting point, and each script carries the same defaults in its
own `Get-RipConfig` hashtable — when they disagree, this table is what needs
fixing.

## config.json

Defaults live in each script and point at the usual install paths and
`I:\Video`. To override anything (drive letter, tool paths, video folder,
etc.) without editing the scripts:

```powershell
Copy-Item Scripts\config.example.json Scripts\config.json
```

Edit `Scripts\config.json` and change only the keys you need — anything you
leave out keeps its script default. `config.json` is gitignored (it's
machine-specific), so this never gets committed. Keys a script doesn't know
are ignored, so one `config.json` serves the whole pipeline.

`config.example.json` carries all of these except `TmdbApiKeyFile` (add that
one only if you keep the key somewhere else, as an absolute path), and has
`MinLengthSeconds` already lowered to `3000`.

| Key | Default | What it does |
|---|---|---|
| `VideoRoot` | `I:\Video` | Raw rips land in a subfolder here; converted files are written flat in it |
| `DriveLetter` | `J:` | The disc drive `RipDisc.ps1` reads |
| `MinLengthSeconds` | `3600` | MakeMKV `--minlength`. Drop to ~`1200` for TV, or 47-minute episodes are skipped |
| `MakeMKV_Exe` | `…\MakeMKV\makemkvcon64.exe` | Ripper |
| `HandBrake_Exe` | `…\HandBrake\HandBrakeCLI.exe` | H.265 encoder |
| `Seconv_Exe` | `…\Subtitle Edit\seconv.exe` | Subtitle OCR CLI |
| `MkvMerge_Exe` | `…\MKVToolNix\mkvmerge.exe` | Remux, and the chapter split in `NameEpisodes.ps1` |
| `MkvExtract_Exe` | `…\MKVToolNix\mkvextract.exe` | Reads chapter marks for `NameEpisodes.ps1` |
| `MkvPropEdit_Exe` | `…\MKVToolNix\mkvpropedit.exe` | Attaches the poster |
| `TesseractDir` | `…\Tesseract-OCR` | Added to `PATH` so `seconv` can shell out to it |
| `TmdbApiKeyFile` | `Scripts\tmdb_api_key.txt` | Where the TMDb key is read from (absolute path if you move it) |
| `StableSeconds` | `30` | Ignore files written more recently than this — a rip still running |
| `DefaultOcrLanguage` | `fin` | OCR language for a subtitle track tagged `und` or nothing |
| `AudioLanguages` | `fin,eng,jpn` | HandBrake `--audio-lang-list` |
| `SubtitleLanguages` | `fin,eng` | HandBrake `--subtitle-lang-list` |
| `MinEpisodeSeconds` | `900` | `NameEpisodes.ps1`: shorter than this is not an episode |
| `MaxEpisodeSeconds` | `6000` | `NameEpisodes.ps1`: longer than this is a Play All, not an episode |
| `MultiEpisodeRatio` | `1.8` | `NameEpisodes.ps1`: this many times the folder's median episode (or that fraction of it) is reported rather than numbered |
| `DurationToleranceSeconds` | `3` | `NameEpisodes.ps1`: how far two durations may differ and still count as equal |

## The TMDb API key

1. Create a free account at [themoviedb.org](https://www.themoviedb.org/).
2. Go to **Settings → API**
   ([themoviedb.org/settings/api](https://www.themoviedb.org/settings/api))
   and request a free API key (choose "Developer" use).
3. Save the key as plain text in `Scripts/tmdb_api_key.txt` (just the key,
   nothing else). This file is gitignored — never commit it.

Posters are best-effort: if the key is missing, `ConvertNext.ps1` still runs,
it just skips the poster step.

## How the loader works

Each script defines its own defaults as a hashtable and calls `Get-RipConfig`
with them. If `config.json` exists next to the scripts, matching keys there
override the defaults; anything `config.json` doesn't mention keeps its
default. `config.json` is optional - skip it and everything just uses defaults
as before.

`config.json` is shared across all scripts, so it can hold keys a given script
doesn't use (e.g. `RipDisc.ps1` ignores `ConvertNext.ps1`'s keys) - that's
expected, not an error.
