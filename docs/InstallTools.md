# InstallTools.ps1

Installs everything the pipeline needs via winget, in one go. The flags are
documented in the script: `Get-Help .\Scripts\InstallTools.ps1 -Full`.

```powershell
.\Scripts\InstallTools.ps1
```

Skips anything already installed. Flags to skip individual tools:
`-SkipMakeMKV`, `-SkipHandBrake`, `-SkipMkvToolNix`, `-SkipSubtitleEdit`,
`-SkipTesseract`.

Installs (skipping any that's already present at its expected path):

- MakeMKV — `RipDisc.ps1`
- HandBrakeCLI — `ConvertNext.ps1`, encode
- MKVToolNix — `ConvertNext.ps1`/`FixPosters.ps1`, mkvmerge/mkvpropedit
- Subtitle Edit — `ConvertNext.ps1`, seconv.exe OCR CLI
- Tesseract OCR — `ConvertNext.ps1`, the OCR engine seconv shells out to

## The Subtitle Edit version trap

Winget's Subtitle Edit package can lag behind the 5.4.0-beta5+ needed for
`seconv.exe` to exist. This script checks for `seconv.exe` afterwards and
tells you to grab a newer installer manually from
[nikse.dk](https://www.nikse.dk/subtitleedit) if it's missing.

## Installing manually instead

| Tool | Used for | Install |
|---|---|---|
| [MakeMKV](https://www.makemkv.com/) | Ripping the disc | Download installer from makemkv.com |
| [HandBrakeCLI](https://handbrake.fr/downloads2.php) | H.265 encode | `winget install HandBrake.HandBrake.CLI` |
| [MKVToolNix](https://mkvtoolnix.download/) | `mkvmerge`/`mkvpropedit` (remux subs, attach poster) | `winget install MoritzBunkus.MKVToolNix` |
| [Subtitle Edit](https://www.nikse.dk/subtitleedit) 5.4+ | `seconv.exe` CLI, OCRs bitmap (VobSub) subtitles | Download installer from nikse.dk (ships `seconv.exe` alongside the GUI from v5.4.0-beta5 on) |
| [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) | OCR engine `seconv` shells out to | `winget install tesseract-ocr.tesseract` |

After installing, confirm the exe paths match what's in
[`Scripts/config.example.json`](../Scripts/config.example.json) — if any tool
installed somewhere else, override it in your own `config.json`
(see [Configuration.md](Configuration.md)).
