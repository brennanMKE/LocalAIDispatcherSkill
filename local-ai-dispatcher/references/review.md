# Reviewing a delegated round

**Every rejected round in the reference project had a green suite.** That sentence
is the whole reason this file is long.

## Order of operations

1. **Read the harness's own verification output**, not the model's summary of it.
2. **Re-run the verification yourself.**
3. **Run the mutations.** Break the thing each new assertion guards; confirm it
   fails, and record *which test* failed.
4. **Read the body of every new test.** Ask what production change would make it
   fail.
5. **Check the diff for scope** — files outside the issue's scope, a branch switch
   mid-round, a criterion satisfied by deletion.
6. **Capture every stream**, including the ones the issue never mentions.

## 1–2. Re-run it; do not read it

A round was marked resolved on a read of a fluent 110-line document. A dispatcher
re-ran the checks and found **three factual errors** about the tool it described.
The model *had* run real commands and pasted real output — it was wrong about what
the output meant.

**Fluency reads as correctness.** A well-written document is the easiest kind to
under-review. Prefer an adversarial pass: instruct the reviewer to *disprove* the
claims.

**Exit 0 is not evidence.** A round reported success with no result line in its log
at all — the command had been rejected by the sandbox and the run continued anyway.
Only the artifacts and a re-run are evidence.

**A green count is not evidence unless it moved.** One round pasted a passing count
and claimed "8 new + 46 existing". The reviewer deleted both new files, re-ran, and
got the **identical** number: the new tests were written in a framework the summary
line does not count. Nobody lied; the metric simply did not measure the work.

**And a count can be identical because the tests were never compiled.** A test file
one character off a declared target path — `Tests/Foo/` instead of `Tests/FooTests/`
— is silently ignored. No error, no warning, the suite stays green, the number does
not move. Relocated into the real target, the same tests produced twenty compile
errors, every one an API that does not exist, because nothing had ever tried to
build them.

## 3. Mutation is the only reliable verification

Six distinct costumes of *"a check that cannot fail"* appeared in a single day.
Each was caught, logged, and given a detector. **Each next one wore a shape the
previous detector could not see.**

| Costume | Why the previous detector missed it |
|---|---|
| A test whose name promises a behaviour it never calls | The name reads as coverage |
| `for x in allCases { guard case .ok = x else { continue }; … }` | Ten cases, one tested, under a name promising all of them |
| An extractor that returns `[]`, so the assertion is `[] == []` | There *is* an `#expect` |
| A test count identical with the new files deleted | The number is real |
| A stale guard still forbidding the **old** path | The literal is plausible |
| A grep criterion too narrow to match the defect | The check ran and passed |
| A predicate that is **structurally unsatisfiable** over real data | Real data, real comparison, and it can never fire |

The last one is worth spelling out because it is the hardest. A layering test
contained a helper stripping `@testable `, `internal ` and `public ` — and **never
stripping `import `**. The caller then asked `marker.hasPrefix("YardKit")` of a
string that always begins `import `. False for every real import line, forever. In
the same file, `skipDescendants()` was called on every directory, so the
"recursive" walk never descended and the `recursive:` parameter was inert.

Every artefact-level check agreed it complied. The words from the criteria were all
present in the source. **None of them functioned.**

> **So the only reliable verification is mutation.** Break the thing the assertion
> guards; confirm it fails. That is not a nice-to-have on top of the other checks,
> it is the only one that can distinguish a working guard from a decorative one.
> Lead every review with the mutation table rather than ending with it.

### Which test killed it matters

A mutation appeared to die correctly — and died *by accident*, through an unrelated
rendering test that greps output text. The **same mutation on a second input passed
silently**, because that input is never rendered. **Record which test failed, not
just that one did**; a mutation killed by an unrelated test is evidence of coverage
you do not have.

### Mutate against a clean build

One dependency-direction mutation **succeeded** incrementally, because the build
system resolved it against a stale module left in the build directory. Wipe the
build directory first, or the assertion that the arrow points one way is worthless.

### A mutation that cannot run is not a passing mutation

Several rounds shipped tests that trap or fail to compile *before* reaching the
function under test — a force-unwrap of a value the fixture never sets, a local
declared in one test and used in another. Every required mutation was then
unrunnable, and the round scored as if it had refused the work.

## 4. Read the body, not the name

Ask of each new test: **what production change would make this fail?** If the
honest answer is "none", the criterion is unmet however green the run was.

Shapes to grep for, whatever the language:

- **No assertion at all** in the test body.
- **A bare `return`** — a quiet skip that reports success.
- **An assertion over literals** — `expect(true)`, `.count >= 0`, `x != nil || x == nil`,
  `… || true`.
- **`if let x = … { assert }`** with no else. When the lookup fails the block does
  not run, the test asserts nothing, and it **passes** — which is exactly the
  failure it was written to catch, reported as success. Use the framework's
  *stopping* unwrap instead. One round shipped five of these in one file.
- **`expect(a || b)`** — passes when either half holds, so neither is tested.
- **`_ = result.something`** — asserts nothing. If it is worth reading it is worth
  asserting on.
- **A hand-written list of cases** instead of the language's exhaustive enumeration.
  The next case someone adds is silently untested.
- **Extract-then-assert with no non-empty check.** Whenever a test parses, scans or
  filters, look for an `isEmpty` assertion before the real one.

Two language-specific hazards worth knowing because they destroy the *whole run*,
not one test:

- **A non-stopping assertion followed by a force unwrap.** The assertion records an
  issue and continues; the unwrap traps and kills the test **process**, so the
  summary line never prints and every other test's result is lost with it.
