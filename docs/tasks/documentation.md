---
id: documentation
status: in_progress
priority: low
kind: task
branch: task/documentation
---

# documentation

- Does the help text have to be in script file? What if it was in a separate md file?
- Root readme could just contain short instructions and reference other md files.
- would it make sense to have md named like the script?

Simplifying the scripts themselves is a separate backlog entry, `simplify
scripts`, so this task moves prose around and changes no behaviour.

# Implementation Plan

## What is actually there now

Measured, not guessed:

| File | Lines | Header comment |
| :- | -: | -: |
| `NameEpisodes.ps1` | 1001 | 75 |
| `ConvertNext.ps1` | 614 | 81 |
| `RipDisc.ps1` | 220 | 25 |
| `FixPosters.ps1` | 139 | 24 |
| `FetchPosterPreview.ps1` | 119 | 25 |
| `InstallTools.ps1` | 79 | 23 |
| `Config.ps1` | 73 | 21 |
| `README.md` | 239 | — |

Three findings decide the rest of this plan:

1. **No script has PowerShell comment-based help.** Not one `<#`, not one
   `.SYNOPSIS`. The headers are plain `#` prose, so `Get-Help
   .\ConvertNext.ps1` and `.\ConvertNext.ps1 -?` tell the user nothing,
   even though every script already carries a hand-written `Usage:` block
   listing its flags. The help is written; it is just in a form PowerShell
   cannot see.
2. **Every flag is documented twice**, in the script's `Usage:` block and
   again in `README.md`, in different words — compare
   `ConvertNext.ps1:37-56` with `README.md:216-230`. Two homes, so they
   drift.
3. **Config keys are documented three times**: the 26-row table in
   `README.md:63-84`, `config.example.json`, and each script's own
   defaults hashtable (`ConvertNext.ps1:98`). Nothing checks that the
   three agree.

So the answer to "does the help text have to be in the script file?" is:
the per-parameter part should move *further into* the script, as real
comment-based help, and the long narrative should move *out*. They are two
different kinds of text that currently sit in one block.

## Routes

| Route | Shape | Cost |
| :- | :- | :- |
| **A. In-script only** | Turn each header into comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`). README shrinks to install, key, config, pipeline order | No new files; `Get-Help -Full` becomes the reference. The 75-line NameEpisodes narrative has to live inside `.DESCRIPTION`, which is a lot of prose to read through `Get-Help` |
| **B. Markdown only** | One `docs/<Script>.md` per script, header cut to a pointer line, README an index | Answers the "md named like the script" question directly, but `-?` still gives nothing, and the reference moves away from the code that must change with it |
| **C. Split by kind (recommended)** | Interface in the script as comment-based help (params, examples, one-paragraph synopsis); narrative in `docs/<Script>.md` (why the arithmetic works, the Downton cases, the pitfalls); README = intro, install, config, pipeline order, and a table linking both | Two homes, but each fact has only one. A flag is documented where it is declared; a war story is documented where it can be read |
| **D. Generate md from help** | PlatyPS `New-MarkdownHelp` builds `docs/*.md` from comment-based help | One source, but adds a module dependency and a build step that has to be rerun or the md lies. Overkill for seven scripts |

Recommendation: **C**.

## Steps

1. **Comment-based help, one script at a time**, starting with
   `FixPosters.ps1` (small, two parameters) to settle the house style,
   then `FetchPosterPreview.ps1`, `RipDisc.ps1`, `InstallTools.ps1`,
   `ConvertNext.ps1`, `NameEpisodes.ps1`. Each gets `.SYNOPSIS`, a short
   `.DESCRIPTION`, one `.PARAMETER` per declared parameter, and the
   existing `Usage:` lines converted to `.EXAMPLE` blocks. Verify per
   script with `Get-Help .\Scripts\<name>.ps1 -Full`.
   `Config.ps1` is dot-sourced and has no `param()`, so it keeps a plain
   header.
2. **Move the narrative** that is not about a parameter into
   `docs/<Script>.md`, named exactly like the script
   (`docs/NameEpisodes.md`). Move the text rather than rewrite it, so the
   diff stays readable and nothing is quietly lost. Each md opens with one
   line saying `Get-Help` is the flag reference.
3. **Rewrite `README.md`** to: what the project is, the pipeline in one
   line, install, the TMDb key, config, and a table of the scripts linking
   `docs/<Script>.md`. The per-flag prose in sections 4 goes; a short
   "typical session" sequence of commands stays, since that is the one
   thing no single script's help can show.
4. **Pick one home for the config keys** (open question 2) and make the
   other two point at it.
5. **A docs check** (open question 3): `Scripts/Test-Docs.ps1` asserting
   that every `.ps1` with a `param()` block has a `.SYNOPSIS`, that every
   declared parameter has a `.PARAMETER` entry, that every script with
   parameters has a `docs/<Script>.md`, and that every relative markdown
   link resolves. That is this task's only testable logic — the rest is
   prose.

Done one script per commit, so a bad house style is caught on the first
one and not on the seventh.

## Answers

1. **Route C**, decided by the human.
2. **Move the prose verbatim**, decided by the human.
3. Config keys: not answered, so taken as **`docs/Configuration.md`** —
   under route C the README is an index, and a 26-row table is not an
   index. README and `config.example.json` point at it.
4. `Scripts/Test-Docs.ps1`: not answered, so **written**. It is the only
   executable thing this task produces and it is what proves the
   `.PARAMETER` coverage, so the alternative is a task with nothing to
   run.
