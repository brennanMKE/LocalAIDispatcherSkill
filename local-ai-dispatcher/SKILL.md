---
name: local-ai-dispatcher
description: Delegate coding work to a local model (LM Studio, Ollama, OpenCode) while a hosted model authors the task and reviews the result — to cut API spend, stay under subscription usage limits, and depend less on cloud providers. Use when the user wants to run an LLM on their own hardware for real implementation work, wire a local endpoint into an agent loop, write a task spec small enough for a local model to actually finish, dispatch or babysit a delegated round, review what came back, or work out what the delegation costs and saves. Triggers on "local model", "LM Studio", "Ollama", "OpenCode", "run it on my own machine", "hitting my usage limit", "out of Claude tokens", "cut my API bill", "offline" or "air-gapped" coding, "AGENTS.md", "worktree per task", "delegate implementation", and "the round timed out / produced nothing / claimed it passed".
license: MIT
metadata:
  author: Brennan Stehling
  version: "1.1"
---

# Local AI dispatcher

Run implementation on a **local model** at $0.00 per token and zero subscription
usage, and keep **authoring and review** on a hosted model.

This is the operating manual for that split — the loop, the guards, the failure
catalogue, and honest accounting. It is derived from a measured run: 50 dispatched
rounds in one day on one project. Every rule cost a round to learn, and the
numbers are stated so you can tell which rules are load-bearing and which are
preference.

## Start here

Route to what the user actually needs. Don't read everything.

| The user is… | Go to |
|---|---|
| **Standing this up** for the first time | Run `scripts/setup-check.sh`, then `references/setup.md` |
| **Not using an issue tracker**, or using their own | `references/task-tracking.md` — the tracker is pluggable |
| **Deciding** whether some work should go local | `references/model-routing.md` |
| **Writing a task** for the local model | `references/worked-example.md` first, then `assets/issue-template.md` |
| **About to dispatch** | `scripts/preflight-issue.sh <id>`, then `references/preflight-checklist.md` |
| **Running or babysitting** a round | `references/dispatch-loop.md` |
| **Reviewing** what came back | `references/review.md` — lead with the mutations |
| **Debugging a failed round** | `references/failure-modes.md` — find the class, don't re-derive it |
| Asking **what it costs or saves** | `references/cost-accounting.md` |
| Running **unattended for hours** | `references/unattended-operation.md` |

## The one-paragraph version

A hosted model authors a task **down to the code** — exact paths, pasted
signatures, measured before-and-after values. A local model implements it inside
its own git worktree, on its own branch, under a wall-clock timeout and a 3-round
cap. A hosted reviewer re-runs the verification and **mutates the code to prove
the tests can fail**, then squash-merges. Dispatch always happens through a
**subagent**, so a 20-minute transcript never enters the reviewing context.

## Why do this — three reasons, and the middle one gets missed

1. **Cost.** Implementation is the bulk of the tokens and the part that benefits
   least from a frontier model *once the thinking is already done*.

2. **Subscription headroom.** In an agentic loop, **input outweighs output by
   roughly 100 to 1** — every turn resends the accumulated context, so a long
   round re-reads its own transcript hundreds of times. That is precisely the
   traffic that burns through a usage window fastest, and precisely the traffic
   with the least judgment in it. Moving implementation to local hardware spends
   the subscription on authoring and review, where judgment actually pays. In the
   reference project the local model processed ~131M tokens; that same traffic on
   a hosted mid-tier model would have been ~$428, and on a subscription it would
   have been the difference between working all day and being throttled by noon.

3. **Independence.** Local inference keeps working offline, on an air-gapped
   machine, during an outage, and without sending the repository anywhere.

## When NOT to use it

Do not delegate work where being wrong is not a bug:

- Licensing / clean-room boundaries. The output looks like ordinary code.
- Code signing, certificates, keychains, archives.
- Architecture spikes whose answer sequences the rest of the project.
- Marking work done. A delegated run reports; a human or hosted reviewer confirms.

## Prerequisites

