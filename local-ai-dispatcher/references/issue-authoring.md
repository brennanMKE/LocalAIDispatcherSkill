# Authoring an issue for a local model

An issue is a **contract about an unfamiliar codebase**. The author has read it;
the implementer has not. Every type the work must touch is a place where "obvious"
diverges between them — and the model's guess will be idiomatic, plausible, and
wrong.

A task is ready when an implementer could follow it **without a judgement call**.

**Read `worked-example.md` first if you have not.** It shows one real task written
both ways — prose and code level — with what each version cost. Everything below
is the general form of that one comparison.

## The standard, in five rules

1. **Name every path in full**, repo-relative. `Sources/Engine/WhereAmI.swift`, not
   "the engine".
2. **Paste every signature the round must call**, and the public members of each
   result type.
3. **Paste the literal change** where it is small — the expression, the line, the
   record layout.
4. **State measured before-and-after values**, and say they were measured. Raw
   bytes, real command output, actual counts.
5. **One deliverable.** If the Expected behavior has two verbs in it, split it.

### The cleanest evidence for rule 2

One round timed out at 1800s having rewritten its test file **26 times**,
discovering signatures by compile error — `foo(at:)` vs `foo(path:)`, `ListItem`
vs `Entry`, `result.description` vs `result.error?.description`. Its own final
notes listed every correction, so it had the answers with a minute left on the
clock.

Pasting five declarations into the issue took round 2 to **17 edits, finished
inside the clock**. Nothing else changed.

### The cleanest evidence for rule 1 + naming collaborators

A different issue named its output file, its twelve fields, and its acceptance
criteria — and named **no collaborators**. The round wrote 679 lines against a
protocol and a platform type it invented as an injection seam, and **did not open
the real collaborator's source file until the last five lines of a 1443-line
log**, after four rewrite cycles against phantom types. The cap killed it with no
test file written at all.

A path says where code goes and nothing about what it may **call**. A model with
no stated API will infer one, reaching reasonably for something injectable,
because that is what testable code usually looks like.

So: quote the real surface, **and say explicitly when there is no abstraction to
implement.** "`GitProcess` is a concrete `Sendable` struct constructed as
`GitProcess()`; the tests run against real repositories, so there is nothing to
inject." That sentence, absent from round 1, was the whole difference.

## The Givens rule — the one that has cost the most

> **Nothing goes in a Givens block that has not been executed.** Not reasoned from
> something executed — *executed*, in the same context the model will run it in.

A Givens block converts the author's confidence into the model's **constraint**.
When the author is right it saves a round; one issue went from 1289s to 139s on
exactly that mechanism. When the author is wrong it removes the model's licence to
notice, and the round spends its whole budget forcing the error to work instead of
reaching for the thing that does.

The failure that produced this rule: an issue told the implementer to locate a
built binary with a one-line snippet under a heading reading **"Givens — verified,
treat as true"**. The snippet matches nothing in that context. The round was killed
at the full cap having produced a structurally correct test that could never find
the binary.

**What was actually verified was something adjacent.** The author had confirmed
the binary and the test bundle are siblings on disk — true — then *reasoned* from
that to a snippet and labelled it fact.

If you want to suggest an unverified approach, it goes in **Notes as a
suggestion**, where disagreeing is allowed.

**Corollary for review:** when a round burns its whole budget on one obstacle,
suspect the givens before suspecting the model.

## Probe before you author

Three levels, each cheaper than the round it saves.

### Probe the tool, not its `--help`

`--help` documents the interface; only execution reveals the **output shape**, and
the output shape is what the integration depends on. An icon generator's help text
is accurate and says nothing about the one fact that decides the task: it emits
`AppIcon-macOS.appiconset` while the build setting expects `AppIcon`. A model
following the help faithfully would have produced a correct icon set the build
ignores entirely.

### Re-probe, even a previous verification

A probe run one day was accurate about everything it asked. Re-run the next day
before dispatch, it turned up three things it had not asked about — including that
**git already reported the field the issue asked someone to compute**, and that two
commands write to **stderr**, so a round parsing stdout would report "nothing to
do" for every repository in code that looks entirely correct.

Then the finding that reversed a design decision: a prune command cannot
distinguish a *moved* worktree from a *deleted* one, and reaping a moved one is
unrecoverable. So the command reports by default and prunes only under an explicit
flag. That is not a preference; it is the probe.

### Probe the code the issue is about

**Run it, on the input the issue is about, before writing a word.**

