---
name: local-ai-dispatcher
description: Delegate implementation work to a local model (LM Studio + OpenCode) while authoring and review stay on a hosted model — to cut token cost and reliance on cloud providers. Use when the user wants to run a local LLM for coding, set up LM Studio / Ollama / OpenCode as an implementer, dispatch issues to a local model, build an unattended agent loop with worktrees and round caps, write issues detailed enough for a small model to implement, review a delegated round, or account for what delegation actually costs. Triggers on "local model", "LM Studio", "OpenCode", "Ornith", "dispatch this issue", "run it locally", "free tokens", "reduce API spend", "delegate implementation", "unattended overnight rounds", "the round failed / timed out / produced nothing".
license: MIT
metadata:
  author: Brennan Stehling
  version: "1.0"
---

# Local AI dispatcher

Run implementation on a **local model** at $0.00 per token, and keep **authoring and
review** on a hosted model. This skill is the distilled operating manual for that split:
the loop, the guards, the failure catalogue, and the honest accounting.

It is derived from a measured run — 50 dispatched rounds in one day on one project.
Every rule here cost a round to learn, and the numbers are stated so you can tell
which rules are load-bearing and which are preference.

## The one-paragraph version

A hosted model authors an issue **down to the code** — exact paths, pasted signatures,
measured before-and-after values. A local model implements it inside its own git
worktree, on its own branch, under a wall-clock timeout and a 3-round cap. A hosted
reviewer re-runs the verification and **mutates the code to prove the tests can fail**,
then squash-merges. Dispatch always happens through a **subagent**, so a 20-minute
transcript never enters the reviewing context.

## When to use this skill

- Setting up a local model (LM Studio, Ollama, llama.cpp) as a coding implementer.
- Wiring OpenCode, Cline, Aider, or similar to a local endpoint for delegated work.
- Authoring a task/issue that a small local model can actually finish.
- Dispatching, babysitting, reviewing, or debugging a delegated round.
- Deciding *which* work goes local and which stays hosted.
- Accounting for what the delegation saves, and what it still costs.
- Any round that timed out, produced nothing, or shipped a green suite that proves nothing.

## When NOT to use it

Do not delegate work where being wrong is not a bug:

- Licensing / clean-room boundaries. The output looks like ordinary code.
- Code signing, certificates, keychains, archives.
- Architecture spikes whose answer sequences the rest of the project.
- Marking work done. A delegated run reports; a human or hosted reviewer confirms.

## The five roles

| Role | Model | Scope |
|---|---|---|
| **Planning** | Top hosted model | Authors the issue to code level: exact paths, pasted signatures, literal lines, measured values |
| **Implementation — pure code** | **Local, $0.00** | Ordinary single-file code against a target the issue already measured |
| **Implementation — structural** | Mid-tier hosted, **billed** | Package manifests, project files, build settings, the environment, the harness itself |
| **Issue review** | Top hosted model | Re-runs verification, runs mutations, reads every new test body |
| **Milestone review** | Top hosted model | Runs when a milestone's issues all resolve; checks stated exit criteria only |

Local models fail *structurally* on build manifests and IDE project files — three rounds
on one command-wiring change, never a test written. They land single-file repairs first
try. Route by that boundary, not by difficulty. See `references/model-routing.md`.

## The economics, stated honestly

**Token cost is not the interesting number. Idle wall-clock is.**

A local round is free per token and slow per round (8–30 minutes). Throughput is set
almost entirely by whether rounds are in flight. In the reference project, measured
hosted spend was ~$38 while a single hour of both dispatch slots sitting idle — because
a turn ended with prose instead of a tool call — cost more than that in foregone work
and appears in no ledger.

So the failure to optimize against is **stopping**, not spending.
See `references/cost-accounting.md`.

## The loop

