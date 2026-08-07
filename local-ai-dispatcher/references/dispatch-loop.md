# The dispatch loop

## Rule zero: the primary checkout never leaves the default branch

It is the checkout a human watches, and it is where merged work becomes visible.
Never switch it to an issue branch and never run a dispatch in it.

The first dispatch on the reference project ran in the primary checkout, which put
it on an issue branch for ~40 minutes. The default branch was then checked out
nowhere, so **no finished issue could be merged** — seven completed branches
queued behind one running round while the repository read as idle.

`git merge --squash` cannot target a branch checked out elsewhere, which is what
turns this from an inconvenience into a blockage. The clean-tree precondition
compounds it: no other work can happen in a tree while a round runs there. That is
what makes one-worktree-per-issue **mandatory rather than merely tidy**.

Worktree naming matters too: per-issue token attribution reads the working
directory, so `../proj-NNNN` is what makes the tally work. A dispatch in the
primary checkout lands in `(main)` with no issue attached.

## The loop

```sh
# 0. worktree, branch, and push it EMPTY
git worktree add -b issue/0012 ../proj-0012 main
cd ../proj-0012 && git push -u origin issue/0012

# 1. claim it — preflight refuses an unclaimed issue
scripts/set-issue-status.sh 0012 in-progress

# 2. author to code level; check it before spending a round
scripts/preflight-issue.sh 0012

# 3. dispatch, from a SUBAGENT, backgrounded
scripts/dispatch-issue.sh 0012 --round 1

# 4. block until it exits; 75 means call again
scripts/await-dispatch.sh 0012

# 5. review by re-running and mutating (see references/review.md)

# 6. commit the round to the branch, push immediately
git add -A && git commit -m "#0012 round 1: <what it did>" && git push

# 7a. accept → squash-merge from the primary checkout, push both
# 7b. reject → write a '## Review' section, dispatch --round 2
```

### Push immediately, merge immediately

**Push the branch when it is created and after every round. Squash-merge and push
the moment an issue resolves. Do not batch.**

Work that is committed but unpushed is invisible, and invisible work is
indistinguishable from no work — this happened once with seven finished branches
sitting unpushed while the default branch looked idle. Separately, six issues once
resolved before any of them landed; progress is only legible when it arrives one
issue at a time.

### Keep the branch, forever

```sh
cd ../proj-main            # a worktree on the default branch, or the primary checkout
git merge --squash issue/0012
git commit -m "#0012 <issue title>"
git push origin main
git push origin issue/0012      # keep the branch — it is the artifact
```

`git merge --squash` records **no merge ancestry**, so the branch is the only
surviving record of how the work went, and the issue's `**Commit**` row points into
it. The default branch answers "what changed for this issue"; the branch answers
"how did it go". Do not rebase the per-round commits tidy — the sequence *is* the
record.

## Dispatch through a subagent, never the main loop

An OpenCode transcript is long and worthless once the outcome is known. A subagent
absorbs it and returns a verdict. **Keeping the main context small is what makes
authoring and reviewing good, which is what makes the local model work at all.**

The dispatcher subagent's whole job:

1. Run `scripts/dispatch-issue.sh NNNN --round N` in the background.
2. Call `scripts/await-dispatch.sh NNNN` repeatedly until it exits 0.
3. Return the diff summary, the real verification output, and whether it converged.

### The failure this shape keeps producing

**A dispatcher subagent can end its turn while its round is still running.** A
subagent's turn ends when it emits text without a tool call, so *"I'll verify once
it exits"* is not a promise it can keep — nothing wakes it. The round ran to
completion unwatched and unverified.

Three attempts at fixing it, and only the third worked:

1. *"Poll until the process actually exits; do not report before then."* **It
   recurred**, with that exact instruction in the prompt: *"Baseline captured.
   Waiting for the dispatch to exit."*
2. *"If you are about to write 'waiting' or 'I'll check back', make another tool
   call instead."* Better, and still an instruction.
