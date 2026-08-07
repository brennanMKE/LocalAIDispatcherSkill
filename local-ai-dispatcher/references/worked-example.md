# Worked example — the same task, written twice

This is the single highest-leverage thing in the skill, because it is the rule
doing the most work and the one hardest to believe in the abstract:

> **Tasks carrying measured code converged in one round. Tasks describing the
> work in prose did not.**

Below is one real task, written both ways, with what each version actually cost.
Nothing about the code, the model, or the harness changed between them.

The example is Swift. **The mechanism is not** — see "What transfers" at the end.

---

## The task

A public function returned a public type whose members were internal. An
out-of-module caller could obtain the value and do nothing with it. No test could
catch it, because the test target used a privileged import that grants internal
access — the tests and a real caller were compiling against different modules.

The work: add a test target that imports **without** that privilege, so the
boundary is checked the way a caller sees it.

---

## Version 1 — prose. Timed out at 1800s.

```markdown
## Description

`gitStatus` returns a public type whose members are internal, so it is unusable
from outside the module. Our tests can't see this because they use
`@testable import`.

## Expected behavior

- [ ] Add a test target that imports YardGit without `@testable`.
- [ ] It should exercise the main public entry points to prove they're reachable
      from a real caller.
- [ ] Make `entries` public so the type is usable.
- [ ] `swift test` passes.
```

Everything in that is true, and a competent human would have no trouble with it.

**What the round actually did:** discovered every signature by compile error.
`worktreeList(at:)` vs `(path:)`. `WorktreeListItem` vs `WorktreeEntry`.
`result.description` vs `result.error?.description`. It rewrote its test file
**26 times** and ran the suite **19 times**, hit the wall clock, and left the tree
non-compiling — a botched edit had trapped a doc comment inside an unterminated
literal.

Its own closing notes listed every correction it had figured out. **It had the
answers and ran out of clock.**

The half that was right is worth noting: the new target *did* import without the
privilege, and the manifest declared it correctly. The model understood the point.
It could not afford the archaeology.

### Why prose fails here specifically

"Exercise the main public entry points" names **five** functions without saying
what any of them is called or what they return. A path says where code goes and
nothing about what it may **call**. Every one of those is a place where "obvious"
diverges between the author, who has read the codebase, and the implementer, who
has not — and the model's guess will be idiomatic, plausible, and wrong.

---

## Version 2 — code level. 17 edits, finished inside the clock.

Same task. The only change is a Givens block containing five declarations, copied
out of the source rather than recalled.

```markdown
## Givens — measured on `main` on 2026-08-07, treat as true

Five entry points this target must call, pasted from source:

```swift
public func whereAmI(at path: String) throws -> WhereAmI
public func gitStatus(at path: String) throws -> WorktreeStatus
public func worktreeList(at path: String) throws -> [WorktreeEntry]
public func worktreeRemove(_ name: String, at path: String) throws -> RemoveResult
public func yardWhere(_ args: [String]) -> Envelope
```

The members each result type exposes:

```swift
public struct WorktreeStatus { public let branch: String?; let entries: [Entry] }
public struct WorktreeEntry  { public let path: String; public let locked: Bool }
public struct RemoveResult   { public let removed: Bool; public let error: Failure? }
public struct Envelope       { public let ok: Bool; public let result: String? }
```

Note `WorktreeStatus.entries` has NO access modifier — that is the defect. It is
internal, and a caller outside the module cannot read it.

**There is no protocol to implement and nothing to inject.** These are free
functions over real repositories built by `FixtureRepository`.

Measured, in a throwaway package depending on the product:

    error: 'entries' is inaccessible due to 'internal' protection level

The other four compiled clean. This is one type, not systemic rot.

## Expected behavior

- [ ] `Tests/BoundaryTests/PublicSurfaceTests.swift` imports `import YardGit`
      with **no** `@testable`, and calls all five functions above.
- [ ] `Package.swift` declares the `BoundaryTests` target.
- [ ] `entries` becomes `public let entries: [Entry]`.
- [ ] `swift test` prints a count greater than 272, the count on `main`.

## Mutations — for the REVIEWER

1. Revert `entries` to internal → `BoundaryTests` must **fail to compile**.
2. Add `@testable` to the import → mutation 1 must stop failing.
```

