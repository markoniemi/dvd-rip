---
id: simplify-scripts
status: in_progress
priority: low
kind: task
branch: task/simplify-scripts
---

# simplify scripts

- suggest how to simplify scripts
- what features can be dropped?
- is there an optional feature that would remove much code from scripts?
- poster image feature can be dropped.

# Implementation Plan

## What the scripts weigh now

2276 lines across seven scripts, after the `documentation` task moved the
prose out:

| Script | Lines |
| :- | -: |
| `NameEpisodes.ps1` | 973 |
| `ConvertNext.ps1` | 585 |
| `RipDisc.ps1` | 235 |
| `FixPosters.ps1` | 136 |
| `FetchPosterPreview.ps1` | 121 |
| `Test-Docs.ps1` | 105 |
| `InstallTools.ps1` | 90 |
| `Config.ps1` | 65 |

## Step 1 — drop the poster feature

Decided already ("poster image feature can be dropped"), and it is the one
change that removes a fifth of the code:

| Goes | Lines |
| :- | -: |
| `FixPosters.ps1`, whole script | 136 |
| `FetchPosterPreview.ps1`, whole script | 121 |
| `ConvertNext.ps1`: `Get-MovieTitleGuess` … `Add-PosterArt` | 161 |
| `ConvertNext.ps1`: the `-FetchPoster` branch | 34 |
| Parameters `-SkipPoster`, `-FetchPoster`, `-Title`, their call sites | ~15 |
| **Total** | **~470, a fifth of the code, and 7 scripts become 5** |

Also gone with it: the TMDb API key (`tmdb_api_key.txt`,
`TmdbApiKeyFile`), the `MkvPropEdit_Exe` config key — nothing else uses
mkvpropedit — `docs/FixPosters.md`, `docs/FetchPosterPreview.md`, the
poster section of `docs/ConvertNext.md`, two rows of the README table and
two rows of `docs/Configuration.md`. MKVToolNix stays installed for
mkvmerge, so `InstallTools.ps1` does not change.

Worth saying plainly, because it is the argument for dropping it rather
than a consolation: Plex and Jellyfin fetch their own artwork from their
own metadata agents, so the embedded cover was mostly for everything
*else* — and the `first frame` task established that Windows Explorer
ignores both the attachment and the sidecar jpg. The library already
converted keeps every cover it has; this only stops new ones being made.

What is genuinely lost: `FixPosters.ps1` is the only way to push a
hand-picked image onto an already-converted file. If a cover is ever wrong
again, it is a mkvpropedit command by hand (it is in `git log`) or the
media server's own artwork picker.

## Step 2 — other optional features, to decide (open question 1)

Measured candidates, biggest first. None of these is decided:

| Feature | Lines | Case for dropping | Case for keeping |
| :- | -: | :- | :- |
| `-Split` / `-SplitAt` in `NameEpisodes.ps1` (`Get-SplitOverrides`, `Set-ExplicitSplit`, `Get-RangeSplit` and their callers) | ~150 | The biggest single block left after posters | It is what Downton Abbey S04 needed; a range-named file is otherwise handled by hand in mkvmerge |
| `-Watch` / `-PollSeconds` polling loop in `ConvertNext.ps1` | ~40 | Rerunning the script is the same thing | Convenient while a long rip session runs |
| `-RedoSubtitles` | ~45 | Redo = delete the `.converted` marker and rerun, if the output file is also removed | Avoids a re-encode, which is the expensive part |
| `-MarkDone` | ~20 | Backfilling pre-existing folders was a one-off | Still the only way to adopt a folder without encoding |
| `-ShowToolOutput` and the per-file log | ~60 | — | Load-bearing: without the log a failing encode says nothing. Not a candidate |

## Step 3 — simplify what stays, without dropping features

1. **Config unpacking.** Every script does `$cfg = Get-RipConfig @{...}`
   and then copies each key into its own variable, 8–10 lines a script, ~45
   lines in all. A `Set-RipConfigVariables` helper in `Config.ps1`, or just
   using `$cfg.VideoRoot` at the three or four places that need it, removes
   the copying.
2. **Duplicated naming helpers.** `FixPosters.ps1` carries its own copy of
   `Get-MarkerPath` and the output-naming rule with a comment saying to
   keep it in sync with `ConvertNext.ps1`. Step 1 deletes that file and the
   problem with it — but the same rule should move to `Config.ps1` so the
   next script cannot repeat it.
3. **`NameEpisodes.ps1`'s main body** is ~500 straight-line lines after the
   last function. Splitting it into named passes (read facts → classify →
   plan renames → report/apply) is the one structural change that would
   make the file readable, and it is also the riskiest thing in this task:
   it is the script with the most subtle arithmetic and no tests.

## Step 4 — keep the documentation true

`Scripts/Test-Docs.ps1` enforces it and must pass at every commit: a
deleted script's `docs/<Script>.md` has to go with it, and the README
table, `docs/Configuration.md` and `docs/ConvertNext.md` lose their poster
rows and sections. The check catches the dangling links but not the stale
prose, so that part is read by eye.

## Order, and what "done" looks like

Step 1 first, in its own commit, since it is decided and it changes what
Step 2 and 3 are even looking at. Then whichever of Step 2 the human
picks, one commit each. Step 3.3 last, or in a task of its own.

Tests: there is no test harness beyond `Test-Docs.ps1`, and this task
deletes code rather than adding it. The honest check is that
`ConvertNext.ps1` still converts one real file end to end after Step 1 —
which needs a raw rip folder to run against, and so is a step for the
human or for a disc left in the drive.

## Answers

Decided by the human:

* **Drop** the poster feature (Step 1), and from Step 2 **`-RedoSubtitles`,
  `-MarkDone` and `-Split`/`-SplitAt`**.
* **Keep** `-Watch`/`-PollSeconds`, and the log with `-ShowToolOutput`.
* `NameEpisodes.ps1`'s main body (Step 3.3) is **out of scope**: it became
  the backlog entry `restructure NameEpisodes`, so my recommendation to
  keep `-Split` was overruled and that is the decision.
* Nothing is done about the posters already on disk — every converted file
  keeps its cover and its sidecar jpg.

Note on dropping `-Split`: the chapter arithmetic that *classifies* a Play
All stays, because that is how a title is recognised at all. Only the
cutting goes, so a range-named file is reported and left whole, which is
what it did before `-Split` existed. `ConvertNext.ps1` still names it
`<Show> - S01E01-E03.mkv`.
