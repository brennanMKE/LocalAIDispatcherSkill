# LocalAIDispatcherSkill

A [Claude Code](https://claude.com/claude-code) skill for **delegating implementation
work to a local model** — cutting token cost and reliance on cloud providers — while
authoring and review stay on a hosted model.

## Overview

The split is the idea:

- A **hosted model authors** the task down to the code — exact paths, pasted
  signatures, measured before-and-after values.
- A **local model implements** it, inside its own git worktree, on its own branch,
  under a wall-clock timeout and a round cap. $0.00 per token.
- A **hosted model reviews** by re-running the verification and *mutating the code
  to prove the tests can fail*, then squash-merges.

Dispatch always happens through a **subagent**, so a twenty-minute transcript never
enters the reviewing context. That is what keeps authoring and review sharp, which
is what makes the local model work at all.

The skill is not a description of that workflow — it is the operating manual,
including the parts that went wrong. Every rule in it cost a round to learn.

## Where it comes from

Distilled from a measured run on one project: **50 dispatched rounds in one day**,
23 issues resolved, ~$24 in hosted tokens and ~131 million local tokens at zero.
24 accepted, 22 rejected, 3 failed outright — and only 2 accepted clean.

That is not a sales pitch, and the skill does not read like one. The failures
cluster hard, and the clusters *are* the operating rules:

- **Issues carrying measured code converged in one round.** Issues describing the
  work in prose did not. Pasting five declarations into one issue took it from a
  1800s timeout and 26 file rewrites to 17 edits inside the clock — nothing else
  changed.
- **Every timeout was a round creating a large new file.** Every round scoped as a
  repair converged, and quickly.
- **Local models fail *structurally* on package manifests and IDE project files**
  while landing single-file repairs first try. Route by that boundary.
- **Every rejected round had a green suite.** Mutation is the only verification
  that distinguishes a working guard from a decorative one.
- **Idle wall-clock, not tokens, is the dominant cost.** The model is free per
  token and slow per round, so throughput is set entirely by whether rounds are in
  flight.

## Installation

### Quick install — `npx skills`

```bash
npx skills add brennanMKE/LocalAIDispatcherSkill --skill local-ai-dispatcher
```

Target specific tools, or run non-interactively:

```bash
npx skills add brennanMKE/LocalAIDispatcherSkill --skill local-ai-dispatcher -a claude-code -a codex
npx skills add brennanMKE/LocalAIDispatcherSkill --skill local-ai-dispatcher -a claude-code -g -y
```

> **Claude Code note:** if the skill installs but Claude Code doesn't see it, it
> likely landed in `~/.agents/skills/` without a `~/.claude/skills/` symlink. Fix:
> ```bash
> ln -s ~/.agents/skills/local-ai-dispatcher ~/.claude/skills/local-ai-dispatcher
> ```

### Manual install — `install.sh`

```bash
git clone https://github.com/brennanMKE/LocalAIDispatcherSkill.git
cd LocalAIDispatcherSkill
./install.sh
```

Cursor has no global skills directory, so install it per project:

```bash
./install.sh --project /path/to/your/project   # links into <project>/.cursor/skills
```

Install straight from git without a manual clone (caches and updates on re-run):

```bash
REPO_URL=https://github.com/brennanMKE/LocalAIDispatcherSkill.git ./install.sh
```

`install.sh` uses symlinks, so edits to the skill files are picked up without
reinstalling.

### Where skills live

| Tool        | Global               | Project            |
|-------------|----------------------|--------------------|
| Claude Code | `~/.claude/skills/`  | `.claude/skills/`  |
| Codex CLI   | `~/.codex/skills/`   | `.codex/skills/`   |
| OpenCode    | `~/.config/opencode/skills/` | *(global only)* |
| Cursor      | *(project only)*     | `.cursor/skills/`  |

## Removal

```bash
rm ~/.claude/skills/local-ai-dispatcher
rm ~/.codex/skills/local-ai-dispatcher
```

Removing a symlink leaves the source repo untouched.

## Usage

The skill triggers automatically when you talk about running a model locally,
dispatching work to it, or debugging a round. Prompts that trigger it:

- *"set up LM Studio and OpenCode so I can delegate implementation"*
- *"dispatch issue 0042 to the local model"*
- *"the round timed out and produced nothing — what happened?"*
- *"write this issue so a small local model can actually finish it"*
- *"review this delegated round"*
- *"how much is the local delegation actually saving?"*

## Standing it up in a project

```bash
cp -R ~/.claude/skills/local-ai-dispatcher/scripts   your-project/scripts
cp ~/.claude/skills/local-ai-dispatcher/assets/dispatch.conf.template your-project/.dispatch.conf
cp ~/.claude/skills/local-ai-dispatcher/assets/AGENTS.md.template     your-project/AGENTS.md
cd your-project && ./scripts/setup-check.sh
```

`setup-check.sh` turns the start-of-project checklist into a command. Every item in
it corresponds to something that failed **silently** on a real project: the output
cap that truncates a tool call mid-write, the parallel limit that queues a dispatch
instead of running it, the missing `timeout` binary on macOS, and the discovery that
**OpenCode reads `AGENTS.md` and not `CLAUDE.md`** — which made every project rule
invisible to the delegate with no error at all.

## Project layout

```
LocalAIDispatcherSkill/
├── install.sh                          # symlinks the skill into each tool's skills dir
├── LICENSE                             # MIT
├── README.md                           # this file
└── local-ai-dispatcher/                # the skill itself
    ├── SKILL.md                        # the loop, the rules, the economics
    ├── references/                     # loaded on demand
    │   ├── setup.md                    # standing the harness up; the silent ceilings
    │   ├── model-routing.md            # what goes local, what stays hosted, measured
    │   ├── issue-authoring.md          # the Givens rule, sizing, probing before writing
    │   ├── preflight-checklist.md      # run before EVERY dispatch, mechanical + judgment
    │   ├── dispatch-loop.md            # worktrees, rounds, the dispatcher subagent, merging
    │   ├── review.md                   # mutation tables, inert-test shapes, reviewer traps
    │   ├── failure-modes.md            # the five classes, with the rounds each cost
    │   ├── cost-accounting.md          # per-phase cost, what is measurable, what is not
    │   └── unattended-operation.md     # heartbeats, and why a turn ends
    ├── scripts/                        # copied into the target project
    │   ├── _common.sh                  # config loading, shared by all of them
    │   ├── setup-check.sh              # verify the environment before the first dispatch
    │   ├── preflight-issue.sh          # refuse a known-defective issue, for free
    │   ├── dispatch-issue.sh           # one round, under two watchdogs
    │   ├── await-dispatch.sh           # blocks so that waiting is not a decision
    │   ├── set-issue-status.sh         # status moves; refuses `closed`
    │   └── tally-local-tokens.sh       # per-issue local volume, from OpenCode's SQLite
    └── assets/                         # templates
        ├── AGENTS.md.template          # rules in the file the implementer actually reads
        ├── dispatch.conf.template      # per-project config for every script
        ├── issue-template.md           # Givens, mutations, and a baseline count
        └── cost-ledger-template.md     # where a figure goes the turn it is measured
```

## A note on the scripts

They are guards, and every one exists because a round was already lost to the thing
it looks for. Two rules govern adding another:

**Test a new guard on input that should PASS, not only on input that should fail.**
A guard is a filter, and a filter that rejects everything looks identical to one
that works until someone tries to get through it. One guard in the reference project
would have blocked *every* dispatch, silently, because its grep pipeline exits
non-zero on the common path — its positive test passed beautifully and proved
nothing.

**When an instruction has failed twice at the same spot, the third fix must be a
different *kind* of fix.** More forceful wording is the same kind. `await-dispatch.sh`
exists because two prompt-level instructions failed to stop a subagent ending its
turn mid-round; making waiting structural worked where telling it not to wait did
not.

## Related

- [IssuesSkill](https://github.com/brennanMKE/IssuesSkill) — the `issues/NNNN.md`
  tracker this workflow dispatches from.

## License

[MIT](LICENSE) © Brennan Stehling
