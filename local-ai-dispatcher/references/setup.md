# Setup — standing up the harness

Everything here failed **silently** on a real project: no error message, no
non-zero exit, just a round that produced nothing or a rule the delegate never
saw. `scripts/setup-check.sh` implements every mechanical item; this file is the
reasoning, and the items no script can decide.

## The pieces

| Piece | Role | Notes |
|---|---|---|
| **LM Studio** (or Ollama, llama.cpp) | Serves the local model on an OpenAI-compatible endpoint | Default `http://127.0.0.1:1234/v1` |
| **OpenCode** | The agent loop the local model drives — tools, file edits, sandbox | Reads `AGENTS.md` |
| **A hosted agent harness** | Authoring, dispatching via subagent, review | Claude Code in the reference project |
| **git worktrees** | One per issue, so rounds never contend for the tree | Mandatory, not tidiness |

The local model does not need to be good at everything. It needs to be good at
*applying a fully specified change*, which is a much smaller ask than the one
people usually make of it.

## Model choice

The reference project used **Ornith 1.0 35B-A3B (8-bit MLX)** — a MoE, non-thinking
model. That combination is the point: the thinking happens when the **issue is
authored**, not when it is implemented, so fast-and-non-thinking is the right trade
for work that has already been thought through. A dense thinking model is slower
per round for no gain on a task where the plan is already written down.

Judge a candidate on one question: given a file path, five pasted signatures, and
a literal before-and-after, does it produce the edit in one pass?

## The checklist, and what each item cost

### 1. `AGENTS.md`, with the rules inlined

**OpenCode reads `AGENTS.md`. It does not read `CLAUDE.md`.**

This was verified, not assumed. Asked to state a licensing rule from preloaded
context with only `CLAUDE.md` present, the model answered **`UNKNOWN`** — while
claiming `CLAUDE.md` was in its system prompt. With `AGENTS.md` present it recited
the rule correctly. Every licensing and code-signing rule was invisible to the
delegate, and nothing errored.

Inline the non-negotiables. **Do not reference another file** — a model that
ignores "do not read any files" will also not follow a pointer. Keep the canonical
copy wherever it lives and mirror any edit in the same commit.

**Verify by recitation**: ask the model to state a rule with no file reads. If it
says `UNKNOWN`, the file is not reaching the system prompt and nothing else will
tell you.

Start from `assets/AGENTS.md.template`.

### 2. The output-token cap

`~/.config/opencode/opencode.json` sets `limit.output` per model. At `8192`, that
budget must hold the model's reasoning **and** an entire file, JSON-escaped, inside
one `write` tool call. A ~550-line deliverable does not fit: the generation is cut
off mid-call, the `content` key never arrives, and the schema rejects it.

```
✗ Write failed
Error: The write tool was called with invalid arguments: SchemaError(Missing key at ["content"]).
```

One round emitted that **188 times over 25 minutes** and produced nothing. Its
reasoning was correct and complete — it had independently derived the right design
and named every type it intended to create. All of it was lost to a truncated JSON
payload, and reading only the outcome would have concluded the model could not do
the task.

**It is intermittent in exactly the way that hides the cause**: 188 occurrences in
one round, 20 in another, zero in twenty more. Small edits fit; large greenfield
files do not. So it reads as flakiness rather than as a ceiling.

Raise it to **16384**. The trade is input budget inside the same loaded context —
more frequent compaction is cheaper than a round that emits nothing.

Two separable lessons: *a symptom that looks like model incompetence can be a
numeric limit*, and *a ceiling is not something a retry can clear*.

```json
{
  "model": "lmstudio/<model-id>",
  "provider": {
    "lmstudio": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:1234/v1",
        "timeout": false,
        "headerTimeout": 300000,
        "chunkTimeout": 300000
      },
      "models": {
        "<model-id>": {
          "limit": { "context": 65536, "output": 16384 },
          "options": { "temperature": 1.0, "top_p": 0.95 }
        }
      }
    }
  }
}
```

### 3. The parallel limit, which is silent

LM Studio's `PARALLEL` setting caps concurrent requests. A dispatch beyond it
**queues rather than running**, with no indication — it simply appears to take a
very long time. Check `lms ps` before planning any fan-out. Two concurrent rounds
was the real ceiling in the reference project; raising it is untested.

### 4. There is no `timeout` binary on macOS

`timeout` and `gtimeout` are both absent without coreutils. A dispatch with no
wall-clock bound can loop indefinitely, which had already happened before the
guard existed. `dispatch-issue.sh` backgrounds the run and spawns its own watchdog
that `TERM`s then `KILL`s. Verify it by triggering it.

It needs a **second** watchdog for a different failure: a hung inference request
writes a session row with 0/0 tokens and no finish reason, then sits silent.
OpenCode's own `chunkTimeout` did not fire; 27 minutes of dead air followed before
the wall-clock guard did. The log's mtime is the cheap, reliable signal — a live
round appends to it constantly. On its first real firing the stall watchdog killed
a dead round at 720s instead of 1800s.

### 5. The sandbox, and where scratch files go

OpenCode auto-rejects writes outside the working directory — `/tmp`, `/var/tmp`,
`$TMPDIR`, anything under `~` that is not the worktree:

```
! permission requested: external_directory (/tmp/*); auto-rejecting
Error: The user rejected permission to use this specific tool call.
```

**That rejection is terminal.** The run ends where it happens, sometimes mid-edit
with the tree non-compiling — and `opencode run` still exits 0, so without a scan
for `auto-rejecting` in the log the harness reports a successful round.

Four rounds were damaged or lost to it across three escalating fixes (the issue,
then `AGENTS.md`, then the dispatch prompt itself). The escalation ladder failed;
see `references/failure-modes.md` on why. Two things that do work:

- Point every scratch write at a gitignored directory **inside the worktree**, and
  say so in `AGENTS.md` *and* the dispatch prompt. This converted *fatal* into
  *survivable* — a later round absorbed the rejection and worked for another
  twenty minutes.
- **Generate the bytes yourself and paste them into the issue** rather than asking
  the model to discover them. Capturing five records of real command output takes
  the author under a minute in a directory they are allowed to write to.

The untried fix, still the right one if it keeps happening: change the sandbox
permission config directly.

Note the asymmetry: a **test runner** spawned by the verification command is not
sandboxed, so a test framework's own temp directories work fine. Only commands the
model runs itself are restricted.

### 6. Repository layout

- The **primary checkout stays on the default branch, permanently.** Never
  dispatch in it.
- One worktree per issue: `git worktree add -b issue/NNNN ../proj-NNNN main`.
- **Push the branch when it is created**, empty, before any work.
- Add the run-log directory and the scratch directory to `.gitignore`.

`git merge --squash` cannot target a branch checked out elsewhere, which is what
turns a pinned default branch from an inconvenience into a blockage.

### 7. Decide how cost will be measured *before* the first round

Retrofitting cost data onto completed work recovers only what the harness happened
to report along the way. See `references/cost-accounting.md`.

## Scripts are not reliably given `cat` or `date`

A script run through an agent harness's shell tool may not have `cat` or `date` on
its PATH even when the calling shell does — `ls`, `sed`, `grep`, `awk`, `sort` and
`tail` all worked in the same script. Use zsh builtins: `$(</dev/stdin)` and
`zmodload zsh/datetime; strftime` / `$EPOCHSECONDS`. They are better anyway. Assume
any script here that shells out to `cat` or `date` is broken until it has been run.
