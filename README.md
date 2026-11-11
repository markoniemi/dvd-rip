# dvd-rip

Rips DVDs/Blu-rays, encodes to H.265, OCRs subtitles, and tags the result
with a TMDb poster. PowerShell scripts, Windows only.

Pipeline: `RipDisc.ps1` (disc → raw mkv) → `ConvertNext.ps1` (raw mkv →
H.265 + OCR'd subs + poster). `FixPosters.ps1` re-applies posters to
already-converted files afterwards.

## Setting up

1. **Install the tools** — `.\Scripts\InstallTools.ps1` does the lot via
   winget. See [docs/InstallTools.md](docs/InstallTools.md) for the tool
   list, the manual installs, and the Subtitle Edit version trap.
2. **Get a TMDb API key** and save it in `Scripts/tmdb_api_key.txt` — see
   [docs/Configuration.md](docs/Configuration.md). Posters are best-effort:
   without the key everything else still runs.
3. **Configure, optionally** — copy `Scripts\config.example.json` to
   `Scripts\config.json` and change only what you need. Every key is in
   [docs/Configuration.md](docs/Configuration.md).

## The scripts

Every script documents its own flags. `Get-Help .\Scripts\<name>.ps1 -Full`
is the reference; the markdown beside it is the why.

| Script | What it does | Notes |
|---|---|---|
| [`RipDisc.ps1`](docs/RipDisc.md) | Disc → raw mkv, with MakeMKV | Title order is not episode order |
| [`NameEpisodes.ps1`](docs/NameEpisodes.md) | Names a season's titles `E01.mkv`… by arithmetic | Dry run by default |
| [`ConvertNext.ps1`](docs/ConvertNext.md) | Raw mkv → H.265, OCR'd subs, poster | The main workhorse |
| [`FetchPosterPreview.ps1`](docs/FetchPosterPreview.md) | Pulls a candidate poster into each raw folder | Check it before converting |
| [`FixPosters.ps1`](docs/FixPosters.md) | Re-applies posters to converted files | Never fetches from TMDb |
| [`InstallTools.ps1`](docs/InstallTools.md) | Installs the five tools via winget | Skips what's there |
| `Config.ps1` | Shared config loader, dot-sourced | [docs/Configuration.md](docs/Configuration.md) |
| `Test-Docs.ps1` | Checks this documentation holds together | Run it after editing docs |

## A typical session

Rip a film, then convert it:

```powershell
.\Scripts\RipDisc.ps1 -Title Kikis_Delivery_Service
.\Scripts\ConvertNext.ps1
```

A season, one disc at a time — rip, check the names, convert:

```powershell
.\Scripts\RipDisc.ps1 -Title The_Crown_S01 -Index 1   # disc 1
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01              # dry run, read it
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Execute     # apply
.\Scripts\ConvertNext.ps1 -Watch
```

Before ripping a series, lower `MinLengthSeconds` to about `1200` in
`config.json` — at the default `3600` a 47-minute episode is skipped.

## Documentation

The `docs/` folder holds one markdown file per script, named after it, plus
[docs/Configuration.md](docs/Configuration.md) for the config keys and
[docs/tasks/](docs/tasks/) for the backlog. `Scripts/Test-Docs.ps1` checks
that every script with parameters has comment-based help covering each one, a
markdown file of its own, and no broken relative links.
