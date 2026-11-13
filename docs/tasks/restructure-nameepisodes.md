---
id: restructure-nameepisodes
status: planned
priority: low
kind: task
branch: task/restructure-nameepisodes
---

# restructure NameEpisodes

Split off from `simplify scripts`, which left it alone deliberately.

`NameEpisodes.ps1` is ~970 lines, of which the last ~500 are one
straight-line main body after the final function. Splitting it into named
passes - read facts, classify, plan renames, report or apply - is what
would make it readable. It is also the riskiest change in the repo: it
holds the duration and chapter arithmetic, and nothing tests it. Worth
considering what a test harness for it would look like first.

# Implementation Plan

## What the file is now

937 lines, in three parts:

| Lines | What |
| -: | :- |
| 48-94 | `param()`, config unpacking, preflight (`exit 1` on a missing exe or folder) |
| 96-380 | 13 helper functions - all pure arithmetic except `Get-MkvFacts`, which shells out to mkvmerge and mkvextract |
| 382-936 | one straight-line main body, ~555 lines, divided by banner comments into **thirteen** unnamed stages |

The thirteen stages, in order, with the names they should get:

| Lines | Stage | Pass |
| -: | :- | :- |
| 384-427 | enumerate, skip files a rip is still writing, read facts | `Read-SeasonItems` |
| 435-457 | trust `E##` / `E##-E##` names, resolve a range into blocks | `Set-KindsFromNames` |
| 466-476 | disprove a single `E##` name that is really a Play All | `Deny-MisnamedSingles` |
| 481-497 | duplicates (same marks, same size) | `Set-DuplicateKinds` |
| 506-514 | Play All rule 1 - holds a run mark for mark | `Set-PlayAllByContainedRun` |
| 518-546 | Play All rule 2 - durations and chapter counts sum | `Set-PlayAllBySums` |
| 552-613 | Play All rule 3 - anchored on another title, remainder divided | `Set-PlayAllByAnchor` |
| 620-636 | a standalone episode equal to one block of a Play All | `Set-EpisodeFromPlayAllBlock` |
| 640-673 | leftovers judged by absolute length and against the median | `Set-KindsByLength` |
| 677-693 | doubts about named singles, said out loud only | `Add-NamedSingleWarnings` |
| 697-755 | assign episode numbers, then Play All spans | `Set-EpisodeNumbers` |
| 763-795 | a late Play All proved from the now-numbered episodes | `Set-PlayAllFromNumbered` |
| 799-830 | targets, including the redundant-Play-All move to `_extra` | `Set-Targets` |
| 834-890 | the `--- titles ---` table, the gap warning, the `--- plan ---` list | `Write-TitleTable`, `Add-GapWarning`, `Write-Plan` |
| 904-936 | blocker check, log, `Move-Item` | `Invoke-Plan` |

So "read facts, classify, plan renames, report or apply" is the right
shape, but the classify step is nine passes, not one, and they are
order-dependent: rule 1 runs before rule 2 *because* a title whose last
chapter mark sits a fraction before its end breaks the chapter-count
arithmetic (the comment at 499-505 is the reason, and Downton Abbey
season 5 is the disc that forced it). The pass order is behaviour and has
to be preserved exactly.

## What stops it being tested today

1. **Config arrives as script-scope variables.** `Test-EpisodeLength`,
   `Test-SameBlock`, `Find-ContainedRun`, `Get-RangeSplit` and
   `Get-MedianEpisodeLength` close over `$MinEpisodeSeconds`,
   `$MaxEpisodeSeconds`, `$MultiEpisodeRatio` and `$Tolerance`. Nothing
   can call them without first reproducing those globals.
2. **The file cannot be dot-sourced at all**: `-DirName` is mandatory and
   the preflight calls `exit`.
3. **The only external I/O in the whole pipeline is `Get-MkvFacts`.**
   Everything downstream reads `Duration`, `Chapters`, `ChapterStart`
   off a plain `pscustomobject`, plus `File.Name`, `.BaseName`,
   `.FullName`, `.Length` and `.LastWriteTime`. That is the seam: a test
   can hand the classifier synthetic facts and never touch a video file.

## Step 1 - snapshot the current behaviour first

Before any edit: run the current script over every folder available (the
real `I:\Video` season folders, and a scratch folder of audio-only cuts
made with mkvmerge, as the `simplify scripts` review used) and keep the
output. Re-run and diff after every step below. Until Step 3 lands this
is the *only* check that covers the arithmetic, and it stays useful
afterwards because it covers the printing and the real file I/O that the
unit tests deliberately do not.

Snapshots live in the scratch folder, not in the repo.

## Step 2 - extract the pure logic into `Scripts/EpisodeLogic.ps1`

Dot-sourced like `Config.ps1`. It takes all 13 helpers except
`Get-MkvFacts`, which stays in `NameEpisodes.ps1` because it is the I/O.

The config closure goes away through one explicit entry point:

```powershell
Initialize-EpisodeRules $cfg    # sets $script:MinEpisodeSeconds, ... inside EpisodeLogic.ps1
```

That keeps all 13 signatures byte-identical - the lowest-risk way to cut
the dependency - and gives the tests one line to set their own
thresholds. The alternative, threading a `$Rules` parameter through every
call site, touches every line of the arithmetic and is exactly what this
task must not do.

