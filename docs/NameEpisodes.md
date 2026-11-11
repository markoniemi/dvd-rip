# NameEpisodes.ps1

Names the raw titles in a TV season folder `E01.mkv`, `E02.mkv`, ... by
reading durations and chapter marks out of the files rather than trusting
title order. The flags are documented in the script:
`Get-Help .\Scripts\NameEpisodes.ps1 -Full`.

```powershell
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01                  # dry run
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Execute         # apply
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Split -Execute  # cut Play Alls up
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Index 5         # first episode is 5
.\Scripts\NameEpisodes.ps1 -DirName The_Crown_S01 -Root I:\Work    # look here, not in VideoRoot
```

Run it per disc rather than once at the end of a season: title order is only
meaningful within one disc.

## Why arithmetic and not title order

MakeMKV names its output by title index (`C1_t00.mkv`), and a DVD usually
carries more titles than episodes: a "Play All" title holding several episodes
back to back, and sometimes the same episode twice. Numbering files blindly in
title order therefore shifts every episode after the first extra title, which
is why `RipDisc.ps1 -Index` can't be trusted on its own.

This script classifies the titles by arithmetic instead of by position, from
durations and chapter boundaries read out of the files themselves:

| Verdict | How it is reached |
| :- | :- |
| Duplicate | same duration (within tolerance) and chapter count as a title already accounted for. |
| Play All | it holds a run of the other titles end to end, every chapter mark of each lining up inside it; OR its duration equals the sum of a run of them and their chapter counts add up; OR one of its chapters starts exactly where another title ends, meaning it begins with that whole title and continues past it. |
| Episode | whatever is left, numbered in title order, unless it is one block of a Play All (then it takes that block's number), far longer than the episodes around it (then it's left alone: a Christmas special is not simply the next episode), or far shorter (a bonus feature that got past `--minlength`). |

Nothing is guessed silently: every verdict is printed with the arithmetic
behind it, and a title the rules can't explain is reported as Unknown and left
alone. Dry run by default - add `-Execute` to apply.

## The yardstick, and what it is worth

"Far longer" and "far shorter" are measured against the median of the episodes
already pinned down (`MultiEpisodeRatio`, 1.8x either way). That yardstick is
only as good as what the folder holds: name the earlier discs of a season
first and it is solid, but in a folder of three titles and nothing named yet
it can be skewed by a long one. The duration of every title is printed, so it
can be checked by eye.

## A name on a file is believed, but checked

A name is not proof either. A file called `E04.mkv` is believed until the
arithmetic says otherwise - and a Play All numbered as an episode by
`RipDisc.ps1 -Index` is exactly what it catches: Downton Abbey season 5
arrived with three of them sitting among the episodes, as E04, E08 and E12. A
single `E##` name is dropped when the file turns out to hold a run of the
other titles mark for mark, which frees that number again. Whatever can be
doubted but not disproved - a named episode much shorter than the rest, two
numbers on one title, a number with no file behind it - is printed under
`--- check ---` and left for the human.

A gap is worth reading rather than closing blindly — it also appears when the
missing episode is simply on a disc you haven't ripped yet.

A file far longer than the episodes around it — a Christmas special, or two
episodes no rule could separate — is reported and left alone rather than
numbered. Rename it `E09.mkv` or `E07-E08.mkv` by hand and the next run takes
that as given.

Without `-Index` the first episode number continues from the highest `E##`
file already in the folder, so the next disc of a season needs no argument.

## -SplitAt, for the discs the arithmetic can't settle

`-SplitAt` is the last word on where a range-named file is cut: Downton Abbey
season 4 disc 1 is 20 chapters holding three episodes, which no even division
fits and no other title on the disc anchors. Give the chapter numbers to cut
BEFORE. Without a file name it applies to the one range-named file that needs
it, and says so rather than guessing when several could.

```powershell
.\Scripts\NameEpisodes.ps1 -DirName Downton_Abbey_S04 -SplitAt 9,15
.\Scripts\NameEpisodes.ps1 -DirName Downton_Abbey_S04 -SplitAt "E01-E03=9,15","E07-E08=7"
```

The chapter numbers are taken as given — only impossible ones are refused — so
the plan is worth reading before adding `-Execute`.

## Play All titles and _extra\

By default they are kept whole. One holding episodes nobody else covers is
named for its range (`E01-E03.mkv`, which `ConvertNext.ps1` turns into
`<Show> - S01E01-E03.mkv`); one whose episodes all exist on their own is
redundant and moves to `_extra\` (`ConvertNext.ps1` scans only the top level
of a raw folder, so `_extra\` is ignored). With `-Split` it is cut into single
episodes at its chapter boundaries with mkvmerge - lossless, no re-encode -
and the original then moves to `_extra\`.

A standalone episode that a Play All also holds keeps its number; the Play
All's copy of it goes to `_extra\`.

Duplicates always move to `_extra\`. Nothing is ever deleted, and every move
goes to `rename-log.txt`.
