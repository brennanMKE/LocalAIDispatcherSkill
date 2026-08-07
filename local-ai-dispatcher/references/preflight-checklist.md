# Preflight — run before every dispatch, including re-dispatches

`[MECHANICAL]` checks are implemented in `scripts/preflight-issue.sh`, which
`dispatch-issue.sh` runs and refuses to dispatch on failure. `[JUDGMENT]` checks
require reading the issue.

**If an issue fails any check, do a planning update first.** Rewrite it, commit it
as its own change with a message naming the failure class it hardens against, and
only then dispatch. **Never dispatch an issue you already know is defective** in
the hope the model works around it — that is how a round gets spent proving
something already known.

Checks read the **spec only**: everything above the first `## Review`,
`## Work log`, or `## Sequencing` heading. Those sections discuss past defects on
purpose, and an earlier version of the script rejected an issue for documenting
its own post-mortem.

## Mechanical — the script decides

| # | Check | Hard? |
|---|---|---|
| 1 | Is the `Module` field filled in? An empty one classifies the issue as non-code and **skips the verification check**. Seven issues sat that way, each reading as clean. | hard |
| 2 | Is the issue claimed (`in-progress`)? An actively running dispatch must say so. | hard |
| 3 | Does it direct work to `/tmp`, `/var/tmp`, or `$TMPDIR`? The sandbox auto-rejects those, terminally. | hard |
| 4 | Does it name at least one concrete source file? | hard for code |
| 5 | Does it name a path that cannot hold a tested unit? A path is a claim about the build system and it can be wrong. | hard |
| 6 | Does it name a verification command whose output can be pasted as proof? | hard for code |
| 7 | Does the stated baseline match the recorded one? A stale baseline hides a small increase. | warn |
| 8 | Does it depend on a branch that is not an ancestor of `HEAD`? | hard |
| 9 | Does it ask the implementer to *discover* a fact rather than applying one? | warn |
| 10 | Does the spec contain a code block at all? | warn |
| 11 | Are the local server's dispatch slots already full? An extra queues silently. | warn |
| 12 | Round > 1 with the issue unchanged since the last round, or with no `## Review` section. | hard (in `dispatch-issue.sh`) |

**Check 4 is the strongest signal in the whole failure log**: every code round that
failed named zero source paths; every round that converged first try named exactly
one.

## Judgment — read the issue and answer honestly

Grouped, because the list is long and the groups are how you remember it.

### Is it one thing?

1. **Exactly one deliverable?** Not one theme — one file, one behaviour, one thing
   that is either done or not. If Expected behavior names more than one new
   production file, it is more than one issue.
2. **Will the deliverable exceed ~200 lines?** Split it before dispatch. Every
   timeout was a large new file.
3. **Is it framed as a repair?** Repairs converge; greenfield writes time out.

### Has every asserted fact been executed?

4. **Has every code snippet in a Givens block been run, in the context the model
   will run it in?** Not reasoned from something adjacent that was run. A "Givens —
   verified" heading tells the model not to question the contents.
5. **Was every fact verified by you, in *this* tree?** Not recalled, not inferred
   from a man page, and not true only on some other branch.
6. **Did you measure the part, then assert the composite?** One issue verified that
   a helper throws on bad input — true — then wrote a criterion about what the
   *caller* returns when given one, without running that. The caller rethrows
   before it reaches the code the criterion was about, so the criterion was
   unsatisfiable by any input. **Run the composite.**
7. **If the task integrates a tool's output, have you run the tool and written down
   what it actually produced?**
8. **Has the code the issue is about actually been run, on the input the issue is
   about?** A throwaway probe costs four minutes and turns a feature request into a
   repair with a measured before-count.

### Can the criteria be satisfied vacuously?

9. **Does a metric criterion state what the number must *change to*?**
10. **Can the criterion be satisfied by DELETING the thing it constrains?**
11. **Does a grep-based criterion fire against known-bad input?** Run it first.
12. **Does the criterion assert the content, or only that something was produced?**
13. **Is any criterion satisfiable by an in-process approximation of an
    out-of-process contract?**