- A local model served on an **OpenAI-compatible endpoint** (LM Studio, Ollama,
  llama.cpp).
- **OpenCode**, which is the agent loop the local model drives.
- **git worktrees.** One per task — mandatory, not tidiness. See
  `references/dispatch-loop.md`.
- **A way to break work into tasks.** The scripts need exactly two things from it:
  *one file per task, at a path they can compute from a task id*, and optionally
  *a status field they can read and write*. Everything else is yours.

That last one is deliberately loose. The defaults match the `issues` skill
(`issues/0042.md` with a `| **Status** |` row) because it pairs well with this
one, but nothing here requires it — `TASK_STYLE` also supports YAML frontmatter
or no metadata at all, and `TASK_DIR` / `TASK_EXT` / `TASK_ID_RE` accept slugs,
Jira-style keys, or any directory you already keep specs in. If your format is
none of those, redefine three shell functions in `.dispatch.conf`.

**Read `references/task-tracking.md` before telling a user to adopt a tracker.**
Suggest one; don't require one.

## The five roles

| Role | Model | Scope |
|---|---|---|
| **Planning** | Top hosted model | Authors the task to code level: exact paths, pasted signatures, literal lines, measured before-and-after values |
| **Implementation — pure code** | **Local, $0.00** | Ordinary single-file code against a target the task already measured |
| **Implementation — structural** | Mid-tier hosted, **billed** | Package manifests, IDE project files, build settings, the environment, the harness |
| **Review** | Top hosted model | Re-runs verification, runs mutations, reads every new test body |
| **Milestone review** | Top hosted model | Runs when a milestone's tasks all resolve; checks stated exit criteria only |

Local models fail *structurally* on build manifests and IDE project files — three
rounds on one command-wiring change, never a test written. They land single-file
repairs first try. **Route by that boundary, not by difficulty.**

## The loop

```sh
# 0. primary checkout stays on the default branch, permanently. Never dispatch in it.
git worktree add -b issue/0012 ../proj-0012 main
cd ../proj-0012 && git push -u origin issue/0012      # push it empty, immediately

# 1. claim it, so the tracker does not lie about what is running
#    (skip if your format has no status field — preflight skips the check too)
scripts/set-issue-status.sh 0012 in-progress

# 2. author to code level, then check it mechanically
scripts/preflight-issue.sh 0012

# 3. dispatch — from a SUBAGENT, backgrounded
scripts/dispatch-issue.sh 0012 --round 1

# 4. the subagent blocks here instead of "waiting"; exit 75 means call it again
scripts/await-dispatch.sh 0012

# 5. review by re-running and mutating, then commit the round to the branch
git add -A && git commit -m "#0012 round 1: <what it did>" && git push

# 6. accept → squash-merge from the primary checkout, push immediately
```

Rules that hold this together, each written after it was violated:

1. **The primary checkout never leaves the default branch.** Dispatching in it
   pins the branch, and every finished task queues behind the running round while
   the repo reads as idle. One worktree per task.
2. **Push the branch when it is created, and after every round.**
   Committed-but-unpushed is indistinguishable from no work.
3. **Merge the moment a task resolves.** Never batch. One task landing is the unit
   of visible progress.
4. **Dispatch through a subagent, never the main loop.** The transcript is
   worthless once the outcome is known, and keeping the main context small is what
   makes authoring and review good.
5. **Never re-dispatch an unchanged prompt.** It re-runs a prompt already proven
   not to work. Write a `## Review` section or split the task.

Full detail: `references/dispatch-loop.md`.

## The three rules that decide whether a round converges

Sorted by measured effect, largest first. `references/worked-example.md` shows
rule 1 as a before/after on one real task — that is the fastest way to internalize
all three.

### 1. Put the code in the task

Tasks carrying **measured** code converged in one round. Tasks describing the work
in prose did not. The cleanest single experiment: a round timed out at 1800s
having rewritten its test file **26 times**, discovering signatures by compile
error. Pasting five declarations into the task took the next round to **17 edits,
finished inside the clock**. Nothing else changed.

