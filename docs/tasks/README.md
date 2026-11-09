# Tasks

The backlog of this project, processed by the `task` plugin. A human writes down
what should happen; the AI plans it and implements it; the human verifies the plan,
reads the diff and accepts it.

* `Tasks.md` - the backlog: one heading per task idea, and this project's
  configuration in its frontmatter.
* `<slug>.md` - one file per task, with its status and its implementation plan.

The rules the AI follows are not in this directory: they come from the `task`
plugin. **The rules live there, not here.**

## Adding a task

Add a heading plus a short explanation to `Tasks.md`:

```markdown
### cache the user lookup [draft, high]

The user lookup hits the database on every request. Cache it.
```

The brackets hold the status and the priority, and the heading becomes the task
file's name, so keep it short and plain. Then:

| Command | What it does |
| :- | :- |
| `/task:task <heading>` | Start, continue or finish that task. |
| `/task:next-task` | Take the next open entry: highest priority, then first in `Tasks.md`. |
| `/task:clean-tasks` | Delete the `done` tasks and their entries. Only when you ask. |

Edit the brackets yourself to re-prioritise a task or to ask for planning; the AI
reads the change back into the task file.

This directory was created by `/task:init`.