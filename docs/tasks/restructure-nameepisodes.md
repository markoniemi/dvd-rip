---
id: restructure-nameepisodes
status: draft
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