`EpisodeLogic.ps1` declares no `param()`, so `Test-Docs.ps1` skips it the
way it skips `Config.ps1` (it `continue`s when a script declares no
parameters) and no `docs/EpisodeLogic.md` is needed.

## Step 3 - the tests, before the body is touched

`Scripts/Test-EpisodeLogic.ps1`, hand-rolled in the shape of
`Test-Docs.ps1`: count the checks, print `FAIL <case>` lines, `exit 1` on
any failure. No `param()`, so no markdown file of its own.

Fixtures are synthetic items from a `New-TestItem -Name -Duration
-Chapters -Marks -Size` helper - no mkv files, no mkvmerge, the suite
runs in about a second. Each case is a real disc already described in the
comments:

| # | Case | Locks in |
| -: | :- | :- |
| 1 | three unnamed 16-min titles, `-Index 7` | `E07`, `E08`, `E09` |
| 2 | 20 chapters as 8+6+6, named `E01-E03` | anchor split at ch 9,15 - *not* the even 8,15 that cuts five minutes into episode two |
| 3 | 7+7+7 marks reading as 19 chapters | rule 1 catches what rule 2 cannot |
| 4 | Play Alls misnamed `E04`, `E08`, `E12` | name disproved, number freed, warning text |
| 5 | same marks and size as a named file | `Duplicate`, the named one wins |
| 6 | standalone episode equal to block 2 of a range-named Play All | `Episode` with *that* number, not a new one |
| 7 | 18 chapters over 2:20 | `Unknown`, "several readings", both options printed |
| 8 | a 1:32 special beside 47-min episodes | `Unknown` via `MultiEpisodeRatio` |
| 9 | a 25-min bonus feature | `Unknown`, the short side of the ratio |
| 10 | a season missing E05 | the gap warning names E05 |
| 11 | a Play All whose every episode exists alone | `_extra\PlayAll_E01-E03.mkv`, `SplitAt` cleared |
| 12 | `Get-EpisodeTag`, `Get-SeriesInfo` edges | `E01-03`, `E1`, `E03-E01`, `TheCrownS01`, a movie folder |

Assertions are on `Kind`, `Episodes`, `SplitAt` and `Target`. `Evidence`
is asserted with `-like` on the part that is the point (case 2's chapter
numbers, case 7's "several readings"), never by whole-string equality -
that would make the suite break on every reworded message.

`Invoke-Plan` gets a case of its own: real empty files in a temp folder,
assert the moves, the `_extra` folder and `rename-log.txt`. It never
reads facts, so empty files are enough.

**Open question 1.** Pester 5 instead of a hand-rolled script? This
machine has only Pester 3.4.0 (the one Windows ships, with the old
`Should Be` syntax), so Pester 5 means an `Install-Module` step in
`InstallTools.ps1` and a dependency the repo does not have today. My
recommendation is hand-rolled: no install, and it matches `Test-Docs.ps1`,
which is the only check the project already has.

## Step 4 - the body becomes named passes

Each stage above becomes a function in `NameEpisodes.ps1`, in the same
order, with the banner comment as its header comment. Main body at the
bottom, ~25 lines:

```powershell
$items = Read-SeasonItems $SeasonDir
$warnings = @()
$warnings += Set-KindsFromNames   $items
$warnings += Deny-MisnamedSingles $items
...
```

One real plumbing change: `$warnings` is appended from four places today.
Each pass returns its warnings and main collects them, so no pass writes
to a variable it does not own.

Two PowerShell 5.1 traps to carry across intact, both already commented
in the file: `@(...).Count` instead of `-not` on an array that may unwrap
to a falsy single element (line 249-251), and `[int]` on the
`Measure-Object -Maximum` result before `"{0:D2}"` (line 702-704). A
third appears only once the code moves into functions: `$items.IndexOf()`
at lines 490 and 688 needs the parameter typed `[object[]]`, or it breaks
when a single-item array unwraps.

Printing stays in the print passes. No classify pass writes to the host
today - only `Read-SeasonItems` ("still being written") and the print
passes do - so the tests never have to capture output.

## Step 5 - documentation

`docs/NameEpisodes.md` explains how each verdict is reached; add the pass
names so a reader can go from a verdict to the function that makes it.
The README script table gains a row for `Test-EpisodeLogic.ps1`.
`Test-Docs.ps1` must pass at every commit.

## Expectation about size

Lines go **up**, not down: `NameEpisodes.ps1` ~937 → ~500, plus
`EpisodeLogic.ps1` ~320 and `Test-EpisodeLogic.ps1` ~280. This task buys
readability and a test harness, not a smaller repo. The `simplify
scripts` task was the one that bought lines back.

## Order, and what "done" looks like

One commit per step, 2 → 5. Step 3 before Step 4 is the point of the
whole plan: the tests have to exist before the risky restructuring, and
they cannot be written before Step 2 makes the functions reachable.

Done is: `Test-EpisodeLogic.ps1` green, `Test-Docs.ps1` green, and the
Step 1 snapshots identical before and after - every folder, same output,
character for character.

**Open question 2.** Is any behaviour change allowed? My assumption is
no: byte-identical output is what makes the snapshot diff a real check,
and anything the restructuring reveals as a bug gets written down as a
new backlog entry rather than fixed here. Say so if you would rather
fixes went in on the way past.

**Open question 3.** One `EpisodeLogic.ps1`, or three files (facts,
classify, plan)? One file, with the pass order visible top to bottom, is
my recommendation; three would hide the order dependency the Play All
rules have.