- **Capturing the process's own stdout in a test.** The write end stays open so EOF
  never arrives, *and* the test runner's own output goes into the void. One suite
  ran 10m50s against a 12s baseline and emitted nothing. Test the value, not the
  writing: make the helper that produces the string internal and call it directly.

`scripts/` in the reference project carried a detector for these
(`check-tests-assert.sh`). It is **necessary and not sufficient** — it looks for
missing assertion macros and skip-shaped returns, not predicates that are
structurally unsatisfiable.

## 5. Scope

- `git diff --stat` for files outside the issue's scope. One round added workflow
  doctrine to **its own governing config file**.
- **Verify the branch at the END of a round, not just the start.** The dispatch
  script checks `HEAD` before dispatching and cannot see a mid-round switch. One
  round came back on a branch it created itself.
- **Can the criterion have been satisfied by deletion?** A "no snake_case keys"
  grep passed because the round removed the whole key-mapping enum and fell back to
  synthesis.

## 6. Capture every stream

Two correct issues, each doing exactly what it specified, together silently dropped
a stderr line: the command wrote **zero bytes** to stderr afterwards. No criterion
in either issue could have caught it, because each issue's criteria are about its
own delta.

It was found only because a review captured stdout and stderr **separately** and
noticed one was empty. **An empty stream is information.**

The general rule for a chain of issues touching one behaviour: the last one needs a
criterion asserting the **end-to-end** behaviour still holds, not just its own
change.

## Traps that live in the reviewer, not the round

### Your probe can change what it measures

A reviewer's probe did two things in one function: resolve a value one way, then
assert that a second lookup finds nothing. The second assertion failed — reading as
the previous reviewer being wrong.

It was not. The first call **registers** the thing the second call looks for. The
measurement had been contaminated by its own setup. Probed alone, each form gave
the opposite result, and the real finding was sharper than either first statement:
the second form is **order-dependent**, which is a flake waiting to happen rather
than an honest failure.

**When a probe contradicts a careful reviewer, suspect the probe.** Isolate each
claim in its own run.

### A verdict formed on partial coverage is provisional

One round covered two of three invocation positions, did not say so, and the review
accepted "the implementation is correct" on that basis. The next round added the
third and it failed immediately — the tool emits a **different message** in that
case, which the hardcoded prefix dropped. **An uncovered case is not a passing
case**, and covering the third one is what found a real production defect.

### Compiling is not launching

A change was accepted as verified on a compile-and-link probe with a negative
control. **The app did not launch** — it died in the dynamic loader on a dependency
whose signature could not be mapped into the process. Linking, embedding,
entitlements, plist keys and dylib loading all fail at **load** time.

And the corrected criterion still was not sufficient: an *unsigned* build is
ad-hoc signed, and an ad-hoc process can map an ad-hoc dependency, so the broken
tree launches too. For that class of failure the evidence is the **absent load
command**, not the launch.

### A test harness with extra privileges cannot verify a boundary defined by privilege

A public function returned a public type whose members were **internal**. An
out-of-module caller could obtain the value and do nothing with it. **No test in
the suite could catch it**, because the tests use a privileged import that grants
internal access — the tests and the caller were compiling against different
modules. Every test passed against an API nobody could use.

This generalizes past any one language: anywhere the tests get a capability the
caller does not — a friend class, a test-only export, a mock that bypasses an
interface — the boundary needs its own check compiled at the caller's level.

### Prose is the one deliverable that cannot be run

No mechanical check reads English against code. A round asked to correct three doc
comments passed **every** guard — exact test count, comments-only proven by a diff
filter, no scope violation — and left the file *less accurate than it found it*.
Each correct fix was padded with invented detail: a pipeline that does not exist,
an assurance that two counts "should match in practice" when they routinely differ,
advice about a length check no code performs.

Read the prose against the implementation line by line. Same discipline as re-running
a test rather than reading its name, applied to the artifact that cannot be run.

## When a review fails, the fix goes upstream

A failed round triggers this sequence **before anything else is dispatched**:

1. **Spawn a learning subagent** on the failure — the round log, the issue text,
   the existing failure log. It returns the root cause, the failure class, and the
   preflight check that would have caught it. Analyze only, no edits. In a
   subagent, for the same reason dispatch happens in one.
2. **Record the row in the failure log in the turn the finding arrives.**
3. **Push the fix to where it will be read.** Model behaviour or environment →
   `AGENTS.md`. How issues are written → the preflight checklist. Anything a script
   can enforce → the script.
4. **Then** do the planning update and re-dispatch.

> **A finding recorded only in a retrospective has not been fixed. It has been
> filed.** A retrospective is read when something goes wrong; an issue is authored
> when things are going fine. The two never meet.

**Assume a failed round is an authoring defect until the evidence says otherwise.**
Most are. The model has generally done what it was told; the losses came from
telling it something wrong, something impossible in its sandbox, or too many things
at once.

## Did the failure log help? Measured, not felt

Before it existed: 8 rounds across 5 issues, two of which went to three rounds or
were abandoned. After: 10 rounds across 6 issues, **nothing needing a third round**,
first-round acceptance up from 1-in-5 to 2-in-6, and several defective issues
refused before a round was spent — rounds that appear in no timing comparison
because they never happened.

**The honest claim is not "fewer failures".** It is: *no failure class has recurred
once logged, and novel ones keep arriving at a steady rate.* The mechanism converts
"the same mistake repeatedly" into "each mistake once", which is worth a great deal
and is not the same as improvement in the raw failure rate.
