---
create_branch: true
create_pull_request: false
---

# Task Backlog

Inbox for new tasks. A human adds an entry; the AI turns it into a task file. See
`README.md` for how. The rules come from the `task` plugin, not from this
directory.

The frontmatter above is this project's configuration. `create_branch` decides
whether a task may have its own branch; `create_pull_request` decides whether
reaching `in_review` opens a pull request on GitHub, or a merge request on GitLab.
Each key is a ceiling: `false` takes the thing away from every task, whatever else
is written down. Edit them here and the next task follows them.

Entry format: `### [<kind>: ]<short title> [<status>, <priority>]` plus a short
explanation. Once the AI has created the task file, it adds a `file: <link>` line
under the heading and keeps the brackets up to date as the status changes. An entry
is removed when its task is cleaned, so this file shows open work only.

Keep a heading short and plain: it becomes the task file's name, and the branch
name when the project uses branches.

Kinds, written before a colon, decide what the branch is called and nothing else:

* `feature: add a login page` - branch `feature/add-a-login-page`.
* `bug: duplicate invoice rows` - branch `bug/duplicate-invoice-rows`.
* `task: bump the version` - branch `task/bump-the-version`.

**No prefix means `task`.** The prefix is dropped from the file and branch name, so
`feature: add a login page` gives `add-a-login-page.md`. A word before a colon that
is not one of the three is simply part of the title.

Statuses:

* `draft` - written down, not planned yet.
* `planning` - a human asked the AI to plan it.
* `planned` - cleared to implement. Either a plan is written and waiting for a
  human to verify it, or you set `planned` yourself **with no plan** in the task
  file, which waives the plan and tells the AI to go straight to the code.
* `in_progress` - the AI is implementing it.
* `in_review` - the implementation is ready, waiting for review.
* `changes_requested` - review asked for changes.
* `approved` - review passed, ready to land.
* `done` - merged, or committed on `main` when the project uses no branches.

Priorities: `high` | `medium` | `low`.

---

## Backlog

### first frame [done, medium]

file: [first-frame.md](first-frame.md)

Windows and many applications show videos as icons, and show first frame as icon. Is it possible to set the poster image as first frame or video?

### documentation [in_review, low]

file: [documentation.md](documentation.md)

- Does the help text have to be in script file? What if it was in a separate md file? 
- Root readme could just contain short instructions and reference other md files.
- would it make sense to have md named like the script?

### simplify scripts [draft, low]
- suggest how to simplify scripts
- what features can be dropped?
- is there an optional feature that would remove much code from scripts? 