3. **`await-dispatch.sh`.** Waiting stops being a decision. The script blocks
   inside a tool call for a budget under the foreground limit, then exits **0** if
   the dispatch finished or **75** meaning *call me again*. The agent either holds
   a result or must make another call.

The difference: the first two asked the agent to recognise a boundary it
demonstrably cannot see; the third removes the boundary.

**And the recovery is what actually matters.** Resuming a subagent from its
transcript costs a round-trip and nothing else — but only if the stop is noticed.
**Treat a dispatcher whose report contains no verification results as unfinished,
not as a status update.** That check is on the reader, needs no cooperation from the
agent, and has caught it both times.

### One good refusal, worth recording

A dispatcher hit the "round > 1 needs a `## Review` section" guard, tried `--force`,
was denied by the permission layer, and then **stopped rather than route around
it** — explicitly rejecting three workarounds it had already identified:
re-dispatching as round 1 (which would overwrite the previous log and misattribute
the cost), renaming that log (deleting the guard's input to defeat the guard), and
writing the `## Review` section itself (a spec edit, not the dispatcher's to make).

That is the behaviour the guards are for. Log the successes as well as the
failures, or the guards read as friction.

## Round outcomes and what each means

| Exit | Meaning | Next move |
|---|---|---|
| 0 | The round ran and changed something | Review it |
| 3 | Round cap | The issue is underspecified or too large. Rewrite or split — do not `--force` |
| 4 | Dirty tree | Commit or discard the previous round first |
| 7 | **No changes** | A failed round. Write the `## Review` section in this turn; never re-dispatch unchanged |
| 8 | Wrong branch | You are probably in the primary checkout |
| 9 | Preflight rejected the issue | Fix the issue text, commit the planning update |
| 10 | Unchanged issue, or no `## Review` | Write it. "Nothing to review" is itself the review |

Two things the exit code will **not** tell you, both of which the script prints
separately:

- **`opencode run` exits 0 after a terminal sandbox rejection.** The script scans
  the log for `auto-rejecting` and surfaces every hit with its context. Check the
  rejected path for a typo before blaming the model — a mistyped absolute path is
  the usual cause, and has killed two rounds.
- **A round can claim a passing test count it never measured.** One invented the
  arithmetic; one wrote "all tests pass, zero failures" while four failed. The
  script runs the verification command **itself** after every round and writes the
  real line into the round's own log, so the claim and the fact sit in one
  artifact.

## Status is part of the work

| Transition | When | By |
|---|---|---|
| `open` → `in-progress` | **before** dispatching a round | `set-issue-status.sh` |
| `in-progress` → `resolved` | passed review **and** squash-merged | `set-issue-status.sh` |
| `in-progress` → `open` | round cap hit, or the issue is being rewritten or split | `set-issue-status.sh` |
| `in-progress` → `wontfix` | the work turned out not to be worth doing | `set-issue-status.sh`, and say why |
| `resolved` → `closed` | **the owner confirms** | never an agent |

**Resolved means merged, not merely accepted.** A round that passes review but sits
unmerged is still `in-progress`; that is what stops a green branch being mistaken
for landed work.

**Set it back to `open` when a round is abandoned.** An issue stuck at
`in-progress` with nothing running is worse than one marked `open`, because it
reads as claimed and nobody picks it up.

Preflight refuses to dispatch an issue that is not `in-progress`, so claiming it is
a gate rather than a habit.

## When an issue cannot be finished

1. Commit whatever is worth keeping to the branch, or discard it. Do not leave
   half-done work uncommitted — the next dispatch refuses a dirty tree.
2. Revert status to `open`.
3. Add a `## Notes` section: which rounds, what failed each time, and **what the
   next author should change about the issue itself**.
4. Commit the markdown on the branch.
5. Leave the branch in place, unmerged. It is the record of the attempt and where
   the next one starts.

Three failed rounds is information about the **issue**, not just about the model.
Never use `wontfix` or `closed` to escape a stuck issue.
