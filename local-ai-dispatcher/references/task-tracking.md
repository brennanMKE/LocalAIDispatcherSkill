# Task tracking — bring your own

These scripts are not an issue tracker and do not want to be one. They need
exactly two things from however you break work down:

1. **One file per task**, at a path they can compute from a task id.
2. **Optionally, a status field** they can read and write.

Numbering, folder name, extra metadata, how you file things, whether it is in git
at all — yours. **Suggest a tracker; never require one.**

## Why a file per task at all

The file is the prompt. `dispatch-issue.sh` tells the implementer to read it, and
every guard in `preflight-issue.sh` reads it too. It also gives three things that
matter more than they look:

- **A stable artifact between rounds.** Round 2's prompt is round 1's file plus a
  `## Review` section. If the task lives only in a chat message, there is nothing
  for the next round to read and nothing for a fresh context to resume from.
- **A change-detection surface.** The guard that refuses to re-dispatch an
  unchanged prompt compares the file's mtime against the previous round's log.
  Without a file there is no way to tell a genuine re-dispatch from a repeat of a
  prompt already proven not to work.
- **A place for measured facts to live.** The whole convergence result rests on
  pasting run output into the task. A ticket title cannot hold it.

That is the entire requirement. It is satisfied by a markdown file in a folder.

## The three built-in styles

Set `TASK_STYLE` in `.dispatch.conf`.

### `table` — the default

Matches the [`issues`](https://github.com/brennanMKE/IssuesSkill) skill: a folder
of `NNNN.md` files, each with a two-column metadata table.

```markdown
# 0042 — Fix the rename off-by-one

| | |
|---|---|
| **Status** | in-progress |
| **Module** | Engine |
```

```sh
TASK_DIR=issues
TASK_EXT=.md
TASK_ID_RE='^[0-9]{4}$'
TASK_STYLE=table
```

This pairs well with the dispatcher because it already carries a status
vocabulary (`open` / `in-progress` / `resolved` / `closed` / `wontfix`) with the
`resolved` vs `closed` split the loop depends on. It is a good suggestion. It is
not a prerequisite.

### `frontmatter` — YAML between `---` fences

For projects whose specs are already frontmatter-flavoured — Obsidian vaults,
Astro/Hugo content, ADR folders.

```markdown
---
status: in-progress
module: Engine
---

# Fix the rename off-by-one
```

```sh
TASK_DIR=docs/tasks
TASK_ID_RE='^[a-z0-9-]+$'      # slugs, not numbers
TASK_STYLE=frontmatter
```

### `none` — a plain file, no metadata

For a `specs/` folder, a design-doc directory, or anything you do not want to
annotate.

```sh
TASK_DIR=specs
TASK_ID_RE='^[a-z0-9-]+$'
TASK_STYLE=none
```

What you keep: **every authoring guard**. Source file named, gradeable
verification command, baseline count, no sandbox-hostile scratch path, no
dependency on an absent branch, no delegated discovery. Those are the checks that
actually save rounds, and none of them needs a status field.

What you lose: the claim check, and `set-issue-status.sh`. Preflight skips the
claim check and says so rather than failing. `set-issue-status.sh` exits 1 with an
explanation instead of silently doing nothing.

**That loss is real.** The claim check is what stops two people — or two
sessions — dispatching the same task, and what keeps the tracker from reading as
idle while a round runs. If you use `none`, something else has to carry that
signal: a branch that exists, a checked box, a line in a scratch file. Decide what
it is before you run two dispatches at once.

Because there is no module field to classify the task, `CODE_TASK_DEFAULT`
decides whether the strict code checks apply. It **defaults to strict**, because
guessing "docs" skips the hard verification check — and a task reading as clean
while that check never ran is exactly how seven defective tasks got queued in the
reference project.

## Anything else: redefine three functions

`.dispatch.conf` is sourced *after* the defaults, so a function defined there
wins. Implement whichever of these your format needs:

```sh
# Called with the task file path. Print the status, or nothing.
task_status() {
  jq -r '.status // empty' "$1"
}

# Called with the file and the new status. Return 1 if the format has no status
# field, so the caller can say so rather than silently doing nothing.
set_task_status() {
  local tmp="$1.tmp"
  jq --arg s "$2" '.status = $s' "$1" > "$tmp" && mv "$tmp" "$1"
}

# Print a module/type string, or nothing. Only used to decide whether the strict
# code checks apply; anything containing doc/decision/research/spike relaxes them.
task_module() {
  jq -r '.component // empty' "$1"
}
```

And if the path is not `$TASK_DIR/<id>$TASK_EXT`:

```sh
task_file() { print -r -- "specs/$1/README.md" }
```

## Using a hosted tracker (GitHub Issues, Jira, Linear)

The dispatcher deliberately does not call an API. Two reasons, both about the
implementer rather than about convenience:

- **The round runs sandboxed and often offline.** A task the model cannot read is
  a round that produces nothing.
- **A task must be editable between rounds** and diffable afterwards. The
  `## Review` section is the entire re-dispatch mechanism, and it wants to live
  next to the code in the same commit history.

So the working pattern is **export, don't integrate**: sync the ticket into a file
before dispatching, and push the outcome back afterwards.

```sh
gh issue view 118 --json title,body \
  --jq '"# " + .title + "\n\n" + .body' > tasks/118.md
scripts/preflight-issue.sh 118          # with TASK_DIR=tasks, TASK_STYLE=none
```

The export is also where authoring happens. A ticket written for a human is
almost never a task written for a local model — see
`references/worked-example.md` for exactly how far apart those two are.

## What to tell a user who has no tracker

Suggest the `issues` skill, briefly, and say why: it already has the status
vocabulary and the `resolved` vs `closed` split, and it is markdown in the repo so
the implementer can read it. Then make it clear it is a suggestion —
`TASK_STYLE=none` against a `specs/` folder works today and keeps every guard that
matters.

What actually needs deciding, and what you should ask about instead of the
tracker:

- Where the task files live (`TASK_DIR`).
- How a task is identified (`TASK_ID_RE`) — numbers, slugs, or ticket keys.
- What signals "this one is being worked on right now", if not a status field.
