# RipDisc.ps1

Rips the main feature(s) with MakeMKV into a new subfolder under `I:\Video`,
named after the disc label. The flags are documented in the script:
`Get-Help .\Scripts\RipDisc.ps1 -Full`.

Disc labels are often useless (`G7_67158D1`), so name the folder yourself:

```powershell
.\Scripts\RipDisc.ps1 -Title Kikis_Delivery_Service
```

## TV series

A folder named `<Show>_S<season>` holds a whole season, and `-Index` is the
first episode number on the disc in the drive:

```powershell
.\Scripts\RipDisc.ps1 -Title The_Crown_S01 -Index 1   # disc 1 -> E01.mkv, E02.mkv
.\Scripts\RipDisc.ps1 -Title The_Crown_S01 -Index 3   # disc 2 -> E03.mkv, E04.mkv
```

With `-Title` an existing folder is reused, so every disc of the season lands
in one folder; without it, a timestamp suffix keeps earlier rips intact.
`ConvertNext.ps1` turns `The_Crown_S01\E05.mkv` into
`The Crown - S01E05.mkv`, which Plex/Jellyfin parse (see `Get-SeriesInfo` in
`Config.ps1`).

## Why the _rip subfolder exists

MakeMKV names its files after the disc volume label (`C1_t00.mkv`), and discs
of one season often carry the *same* label, so disc 2 would otherwise write
over disc 1. Each rip therefore lands in a `_rip` subfolder first and is moved
up afterwards (a rename, not a copy); a name already taken gets a disc
counter, `C1_d2_t00.mkv`. Nothing is overwritten, and only this disc's files
are renamed by `-Index`, so unrenamed titles from an earlier disc are left
where they are. Both `_rip` and the counter are invisible to the rest of the
pipeline.

## Title order is not episode order

`-Index` numbers the files in MakeMKV title order, which is *usually* episode
order — a "Play All" title or a bonus feature longer than `MinLengthSeconds`
shifts everything by one. Every rip appends the disc's title table (duration,
chapter count, source VOB, and whether `--minlength` keeps it) to `titles.txt`
in the output folder; check it against the renames the script prints before
converting. If `-Index` was wrong, rename the files by hand — the episode
number lives in the raw file name, so `ConvertNext.ps1` picks up the
correction. A "Play All" title that holds several episodes can be kept whole
and named for its range instead: `E01-E03.mkv`.

[NameEpisodes.ps1](NameEpisodes.md) does this by arithmetic rather than by
title order, and is the better tool once a disc is ripped.

Note that `MinLengthSeconds` (3000 in `config.example.json`, 3600 by default)
drops TV episodes — a 47-minute episode is only 2820 s. Lower it in
`config.json` to about `1200` before ripping a series, and check `titles.txt`
to see what that lets through. See [Configuration.md](Configuration.md).