```sh
# 0. primary checkout stays on the default branch, permanently. Never dispatch in it.
git worktree add -b issue/0012 ../proj-0012 main
cd ../proj-0012 && git push -u origin issue/0012      # push it empty, immediately

# 1. claim it, so the tracker does not lie about what is running
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

1. **The primary checkout never leaves the default branch.** Dispatching in it pins the
   branch, and every finished issue queues behind the running round while the repo reads
   as idle. One worktree per issue.
2. **Push the branch when it is created, and after every round.** Committed-but-unpushed
   is indistinguishable from no work.
3. **Merge the moment an issue resolves.** Never batch. One issue landing is the unit of
   visible progress.
4. **Dispatch through a subagent, never the main loop.** The transcript is worthless once
   the outcome is known, and keeping the main context small is what makes authoring and
   review good.
5. **Never re-dispatch an unchanged prompt.** It re-runs a prompt already proven not to
   work. Write a `## Review` section or split the issue.

Full detail: `references/dispatch-loop.md`.

## The three rules that decide whether a round converges

Sorted by measured effect, largest first.

### 1. Put the code in the issue

Issues carrying **measured** code converged in one round. Issues describing the work in
prose did not. The cleanest single experiment: a round timed out at 1800s having
rewritten its test file **26 times**, discovering signatures by compile error. Pasting
five declarations into the issue took the next round to **17 edits, finished inside the
clock**. Nothing else changed.

Name every path in full. Paste every signature the round must call, and the public
members of each result type. Paste the literal change where it is small. State measured
before-and-after values and say they were measured.

### 2. One deliverable

If the Expected behavior has two verbs in it, it is two issues. No multi-deliverable
issue has ever converged; every converged issue named exactly one file. The failure
signature is distinctive — the model gets partway into each piece and the watchdog fires.

### 3. Prefer repair framing over greenfield

**Every timeout was a round creating a large new file.** Every round scoped as a repair
converged, and quickly. A repair starts from something that builds; each step either
compiles or does not. A monolithic write is all-or-nothing — one round emitted 306 lines
with `{ ... }` placeholder bodies still in them and spent twenty minutes failing to dig
out.

If a deliverable will exceed ~200 lines, split it before dispatching, not after it fails.

The counter-risk is real and has cost rounds: **a code sample written from memory
propagates silently.** Everything pasted into an issue must have been *run*, in the
context the implementer will run it in — not reasoned from something adjacent that was
run. See `references/issue-authoring.md`.

## Verification: mutation or nothing

**Every rejected round in the reference project had a green suite.** A green count is not
evidence unless it *moved*, and a passing test is not evidence unless it *can fail*.

Six distinct costumes of "a check that cannot fail" appeared in a single day — an
assertion-free test; a loop that `continue`s past all but one case; an extractor returning
`[]` so the assertion is `[] == []`; a test count identical with the new files deleted; a
stale guard forbidding the old path; a predicate that is structurally unsatisfiable. Each
was caught, logged, and given a detector. **Each next one wore a shape the previous
detector could not see.**

So the review leads with the mutation table: break the thing each assertion guards, and
confirm it fails. Record *which* test killed the mutation — a mutation killed by an
unrelated test is evidence of coverage you do not have.

And read the **body** of every new test, not its name. Ask what production change would
make it fail. If the answer is "none", the criterion is unmet however green the run was.

Full checklist: `references/review.md`.

## Rules for the implementer live where the implementer reads them

**OpenCode reads `AGENTS.md`. It does not read `CLAUDE.md`.** Verified, not assumed:
asked to state a rule with only `CLAUDE.md` present, the model answered `UNKNOWN`; with
`AGENTS.md` present it recited it. Every licensing and signing rule was invisible to the
delegate and nothing errored.

So put the non-negotiables in `AGENTS.md`, **inlined, not referenced** — a model that
ignores "do not read any files" will also not follow a pointer. Verify it landed by
asking the model to recite a rule with no file reads.

Start from `assets/AGENTS.md.template`.

## When an instruction fails three times, stop writing instructions

The strongest structural finding here, and it generalizes past this workflow:

- A dispatcher subagent wrote *"waiting for the dispatch to exit"* and stopped. An
  instruction was added telling it not to. **It recurred, with the instruction in the
  prompt.** The fix that worked was `await-dispatch.sh` — a script that blocks inside a
  tool call and exits 75 meaning *call me again*. Waiting stopped being a decision.
- A sandbox `/tmp` rejection was fixed at the issue, then in `AGENTS.md`, then in the
  dispatch prompt itself. It recurred all three times. Four rounds lost.

