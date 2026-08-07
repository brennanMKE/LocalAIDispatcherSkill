# Cost accounting

> **Decide how cost will be measured before the first delegated round.**
> Retrofitting it onto completed work recovers only what the harness happened to
> report along the way.

## Cost is per phase, and only one phase is ever free

```markdown
## Work log

| Phase | Who | Cost |
|---|---|---|
| **Authoring** | Opus 5 | hosted — not separately metered |
| **Implementation** | OpenCode / <local-model> (local) | $0.00 |
| **Review** | Opus 5 | hosted — not separately metered |

| | |
|---|---|
| **Rounds** | 2 |
| **Wall time** | 14m |
```

One combined `Token cost` row makes a hosted-implemented issue and a
locally-implemented one look identical, which destroys the only signal the table
carries. Split it.

**Authoring and review always cost.** Writing an issue detailed enough that
implementation needs no further judgment is real work, and so is reading a diff and
its verification output against the done-criteria. Recording those as free makes
delegation look cheaper than it is and hides where the remaining spend goes.

**Implementation is `$0.00` only when it actually ran locally.** When a round is
taken over by hand — or by a hosted model for any reason — that row says so. The
table exists so a reader can tell at a glance which issues were genuinely free to
implement, so misattributing one destroys the only thing it is for.

## `hosted` is a placeholder, not a cost

Filling authoring and review rows with the bare word `hosted` names a billing
category and stops. An issue that cost pennies and one that cost dollars then look
identical.

**The underlying gap is real**: an agent harness typically exposes no per-turn token
usage for the main loop, and without an API key there is no `count_tokens` call
available either. So write **`hosted — not separately metered`**, and file the gap
as an issue rather than papering over it.

**Never invent a number.** An estimate is acceptable only with its method and inputs
stated beside it; a figure with no derivation is indistinguishable from an invented
one.

## What *is* measurable

### 1. Dispatcher subagent tokens — measured once, then gone forever

A subagent reports its token total on completion, in a notification that exists
**nowhere else** — not in git, not in a log, not in any API. When the session ends
it is gone.

> **Write it into the cost ledger and the issue's work log in the turn it is
> reported.** Do not hold it in conversation context intending to write it up later.
> The same applies to wall times, round counts, and any number the harness surfaces
> once.

That figure is usually **combined**, with no input/output split. Agentic subagent
work is heavily input-weighted (large tool results and re-read context dominate), so
price it at a stated assumption and **write the assumption inline at every use**:

```
0.85 × $5.00 + 0.15 × $25.00 = $8.00 per MTok combined
```

Write `≈$0.40 (50k tokens @ $8/MTok, 85/15 split assumed)`, never a bare `$0.40`.

### 2. Local token volume — durable, and only in one place

`scripts/tally-local-tokens.sh` reads OpenCode's SQLite database at
`~/.local/share/opencode/opencode.db`, which records `tokens_input` /
`tokens_output` per session.

**Nothing else records it.** The dispatch logs carry no token counts, LM Studio
exposes no historical usage endpoint, and the subagent figure above dies with the
session. The database **survives**, which is why the tally is regenerable rather
than a snapshot someone has to remember to update.

Attribution is by working directory — a dispatch runs in `../proj-NNNN`, so the
worktree name is the issue number. That is another reason a dispatch must never run
in the primary checkout: it would land in `(main)` with no issue attached.

## What the numbers actually say

From ~131 million local tokens across 98 sessions:

**Input outweighs output by roughly 100 to 1.** That is the shape of an agentic loop
rather than anything about the model: every turn resends the accumulated context, so
a long round re-reads its own transcript hundreds of times. **It is the strongest
argument for running the implementer locally** — on a hosted model that ratio *is*
the bill. Priced at mid-tier hosted rates, that traffic would have been ~$428.

## If you are on a subscription rather than an API key

The dollar figure is then the wrong frame, and the right one is **usage headroom**.

A subscription meters against a rolling window. The 100:1 input ratio above means
implementation rounds consume that window faster than anything else you do — a
30-minute round re-sends its whole context on every turn, and in the reference
project one round burned 438,301 input tokens for a context that never exceeded
49k, because nothing was being cached.

Three consequences worth stating to anyone weighing this up:

- **Implementation is the worst possible use of a metered window.** It is the
  highest-volume phase and the one with the least judgment in it, *once the task
  has already been authored properly*. Authoring and review are low-volume and
  high-judgment — exactly what a frontier model should be spending its quota on.
- **Moving implementation local converts a hard limit into a soft one.** Local
  inference is bounded by wall clock, not by quota. You trade "throttled by noon"
  for "each round takes 8–30 minutes", and rounds can run while you do something
  else.
- **The rounds that fail cost the same as the rounds that succeed.** Well over
  half the local volume in the reference project went on rejected or abandoned
  rounds. On a subscription that would have been over half your window spent on
  work that was thrown away — which is the strongest argument in this whole skill
  for the preflight refusing a defective task before a round is spent on it.

What still consumes the subscription: authoring, review, and every dispatcher
subagent. That last one is not small — measured at ~40–70k tokens per dispatch —
so a session that dispatches twenty rounds spends real quota on the supervision
layer even though the implementation itself is free. Budget for it.

**The most expensive rounds are the ones that failed.** Well over half the total
volume went on rounds that were rejected or abandoned. That is the cost of authoring
defects, and it is invisible in the dollar column **precisely because it is free**.
Free failure is the kind that stops being noticed — which is why the failure log
exists and why the preflight refuses a defective issue before a round is spent on it.

## The number that is not in any ledger

**For an unattended local-inference workflow, idle wall-clock is the dominant cost.**

The model is free per token and slow per round, so throughput is set almost entirely
by whether rounds are in flight. Measured hosted spend on the reference project was
$38. One hour of both dispatch slots sitting idle — because a turn ended with prose
instead of a tool call, during a window a human had explicitly set aside — was worth
more than that. Six dispatched rounds at ~20 minutes each would have fit in it.

**So a stop during an unattended window is not a small process foul; it is the
single most expensive thing that can happen**, and it appears in no ledger.

Size that failure by idle wall-clock, not by tokens. See
`references/unattended-operation.md`.

## Has the delegation paid for itself?

State it honestly, and keep the `Rounds` column, because that is the number to watch.

Early on, review cost was **higher** than the implementation cost it replaced. That
is expected — the review discipline caught a swapped exit-code contract and three
false claims about a tool that would otherwise have shipped — but it must be
revisited once several issues have gone through cleanly.

The falsifiable hypothesis worth measuring on any project doing this: **issues
authored to code level should raise the first-round accept rate and cut the
hand-finish rate.** The reference baseline is 2 clean accepts and 16 hand finishes
out of 24. If the next batch looks the same, the planning change is not the lever
and the constraint is the implementer.

Secondary numbers worth watching: **rounds lost to environment rather than code**
(in one day: two hung inferences, two mistyped-path sandbox rejections, ~six `/tmp`
rejections, one output-cap truncation), and whether routing structural work to a
hosted model removes the failures the local one could not clear in three attempts.

## Templates

`assets/cost-ledger-template.md`.
