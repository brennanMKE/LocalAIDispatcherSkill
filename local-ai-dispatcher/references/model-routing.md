# Model routing — what goes local, what stays hosted

## The measured baseline

One day, one local model, **fifty dispatched rounds**:

| | |
|---|---|
| Rounds dispatched | **50** |
| Accepted | 24 |
| Rejected | 22 |
| Failed outright — hung, timed out, no code | 3 |
| Guard refusal, no round spent | 1 |
| **Accepted that needed a hand finish** | **16 of 24** |
| **Accepted clean** | **2** |

23 issues resolved. ~$24 in hosted authoring/review tokens, ~131 million local
tokens at $0.00.

So the local model produced complete, acceptable work **twice in fifty rounds**,
and roughly half of all rounds produced nothing usable.

**Read that as a routing problem, not a verdict.** The rounds that failed cluster
hard, and the clusters are the routing rule.

## The five roles

| Role | Model | Scope |
|---|---|---|
| **Planning** | Top hosted model | Authors the issue down to the code: exact paths, pasted signatures, literal lines, measured before-and-after values |
| **Implementation — pure code** | **Local, $0.00** | Ordinary single-file code against a target the issue already measured |
| **Implementation — structural** | Mid-tier hosted, **billed** | Package manifests, IDE project files, build settings, the environment, the harness |
| **Issue review** | Top hosted model | Re-runs verification, runs mutations, reads every new test. Also reviews umbrella issues once their children resolve |
| **Milestone review** | Top hosted model | Runs when a milestone's issues all resolve; checks stated exit criteria only |

## Route local when

- The issue names **one file** and one deliverable.
- The change is a **repair** against code that already exists and already builds.
- Every signature the round must call is **pasted into the issue**.
- The verification command and its expected output line are stated.
- The deliverable is under roughly **200 lines**.

## Route hosted when

- The change touches a **package manifest, an IDE project file, or build settings**.
  This is the sharpest boundary in the data: one issue spent three rounds on a
  single command-wiring change and never wrote a test; another needed hand
  finishing on exactly the structural half while its pure-code half landed first
  try.
- The work is about **the environment or the harness itself**.
- The deliverable is a **large new file** and cannot be split further. Every
  timeout was a round creating one.
- Getting it wrong is not a bug — licensing boundaries, signing assets,
  architecture spikes that sequence the rest of the project.

## Never delegate

- **Marking work done.** A delegated run reports what it did; verification is
  confirmed independently before status moves.
- **Clean-room / licensing judgment.** The output looks like ordinary code, so a
  code review will not reliably catch it.
- **Anything touching certificates, keychains, or archives.**

## What the failures correlate with

Sorted by strength:

1. **How the issue was written.** Issues carrying *measured* code converged in one
   round — a one-line parser fix with the raw bytes pasted in; a count with both
   candidate commands measured against a real repository; a coverage gap with the
   trap stated up front. Issues describing the work in prose did not.
2. **Greenfield versus repair.** Every timeout was a round creating a large new
   file. Every round scoped as a repair converged, and quickly — 504s, 246s, 132s
   against 1800s caps.
3. **Structural versus pure code.** Manifests and project files fail; single-file
   repairs land.

Difficulty barely appears in that list. The repairs that converged were fiddly and
the greenfield files were ordinary.

## A hand finish is expected, not a failure

Sixteen of twenty-four accepted rounds needed one. Pretending otherwise costs a
full round of latency on most issues.

**Review, finish the last small thing by hand, and re-dispatch only when the
*shape* is wrong** rather than the details. A round can be simultaneously a
success and a process violation — grade the two separately rather than letting
either verdict swallow the other.

## The outcome that matters more than any of the above

After 23 resolved issues and 311 tests, the project's own CLI still answered
`Unknown subcommand`. **The engine was excellent and the product was zero.**

Per-issue review is structurally blind to the gaps *between* issues: forty-two
issues passed review individually while the milestone's actual criterion — working
commands — went unmet, and no single issue's review could have seen it.

That is what milestone review is for, and it needs two bounds or it becomes an
open-ended quality pass:

- It may file issues **only** against a stated exit criterion. Not general
  quality, not style. If a criterion is not written down, it is a proposal, and it
  goes to the human.
- **Two consecutive reviews with no findings closes the milestone.** Without a
  termination rule the loop cycles forever.

Distinguish it from an **umbrella issue**, which breaks *one feature* into small
implementation tasks — that is how work is sized for a small model, and ordinary
issue review covers the parent once its children resolve. A milestone criterion is
a property of the whole milestone, often spanning features, and frequently
satisfied by no single issue.
