# NNNN — {A single declarative sentence naming the ONE deliverable}

| | |
|---|---|
| **Status** | open |
| **Module** | {must not be empty — an empty Module skips the verification check} |
| **First seen** | YYYY-MM-DD |

<!--
  This template is shaped by what makes a round converge, measured over 50
  dispatches. Delete the guidance comments before dispatching; keep the headings.

  The one-line test: could one person finish this in a single sitting WITHOUT
  DECIDING WHERE ANYTHING GOES? If not, split it.
-->

## Description

{What to build and why it matters. Lead with the punchline.}

{If this is a repair, say what is broken and give the measured symptom. Rounds
scoped as repairs converge; rounds creating a large new file time out.}

## Givens — measured on `{branch}` on {date}, treat as true

<!--
  NOTHING GOES IN THIS BLOCK THAT HAS NOT BEEN EXECUTED.

  Not reasoned from something adjacent that was executed — executed, in the same
  context the model will run it in. This heading tells the model not to question
  the contents, so a wrong line here removes its licence to notice and it will
  spend the whole round forcing the error to work. One issue lost a full 1800s
  cap to a single reasoned-not-run line.

  If you want to suggest an unverified approach, put it under ## Notes as a
  suggestion, where disagreeing is allowed.
-->

**The file to change** — `path/to/File.ext`, line 88:

```
{paste the literal current line or expression}
```

**Every signature this round must CALL**, pasted from source:

```
{paste the declarations, and the public members of each result type}
```

**There is no abstraction to implement here.** `{Collaborator}` is a concrete
`{kind}` constructed as `{Collaborator}()`; the tests run against real fixtures
from `{Helper}`, so there is nothing to inject.

<!--
  That last sentence matters more than it looks. A model with no stated API will
  infer one, reaching reasonably for something injectable — one round wrote 679
  lines against a protocol it invented and never opened the real collaborator's
  source until the last five lines of a 1443-line log.
-->

**The affordance that already exists**: `{Helper}.{method}()` already builds
{exactly the state this issue needs}. Use it; do not reconstruct it.

**Measured before and after**:

| | |
|---|---|
| Input | {real bytes / real command output, pasted} |
| Current output | {what it actually produces today — measured, not assumed} |
| Required output | {what it must produce} |

**Do not re-measure any of the above.** It is stated here so the round does not
have to spend context discovering it.

## Expected behavior

<!--
  One deliverable. If this list has two verbs in it, it is two issues.
  "Write tests" must be a CHECKBOX HERE naming the file — a separate "tests must
  be able to fail" section reads as advice on how to test, not as a deliverable,
  and a round once changed only the source and reported success.
-->

- [ ] `path/to/File.ext` {states the literal change}.
- [ ] `path/to/FileTests.ext` gains {N} tests covering {the cross product, listed
      explicitly if the criterion has two independent dimensions}.
- [ ] `git diff --name-only` lists **two** files.
- [ ] `{verification command}` prints a line matching `{the exact expected line}`,
      with **N greater than {baseline}**, the count reported on `{branch}` before
      this change.

<!--
  Criteria traps, each a rejected round:
    - a metric with no baseline is satisfiable by a round that adds nothing
    - a criterion phrased as an ABSENCE can be met by DELETING the thing it
      constrains — phrase it as a presence
    - "prints the envelope" is satisfied by an envelope with the wrong content
    - a grep criterion must be run against known-bad input first, or it returns
      clean and proves nothing
    - if the criterion is about what a CALLER observes (stdout bytes, exit status,
      a hook firing), say that an in-process test cannot satisfy it
    - if a behaviour is "the default", name the FUNCTION SIGNATURE that has one
-->

## Mutations — for the REVIEWER, after the round

<!--
  These are things the reviewer does to the production source to check the round's
  tests are load-bearing. They are NOT a request for tests that reproduce the
  mutated behaviour — a round once read them that way and shipped tests that were
  flaky and inert at once.

  Mutation is the ONLY reliable verification. Every rejected round had a green
  suite, and six distinct costumes of "a check that cannot fail" appeared in a
  single day, each invisible to the detector written for the last one.

  Record WHICH test kills each mutation. A mutation killed by an unrelated test is
  evidence of coverage you do not have.
-->

1. **{Revert the literal change}** → `{TestName}` must fail.
2. **{Break the second dimension}** → `{OtherTestName}` must fail.
3. **{Delete the new file entirely}** → the count must drop below {baseline}.

## Notes

{Dependencies: `Blocked by #NNNN`.}

{Unverified suggestions go HERE, not in Givens.}

---

<!-- Everything below this line is added as the work happens. Preflight stops
     reading at the first `## Review` heading, so these sections may discuss bad
     paths and past defects freely. -->

## Review

<!--
  Written by the reviewer between rounds. Three rules:

  1. Name the CLASS, not one instance. "Fix X in test Y" reliably gets X fixed in
     Y and nowhere else. Give the command that finds every occurrence.
  2. State verified facts as GIVENS. Verification is the reviewer's job; telling
     the round to go verify something can make it unrunnable in the sandbox.
  3. RE-READ THIS AGAINST THE ACTUAL TREE IMMEDIATELY BEFORE DISPATCHING. A review
     is written against the state at the end of a failing round, and any merge
     since can silently invalidate it — it will still read as current instruction,
     because prose carries no timestamp.

  If the previous round produced NOTHING — a timeout, an empty tree — say exactly
  that here, plus what has changed since. "Nothing to review" is itself the review,
  and the dispatch guard requires this heading.
-->

## Work log

| Phase | Who | Cost |
|---|---|---|
| **Authoring** | {model} | hosted — not separately metered |
| **Implementation** | OpenCode / {local model} (local) | $0.00 |
| **Review** | {model} | hosted — not separately metered |

| | |
|---|---|
| **Rounds** | {n} |
| **Wall time** | {m} |

<!--
  Implementation is $0.00 ONLY when it actually ran locally. A round taken over by
  hand says so. Misattributing one destroys the only thing this table is for.
-->
