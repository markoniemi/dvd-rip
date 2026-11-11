# FetchPosterPreview.ps1

Fetch a candidate TMDb poster into each raw disc folder that doesn't already
have one, for review before it gets baked into the mkv. The flags are
documented in the script:
`Get-Help .\Scripts\FetchPosterPreview.ps1 -Full`.

ConvertNext.ps1 uses a jpg/png already sitting in the raw disc folder as the
poster instead of asking TMDb (see [ConvertNext.md](ConvertNext.md)). This
script is how you get a candidate image into those folders so you can look at
it - and swap it for a different file, or delete it - before running
ConvertNext.ps1.

Scans every raw folder under VideoRoot and skips any that already has a
jpg/jpeg/png in it (whether from a previous run of this script or dropped in
by hand) - it never overwrites an existing candidate.

A `<Show>_S<season>` folder (see `Get-SeriesInfo` in `Config.ps1`) is searched
on TMDb's tv endpoint under the show name - one `poster.jpg` for the whole
season, which every episode of it then reuses.

Requires the same `tmdb_api_key.txt` next to the scripts as the other scripts
(see [Configuration.md](Configuration.md)).