14. **Do the criteria's two dimensions get crossed, or only covered separately?**
    Ask of any criterion containing "or" and "with": is that three cases or
    two-by-two?
15. **Does the assertion distinguish the right state from a *neighbouring wrong
    one*?** Not just "can it fail" — what *else* makes it pass. A marker-file check
    was true for both the state the issue wanted and an accidental one; the fix was
    to name a second observable that differs between them.

### Does the round have everything it needs?

16. **Can the named path hold a unit test?** Check it against the build manifest.
17. **If the round must CALL an API, is the declaration pasted**, along with the
    members of its result type?
18. **Are collaborators named, not just the output file?** And is it stated when
    there is **no** abstraction to implement? A model reaching for testability will
    invent one.
19. **Is the affordance named, not just the constraint?** Grep for whether the
    helper already exists before writing "you will need X".
20. **Is the fixture's *mechanism* given, not just its shape?**
21. **Is "write tests" a checkbox in Expected behavior, naming the file?**
22. **If the issue says a behaviour is "the default", does it name the function
    that has a default?** A default needs a parameter; a parameter needs a
    signature.
23. **Is there anything left for the model to go and find?** If the issue names
    every type, signature and path inline, there is nothing to explore and nothing
    to hang on — subagent handoffs are implicated in four of the last five failed
    rounds.
24. **Has the round been told not to re-measure what the issue already measured**,
    and not to run the suite before writing anything?

### Is the review still true?

25. **If the branch changed since the `## Review` was written, does the review
    still describe the tree the model will see?** A review is written against the
    state at the end of a failing round. Any merge or correction after that can
    silently invalidate it, **and it will still read as current instruction,
    because prose carries no timestamp.** This cost a round: a merge reverted the
    previous round's documentation work; the review did not mention documentation
    because it had been done; the model correctly treated the review as the task
    and undid it again. **Re-read the review against the actual tree immediately
    before dispatching**, not when writing it.
26. **When the review names a defect, does it name the CLASS or one instance?** A
    review saying "fix X in test Y" reliably gets X fixed in Y and **nowhere
    else** — one round added a required guard to the single test named by title and
    left the identical unguarded pattern at seven other sites. If the defect is a
    pattern, say so, and give the command that finds every occurrence.
27. **Does the feedback ask the implementer to verify something?** Verification is
    the reviewer's job. Review feedback once told a round to verify a fact that
    needs a scratch directory the sandbox denies — **the feedback itself made the
    round unrunnable.** State verified facts as givens; the implementer applies the
    conclusion.
28. **If the previous round produced no diff, has the `## Review` section been
    written anyway?** "Nothing to review" is itself the review. This has blocked
    two re-dispatches: a round killed at the timeout has nothing to review, so the
    heading gets skipped, and the next dispatch bounces two seconds in. Write it in
    the same turn as the failure, and say what has changed since.

### Housekeeping

29. **Before creating `NNNN.md`, is NNNN actually free?** Pick the number over
    **every** file on disk, not over the open ones — a resolved issue still owns
    its number. Create it with a tool that fails on an existing path, never a `>`
    redirect. A resolved issue was clobbered exactly this way and noticed only by
    coincidence.

## Adding a new check

Two rules, both from guards that were nearly shipped broken.

**Test it on input that should PASS, not only on input that should fail.** A guard
is a filter, and a filter that rejects everything looks identical to one that works
until someone tries to get through it. One guard would have blocked **every**
dispatch — silently, with a bare exit 1 — because its grep pipeline exits non-zero
on the *common* path under `ERR_EXIT`. Its positive test passed beautifully and
proved nothing about the normal case.

**Prefer a warning to a block for anything heuristic over prose.** A guard that
blocks good issues is worse than the bug it prevents.

Keep the test cases in the commit — the legitimate case, the case where the pattern
is simply absent, and the actual defect.