**Three escalations of the same kind of fix is the signal to change the kind of fix.**
More forceful wording is the same kind. A guard, a blocking script, or a config change is
a different kind.

Corollary for the human: a finding recorded only in a retrospective **has not been fixed,
it has been filed.** Push it to the file that is read *before* the next dispatch —
`AGENTS.md` for model behaviour, the preflight checklist for authoring, the script for
anything mechanical.

## Guards, and what each prevents

Copy `scripts/` into the project and configure `.dispatch.conf`. Each guard exists
because a round was already lost to the thing it looks for.

| Script | Prevents |
|---|---|
| `setup-check.sh` | Standing up the harness with a silent ceiling in it — output cap, `PARALLEL` limit, missing `timeout` binary, `AGENTS.md` absent, run logs not gitignored |
| `preflight-issue.sh` | The authoring defects that have each cost a round: no source file named, no gradeable verification command, no baseline count, a scratch path the sandbox rejects, a dependency on an absent branch, delegated discovery, an unclaimed issue, a third concurrent dispatch |
| `dispatch-issue.sh` | An unbounded run, a hung inference, a fourth round, a dirty tree, the wrong branch, a no-op round reported as success, a sandbox rejection reported as exit 0 |
| `await-dispatch.sh` | A dispatcher subagent ending its turn while its round still runs |
| `tally-local-tokens.sh` | Losing the local model's token volume, which exists only in OpenCode's SQLite and nowhere else |

**Test every new guard on input that should PASS, not only on input that should fail.**
A guard is a filter, and a filter that rejects everything looks identical to one that
works until someone tries to get through it. Two guards here would have blocked *every*
dispatch; both were caught only by a negative control.

## Bootstrapping a project

Run `scripts/setup-check.sh` first — it turns the start-of-project checklist into a
command. Then, in order:

1. `AGENTS.md` at the repo root with the non-negotiables **inlined**. Verify by recitation.
2. Copy `scripts/` in; write `.dispatch.conf` from `assets/dispatch.conf.template`.
3. Add the run-log directory to `.gitignore`.
4. Confirm the model server's concurrency limit before planning any fan-out.
5. Confirm the output-token cap is large enough to hold a whole file in one tool call.
6. **Decide how cost will be measured before the first delegated round.** Retrofitting it
   onto completed work recovers only what the harness happened to report along the way.

Details and the reasoning for each: `references/setup.md`.

## References

| File | Read it when |
|---|---|
| `references/setup.md` | Standing the harness up, or a round fails for environmental reasons |
| `references/model-routing.md` | Deciding local vs hosted for a piece of work |
| `references/issue-authoring.md` | Writing an issue for delegation — the Givens rule, sizing, templates |
| `references/preflight-checklist.md` | Before **every** dispatch, including re-dispatches |
| `references/dispatch-loop.md` | Running the loop: worktrees, rounds, the dispatcher subagent, merging |
| `references/review.md` | Reviewing a round — mutation tables, inert-test shapes, what to re-run |
| `references/failure-modes.md` | A round failed and you want the class, not a fresh diagnosis |
| `references/cost-accounting.md` | Recording what a round cost; arguing whether delegation pays |
| `references/unattended-operation.md` | Running for hours without a human; heartbeats and recovery |

## Resources

| Path | What it is |
|---|---|
| `scripts/setup-check.sh` | Verifies the environment before the first dispatch |
| `scripts/preflight-issue.sh` | Mechanical authoring checks; refuses a known-defective issue |
| `scripts/dispatch-issue.sh` | Runs one round under a wall-clock and stall watchdog |
| `scripts/await-dispatch.sh` | Blocks inside a tool call so waiting is not a decision |
| `scripts/set-issue-status.sh` | Moves an issue's status; refuses invalid values |
| `scripts/tally-local-tokens.sh` | Per-issue local token volume from OpenCode's SQLite |
| `assets/AGENTS.md.template` | Rules for the implementer, in the file it actually loads |
| `assets/dispatch.conf.template` | Per-project configuration for every script here |
| `assets/issue-template.md` | Issue shape with Givens, mutations, and a baseline count |
| `assets/cost-ledger-template.md` | Where measured figures go the turn they are reported |