**Outcome:** converged. 17 edits, inside the clock.

Note what the Givens block bought beyond the signatures: the sentence *"there is
no protocol to implement and nothing to inject"*. A model reaching for testability
will invent an injection seam — one round wrote 679 lines against a protocol and a
platform type it made up, and did not open the real collaborator's source until
the last five lines of a 1443-line log.

---

## What changed, line by line

| Version 1 said | Version 2 said | Why it mattered |
|---|---|---|
| "the main public entry points" | five pasted declarations | Removed 26 rewrite cycles of signature archaeology |
| — | the members of each result type | The round has to write call sites, not just calls |
| — | "no protocol, nothing to inject" | Pre-empts the invented-abstraction failure |
| "make `entries` public" | the exact declaration, before and after | No judgement call about where or how |
| "add a test target" | the full file path, and the manifest edit | A path is a claim about the build system |
| "`swift test` passes" | "count greater than 272, the count on `main`" | A count that does not move satisfies "passes" |
| — | two mutations, with the second checking the first | Proves the test can fail — the only real verification |

**Version 2 is longer and took about fifteen minutes to write.** Version 1 cost a
30-minute round and produced a broken tree. That is the trade, and it is not close.

---

## The counter-risk, which has cost rounds

A Givens block converts the author's confidence into the model's **constraint**.
Get it right and it saves a round; one task went from 1289s to 139s on exactly
this mechanism. Get it wrong and it **removes the model's licence to notice**, and
the round spends its whole budget forcing the error to work.

That has happened. A task told the implementer to locate a built binary with a
one-line snippet under a heading reading *"Givens — verified, treat as true"*. The
snippet matches nothing in that context. The round died at the full cap having
written a structurally correct test that could never find the binary.

**What was verified was something adjacent.** The author had confirmed the binary
and the test bundle are siblings on disk — true — then *reasoned* from that to a
snippet and labelled it fact.

> **Nothing goes in a Givens block that has not been executed**, in the context
> the model will run it in. An unverified suggestion goes in Notes, where
> disagreeing is allowed.

---

## Before you write the task: probe

Version 2 was only writable because someone ran a probe first. Three levels,
cheapest first, each one worth minutes against rounds:

**Probe the code**, on the input the task is about. One parser was fed real bytes
containing a rename, a path with a newline, a conflict and an ignored file — seven
records in, six out. Then a record whose path was two non-UTF-8 bytes: **zero**
out, the entire status silently empty. Three defects, none visible from reading.

> **The task that came out of that probe is a repair with five named mutations and
> a measured before-count. The task written from reading the source would have
> been a feature request.** It took four minutes.

**Probe the tool**, not its `--help`. Help text documents the interface; only
execution reveals the output shape, and the output shape is what the integration
depends on. An icon generator's help is accurate and silent about the one fact
that decides the task — it writes to a differently-named directory than the build
setting expects.

**Re-probe before dispatch, even your own earlier probe.** A probe run one day was
accurate about everything it asked; re-run the next day it turned up that the tool
*already reported* the field the task asked someone to compute, and that two
commands write to **stderr**, so a round parsing stdout would report "nothing to
do" for every repository in code that looks entirely correct.

---

## What transfers

Nothing above depends on Swift. The general form:

1. **Paste the API the round must call**, and the shape of what it returns. In any
   language, a name without a signature is an invitation to guess.
2. **Say what does *not* exist.** "No protocol, nothing to inject" is worth more
   than three paragraphs about what does exist, because it closes off the most
   attractive wrong path.
3. **Give the exact path**, and check it against the build system first. A path is
   a claim, and it can be wrong.
4. **State the metric's delta, not its value.** "Passes" and "prints N" are both
   satisfiable by a round that adds nothing.
5. **Write the mutations down**, and make one of them check another. A mutation
   that dies for the wrong reason is worse than none.
6. **Run something first.** The difference between a feature request and a repair
   is four minutes of probing, and repairs converge while greenfield rounds
   time out.
