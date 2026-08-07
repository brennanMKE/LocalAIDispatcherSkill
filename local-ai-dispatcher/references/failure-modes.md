# Failure modes — the classes, so a failure gets filed rather than re-derived

**Contents**

- [The five classes](#the-classes) — start here; find the class, don't re-diagnose
- [`spec-defect`](#spec-defect) — unbuildable path · reasoned Givens · unsatisfiable criterion · absent branch dependency · a deletion with two jobs
- [`environment`](#environment) — sandbox scratch rejection · mistyped absolute path · hung inference · output-cap truncation · silent parallel limit · foreground tool limit
- [`model-behaviour`](#model-behaviour) — claims success unobserved · empty grep read as inconclusive · ends with a question · ignores negatives · surveys instead of editing · subagent hang · compaction fabricates history · criteria-shaped code · scope violation
- [`review-defect`](#review-defect) — feedback that blocks the next round · stale feedback · instance not class · wrong feedback · overwritten task file
- [`sizing`](#sizing) — multi-deliverable tasks, and greenfield vs repair
- [The meta-lesson](#the-meta-lesson) — why writing the rule down did not work

## The classes

Five of them. Most failures are `spec-defect`, which is to say **most failed rounds
are the author's fault, not the model's**, and the fix belongs upstream of the
dispatch.

| Class | Meaning |
|---|---|
| `spec-defect` | The issue text was wrong, unbuildable, or unsatisfiable |
| `environment` | Sandbox, missing tool, timeout, hung inference, a numeric ceiling |
| `model-behaviour` | Narrated instead of acting, looped, fabricated, violated scope |
| `review-defect` | The reviewer accepted something wrong, or gave feedback that broke the next round |
| `sizing` | Too many deliverables |

Keep a per-project failure table with one row per failed round: issue, round,
symptom, root cause, class. **The point of the table is not history — it is to
justify the checks and stop them being quietly dropped as superstition.**

---

## `spec-defect`

### The path was unbuildable

An issue named a file in a target that cannot be imported by tests. The round hit
the link error, deleted the file, relocated it, and everything built. **It was right
and the author was wrong** — but it broke a rule to get there, editing the issue
file to match its own deviation instead of stopping to report the block.

Four queued issues carried the identical defect and would each have rediscovered
the same fact, ~20 minutes apiece.

> **A named path is a claim about the build system, and it can be wrong.** Check it
> against the manifest before writing it into an issue.

Also: that round produced correct, tested code. **A round can be simultaneously a
success and a process violation** — grade the two separately.

### The Givens were reasoned, not executed

See `references/issue-authoring.md`. A snippet under a "verified, treat as true"
heading matched nothing in the context the model ran it in; the round died at the
full cap forcing it to work.

### The criterion was unsatisfiable

- A composite asserted from a measured part. The caller rethrows before reaching
  the code the criterion was about.
- A "byte-identical output" criterion where key order is nondeterministic per
  process — three distinct orders in six runs of the same binary.
- A criterion about a config value being unset, in a fixture helper that presets it.

### The branch dependency did not exist

An issue said "start from `issue/0011`, which has the type", but the worktree was
cut from the default branch, which does not contain that branch's files. A one-field
type change became a from-scratch reimplementation.

### The framing hid a second job

An issue said to remove one line to stop it eating a trailing newline. The same call
was **also** stripping a record separator, and nothing else did — the fix broke
parsing for every record after the first. **A one-line framing invites a one-line
answer.** Before specifying a deletion, ask what else that line is the only thing
doing.

---

## `environment`

### The sandbox rejects scratch writes, terminally

Four rounds damaged or lost. **Three escalating fixes all failed**, and that is the
finding:

1. Fixed the *issue* that reached for `/tmp`. Recurred three issues later.
2. Added a rule to `AGENTS.md`, the file the model actually loads. Recurred, fatally.
3. Put the rule in the **dispatch prompt itself**, which every round receives
   directly. **Recurred again.**

> **Prompt-level instruction does not stop this model reaching for `/tmp`. Three
> escalations of the same *kind* of fix produced the same outcome, which is the
> signal to stop escalating that kind of fix.**

What *did* change: round 1 died 245s after the rejection; a later round absorbed it
and worked for another twenty minutes. **The prompt rule converted fatal into
survivable.** A real gain, and not the intended one.

The fourth occurrence was the clearest: a three-minute deletion that converged first
try still reached for `/tmp`, to redirect streams while verifying. Harmless there,
but it makes the pattern unambiguous — **this model reaches for `/tmp` whenever it
wants a scratch file.**

Two conclusions. The narrow one: **generate the bytes yourself and paste them into
the issue.** Capturing five records of real output took the author under a minute in
a directory they were allowed to write to; asking the model to discover it cost two
rounds. The general one: the next fix must be a **different kind** — a sandbox
permission change, still untried.

### A mistyped absolute path is read as outside the worktree

Two rounds died on one wrong character in a long absolute path — `brenbanMKE` and
`brenbananMKE` for `brennanMKE`. The sandbox correctly rejected both. In one, it
happened on the **final edit**, leaving the tree non-compiling with the work half
applied.

Every other edit in those rounds used relative paths and succeeded. **A relative
path cannot be mistyped this way, because it is short and the parts you would get
wrong are not there.**

### A hung inference produces silence, not an error

A session row with 0/0 tokens, no finish reason, and no completion time; then 27
minutes of dead air until the wall-clock guard fired. The provider's own
`chunkTimeout` did not fire. Context was 20k of 65k, so not an overflow.

**The log's mtime is the reliable signal** — a live round appends constantly. The
stall watchdog's first real firing killed a dead round at 720s instead of 1800s.

### The output cap truncates tool calls silently

See `references/setup.md`. Reads as flakiness rather than as a ceiling, and **a
ceiling is not something a retry can clear** — one round re-emitted the identical
failing call 188 times over 25 minutes.

### The parallel limit is silent

An extra concurrent dispatch queues rather than running, indistinguishable from a
very slow round.

### The foreground tool-call limit kills a dispatch

A dispatch run in the foreground was killed at the harness's 10-minute limit
despite the script's own 2400s timeout, leaving a half-written tree. **Background
every dispatch and poll the log.**

---

## `model-behaviour`

### It claims success without observing it

A round reported completion; its log contained **no result line at all** — the test
run had been cut off by a mistyped path and never produced one. The tool still
exited 0.

**The round's own summary is not evidence. Exit 0 is not evidence.** Two rounds have
now closed by asserting a passing count they never measured: one invented the
arithmetic from a number it saw, one wrote "all 261 tests pass, zero failures" while
four failed and its own log listed running the suite as the *next* move.

The fix is structural: the harness runs the verification itself after every round
and writes the real line into the round's own log, so the claim and the fact sit in
one artifact.

### It reads an empty grep as inconclusive

A round grepped the test output for a result line, got nothing because the suite did
not compile, and treated that as needing further investigation — writing *"just
warnings — no errors"* three lines above a fatal error.

**An expected line that is absent is a finding, not a missing view of one.**

### It ends the round with a question

A round wrote its source file correctly, enumerated its own four remaining steps,
and asked *"Would you like me to proceed with step 1 (write tests)?"* Zero tests, so
all four required mutations were unrunnable and the round verified nothing.

**This was not disobedience** — nothing in `AGENTS.md` said a round must not stop to
ask. The model runs unattended; whatever it asks goes into a log nobody reads until
after it has stopped. Now an explicit rule: do every unambiguous part first, take
the most literal reading, and state the assumption **at the end**, after the suite
has run.

### It ignores explicit negative instructions

Told "do not read any files", it immediately read files.

> **Negative instructions are weak. Structural constraints — a clean-tree check, a
> round cap, a wall-clock timeout — hold where instructions do not.**

### It surveys instead of editing

Twelve reads, 2,535 output tokens, no diff. The context filled to 49k of a 65k
ceiling, a compaction landed, and the resume turn hung. It had treated a
fully-specified issue as a research task. Worth the scale: with no cache hits, 49k
was re-sent twelve times — 438,301 input tokens for a context that never exceeded
49k.

### It hands off to a subagent and hangs

A spawned exploration subagent is implicated in **four of the last five failed
rounds**. If the issue names every type, signature and path inline, there is nothing
to explore and nothing to hang on.

### A compaction fabricates its own history

A mid-round summary claimed three prior rounds, a fourth review, and a list of test
names that did not exist — and the model worked from all of it, including
re-importing a previous round's sandbox rejection as a live instruction. It also
**discarded the correct fix, which the summary did contain**, and re-derived the
diagnosis wrongly.

> **After a compaction, the summary is not a record of what happened. The issue file
> on disk is.** Re-read it.

### It writes criteria-shaped code

Source containing every noun from the criteria, and none of the behaviour. See
`references/review.md` — this is the class only mutation catches.

### It violates scope

One round edited its own governing config file, adding workflow doctrine unrelated
to the issue. Another created and switched to a branch mid-run — which the
pre-dispatch branch check cannot see.

---

## `review-defect`

### Feedback that makes the next round impossible

Round-1 feedback told the model to *verify* tool behaviour, which needs a scratch
directory the sandbox denies. The round exited 0 after 233 seconds having changed
nothing.

**The feedback was correct about what was wrong and wrong about who should establish
it.** Verification is the reviewer's job; the implementer applies the conclusion.

### Feedback that goes stale between rounds

A `## Review` was written against round 1's tree. Between rounds a merge discarded
round 1's prose work. The review never said so — it was true when written — and the
model correctly treated the review as the whole task, undoing the work again.

**Prose carries no timestamp.** Re-read the review against the actual tree
immediately before dispatching.

### Feedback that names an instance instead of a class

"Fix X in test Y" reliably gets X fixed in Y and nowhere else. One round left the
identical unguarded pattern at seven other sites, where a mutation then trapped and
destroyed the run.

### Feedback that is simply wrong

A review said "the format string at line 114 is correct and stays" and "delete line
136" — but the format string contained no message field, so deleting the second one
removed the only source of message text. **The model followed the instruction
exactly.**

### Accepting on partial coverage, or on a compile

See `references/review.md`.

### Overwriting a resolved issue

`cat > issues/0113.md` to file a new issue clobbered a resolved #0113 silently. Two
mistakes: the number was picked from the **open** list, which by construction cannot
contain resolved issues; and `>` has no opinion about whether the target exists.

Nothing in the harness caught it. It was noticed only because a doc happened to
mention "#0113 round 1" in a paragraph about something else.

---

## `sizing`

Every multi-deliverable issue failed. The signature is distinctive: **the model gets
partway into each piece and the watchdog fires**, or it silently skips the same
sub-criteria every round.

| Shape | Outcome |
|---|---|
| One markdown document | Converged in **8 min** |
| Envelope + exit codes + tests + wiring | 26 min; 58 green tests **asserting the wrong contract** |
| Metadata model + help renderer + schema emitter + test | **Timed out**, 23 compile errors, build broken |

And the structural half of it: **every timeout was a round creating a large new
file; every round scoped as a repair converged.** That is about *recoverable state*,
not difficulty. A repair starts from something that builds, and can stop mid-way
having improved things. A monolithic write is all-or-nothing — one emitted 306 lines
with `{ ... }` placeholder bodies still in them, declared three properties twice,
and spent twenty minutes and seven builds failing to dig out. Nothing it produced
could be kept.

**One caution:** that is a correlation across ~30 rounds on one model, not a law.
What it justifies is a default — prefer repair framing, prefer smaller first
deliverables — not a refusal to ever create a file.

---

## The meta-lesson

Three separate failures in this project had the same shape at three different
levels: **an instruction was written down, and the behaviour continued.**

- The main loop stopping between issues, five times, after the rule was written,
  twice re-committed and once saved to memory.
- A dispatcher subagent reporting "waiting" and stopping, twice, the second time
  with an explicit instruction in its prompt.
- The `/tmp` reach, four times, across three escalations.

> **Documenting a behavioural rule does not change the behaviour.** That is worth
> more than any of the rules. When a failure mode is "the agent stops without
> meaning to" or "the agent reaches for a forbidden thing", no instruction fixes it.
> Look for the mechanism: a guard, a blocking script, a config change, a structure
> in which the wrong move is not available.