One parser was fed real bytes from a fixture containing a rename, a submodule, a
path with a space, a path with a newline, a conflict, an untracked file and an
ignored file — seven records in, six out. Then a record whose path was two
non-UTF-8 bytes: **zero** out, the entire status silently empty.

Three defects, none visible from reading, none catchable by the existing tests:
renames dropped by an off-by-one; one bad byte erasing everything; submodule state
read into a variable and never used.

> **The issue that came out of that probe is a repair with five named mutations
> and a measured before-count. The issue written from reading the source would
> have been a feature request.** It took four minutes.

It also settled a requirement that could not be built — the tool has no copy
detection at all — which a round would otherwise have spent itself discovering, or
worse, invented a state nothing can produce.

## Sizing

**A useful check: could one person finish this in a single sitting without
deciding where anything goes?** If not, split it.

- An issue that names more than one new file is probably too big.
- A deliverable over roughly 200 lines should be split **before** dispatch.
- Prefer **pure functions returning values** over anything that prints. A function
  returning a string can be asserted; one that writes to stdout needs a subprocess
  test, which is a separate issue — and the model reaches for printing by default.
- Prefer **repair framing over greenfield**. Types and signatures first, build,
  then bodies. A file with two working functions is a foundation; a file with
  twelve stubbed ones is a liability, because the next round inherits the
  confusion rather than the progress.

## Criteria that cannot be satisfied vacuously

Each of these is a rejected round in one costume.

| Trap | Fix |
|---|---|
| A metric with no baseline | State what N must **change to**. "Prints `N tests`" is satisfiable by a round that adds nothing to the run. |
| An "or" plus a "with" | Ask: is that three cases or **two-by-two**? Enumerate the cross product. A round shipped tests for each half and never built the case with both — the only case its code got wrong. |
| A criterion phrased as an **absence** | It can be met by **deleting** the thing it constrains. Phrase it as a presence: "an explicit X exists AND its members are …". |
| "Prints the version envelope" | Name the expected **content**, not that something was produced. |
| A grep-based criterion | Run the grep against **known-bad input** first and confirm it fires. A quoted-literal search misses interpolation and returns clean while proving nothing. |
| An in-process test for an out-of-process contract | If the criterion is about what a *caller* observes — stdout bytes, exit status, a hook firing — say explicitly that a test which does not spawn a process cannot satisfy it. |
| "Write tests" in a separate section | It reads as advice on *how* to test, not as a deliverable. Put **"`<path>/FooTests.ext` gains tests; `git diff --name-only` lists two files"** in Expected behavior, where the round reads what it owes. |
| Naming a constraint without the affordance | "You will need X" invites reinvention. **Grep for whether X already exists** and name it. A round reconstructed a fixture badly because the issue never mentioned the helper that already built exactly that state. |
| A fixture given as a table | A table says what to build; only the **mechanism** says what breaks if you build it slightly wrong. |
| "The default is X" | A default needs a **parameter**, and a parameter needs a **signature**. Write the signature into the issue, or the round produces two unrelated functions with nothing choosing between them. |
| Specifying a **deletion** | Ask what else that line is the only thing doing. One removal fixed the named bug and broke parsing for every record after the first, because the same call had two jobs. A one-line framing invites a one-line answer. |

## Two more rules the harness cannot enforce

**Tell the round not to re-measure what the issue already measured**, and not to
run the suite before writing anything. Two full test runs piped into context
before any work forced a compaction, and the summary that came back had invented
four prior rounds and a list of test names that did not exist. The model then
worked from all of it.

**If the deliverable is prose, say that elaboration is not wanted.** Prose has no
test. A round asked to correct three doc comments passed *every* mechanical guard
and left the file **less accurate than it found it** — each correct fix padded with
confident, fabricated detail. Require that each sentence name something visible in
the code: *a doc comment may not contain a claim that would need a test to be true.*

## Re-author the backlog before dispatching it

An issue written before this standard existed **is not ready**, however complete it
looks. The first two planning passes on a mature backlog each found a defect in
text the author had written and believed:

- A Givens block named a function with the wrong argument label — the exact class
  that cost another issue its clock.
- It described an output format as merely *omitting* a field when, measured, that
  format also carries an explicit extra line.
- One issue's criterion was **unimplementable as written**, because the fixture
  helper presets the very config value the criterion asked about being unset.

Four corrections across two issues, every one a fact written from memory. The two
issues grew from 50 to 267 lines and from 53 to 395.

Author an issue when it reaches the **front of the queue**, not earlier — authoring
against a tree that will have changed by the time it runs is how one round failed
outright.

## Template

`assets/issue-template.md`, and `worked-example.md` for the same task written
badly and then well.