Name every path in full. Paste every signature the round must call, and the public
members of each result type. Paste the literal change where it is small. State
measured before-and-after values and say they were measured.

### 2. One deliverable

If the Expected behavior has two verbs in it, it is two tasks. No
multi-deliverable task has ever converged; every converged one named exactly one
file. The failure signature is distinctive — the model gets partway into each
piece and the watchdog fires.

### 3. Prefer repair framing over greenfield

**Every timeout was a round creating a large new file.** Every round scoped as a
repair converged, and quickly. A repair starts from something that builds; each
step either compiles or does not. A monolithic write is all-or-nothing — one round
emitted 306 lines with `{ ... }` placeholder bodies still in them and spent twenty
minutes failing to dig out.

If a deliverable will exceed ~200 lines, split it before dispatching.

The counter-risk is real and has cost rounds: **a code sample written from memory
propagates silently.** Everything pasted into a task must have been *run*, in the
context the implementer will run it in — not reasoned from something adjacent that
was run. See `references/issue-authoring.md`.

## Verification: mutation or nothing

**Every rejected round in the reference project had a green suite.** A green count
is not evidence unless it *moved*, and a passing test is not evidence unless it
*can fail*.

Six distinct costumes of "a check that cannot fail" appeared in a single day — an
assertion-free test; a loop that `continue`s past all but one case; an extractor
returning `[]` so the assertion is `[] == []`; a test count identical with the new
files deleted; a stale guard forbidding the old path; a predicate that is
structurally unsatisfiable. Each was caught, logged, and given a detector. **Each
next one wore a shape the previous detector could not see.**

So the review leads with the mutation table: break the thing each assertion
guards, and confirm it fails. Record *which* test killed the mutation — a mutation
killed by an unrelated test is evidence of coverage you do not have.

And read the **body** of every new test, not its name. Ask what production change
would make it fail. If the answer is "none", the criterion is unmet however green
the run was.

Full checklist: `references/review.md`.

## Rules for the implementer live where the implementer reads them

**OpenCode reads `AGENTS.md`. It does not read `CLAUDE.md`.** Verified, not
assumed: asked to state a rule with only `CLAUDE.md` present, the model answered
`UNKNOWN`; with `AGENTS.md` present it recited it. Every licensing and signing
rule was invisible to the delegate and nothing errored.

So put the non-negotiables in `AGENTS.md`, **inlined, not referenced** — a model
that ignores "do not read any files" will also not follow a pointer. Verify it
landed by asking the model to recite a rule with no file reads.

`assets/AGENTS.md.template` opens with a minimum-viable version worth copying in
whole; the long catalogue below it is opt-in.

## When an instruction fails three times, stop writing instructions

The strongest structural finding here, and it generalizes past this workflow:

- A dispatcher subagent wrote *"waiting for the dispatch to exit"* and stopped. An
  instruction was added telling it not to. **It recurred, with the instruction in
  the prompt.** The fix that worked was `await-dispatch.sh` — a script that blocks
  inside a tool call and exits 75 meaning *call me again*. Waiting stopped being a
  decision.
- A sandbox `/tmp` rejection was fixed at the task, then in `AGENTS.md`, then in
  the dispatch prompt itself. It recurred all three times. Four rounds lost.

**Three escalations of the same kind of fix is the signal to change the kind of
fix.** More forceful wording is the same kind. A guard, a blocking script, or a
config change is a different kind.

Corollary for the human: a finding recorded only in a retrospective **has not been
fixed, it has been filed.** Push it to the file that is read *before* the next
dispatch — `AGENTS.md` for model behaviour, the preflight checklist for authoring,
the script for anything mechanical.

## Guards, and what each prevents

Copy `scripts/` into the project and configure `.dispatch.conf`. Each guard exists
because a round was already lost to the thing it looks for.

