# FixPosters.ps1

Re-apply poster images from raw disc folders onto already-converted mkv
files. The flags are documented in the script:
`Get-Help .\Scripts\FixPosters.ps1 -Full`.

ConvertNext.ps1 bakes the poster in at conversion time. This script redoes
that step on demand, from whatever image is sitting in the raw disc folder
right now - so to fix a wrong cover you drop a better jpg/png into the raw
folder (replacing the old one) and rerun this.

For every raw `*.mkv` that is marked converted (`<file>.mkv.converted`) and
whose converted output exists, it:

1. copies the raw folder's jpg/jpeg/png next to the converted mkv, named
   after it (`<mkv basename>.<ext>`),
2. re-attaches it as the mkv's `cover.<ext>` attachment, replacing any
   previous cover.

Raw folders with no image, raw files not yet converted, and raw files whose
converted output is missing are skipped - nothing is fetched from TMDb here
(use [FetchPosterPreview.ps1](FetchPosterPreview.md) for that).