| Script | Prevents |
|---|---|
| `setup-check.sh` | Standing up the harness with a silent ceiling in it — output cap, `PARALLEL` limit, missing `timeout` binary, `AGENTS.md` absent, run logs not gitignored |
| `preflight-issue.sh` | The authoring defects that have each cost a round: no source file named, no gradeable verification command, no baseline count, a scratch path the sandbox rejects, a dependency on an absent branch, delegated discovery, an unclaimed task, a third concurrent dispatch |
| `dispatch-issue.sh` | An unbounded run, a hung inference, a fourth round, a dirty tree, the wrong branch, a no-op round reported as success, a sandbox rejection reported as exit 0 |
| `await-dispatch.sh` | A dispatcher subagent ending its turn while its round still runs |
| `set-issue-status.sh` | An invalid status, and an agent marking work confirmed-done — which is the human's call |
| `tally-local-tokens.sh` | Losing the local model's token volume, which exists only in OpenCode's SQLite and nowhere else |

**Test every new guard on input that should PASS, not only on input that should
fail.** A guard is a filter, and a filter that rejects everything looks identical
to one that works until someone tries to get through it. Two guards here would
have blocked *every* dispatch; both were caught only by a negative control.

## Bootstrapping a project

Run `scripts/setup-check.sh` first — it turns the start-of-project checklist into
a command. Then, in order:

1. `AGENTS.md` at the repo root with the non-negotiables **inlined**. Verify by
   recitation.
2. Copy `scripts/` in — including `_common.sh`, which every other script sources —
   and write `.dispatch.conf` from `assets/dispatch.conf.template`.
3. Point `TASK_DIR` / `TASK_STYLE` at however the project already tracks work.
4. Add the run-log directory and the scratch directory to `.gitignore`.
5. Confirm the model server's concurrency limit before planning any fan-out.
6. Confirm the output-token cap is large enough to hold a whole file in one tool
   call.
7. **Decide how cost will be measured before the first delegated round.**
   Retrofitting it recovers only what the harness happened to report along the way.

Details and the reasoning for each: `references/setup.md`.

## References

| File | Read it when |
|---|---|
| `references/setup.md` | Standing the harness up, or a round fails for environmental reasons |
| `references/task-tracking.md` | The project has no tracker, or its own |
| `references/model-routing.md` | Deciding local vs hosted for a piece of work |
| `references/worked-example.md` | Writing a task — the same one, prose vs code level, with outcomes |
| `references/issue-authoring.md` | Writing a task in depth — the Givens rule, sizing, probing first |
| `references/preflight-checklist.md` | Before **every** dispatch, including re-dispatches |
| `references/dispatch-loop.md` | Running the loop: worktrees, rounds, the dispatcher subagent, merging |
| `references/review.md` | Reviewing a round — mutation tables, inert-test shapes, reviewer traps |
| `references/failure-modes.md` | A round failed and you want the class, not a fresh diagnosis |
| `references/cost-accounting.md` | Recording what a round cost; arguing whether delegation pays |
| `references/unattended-operation.md` | Running for hours without a human; heartbeats and recovery |

## Resources

| Path | What it is |
|---|---|
| `scripts/_common.sh` | Config loading and task-file access. **Every other script sources it** |
| `scripts/setup-check.sh` | Verifies the environment before the first dispatch |
| `scripts/preflight-issue.sh` | Mechanical authoring checks; refuses a known-defective task |
| `scripts/dispatch-issue.sh` | Runs one round under a wall-clock and a stall watchdog |
| `scripts/await-dispatch.sh` | Blocks inside a tool call so waiting is not a decision |
| `scripts/set-issue-status.sh` | Status moves; refuses invalid values and `closed` |
| `scripts/tally-local-tokens.sh` | Per-task local token volume, from OpenCode's SQLite |
| `assets/AGENTS.md.template` | Rules in the file the implementer actually reads |
| `assets/dispatch.conf.template` | Per-project config for every script here |
| `assets/issue-template.md` | Task shape with Givens, mutations, and a baseline count |
| `assets/cost-ledger-template.md` | Where a measured figure goes the turn it is reported |
