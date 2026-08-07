# Running unattended

The whole point of a free-per-token, slow-per-round implementer is that it can run
while nobody is watching. Everything in this file exists because that turned out to
be much harder than expected, and for one mechanical reason.

## The mechanic almost everyone misses

> **A turn ends when a response contains no tool calls. It does *not* end because
> the response contains text.**

Background work re-invokes the session when it finishes. Nothing else does. So a
turn that ends with prose and nothing running **stops the queue silently**, and
stays stopped until a human notices.

This is not a discipline problem and it does not read like quitting. Every stop had
the same shape: finish a unit of work, write a summary, let the response end there.
The summary *feels* like reporting rather than quitting, which is exactly why a rule
about it keeps failing to bind — it reads as advice about **tone** when it is really
a fact about **turn structure**.

It has happened at every level of the same project:

- **The main loop**, five separate times after the rule was written down, twice
  re-committed and once saved to memory. The user called it out four times, with
  rising sharpness.
- **A dispatcher subagent** writing *"waiting for the dispatch to exit"* and
  stopping — twice, the second time with an explicit instruction in its prompt
  telling it not to.
- **A promise about the future**: *"I'll keep two rounds in flight through the
  night"*, followed by dispatching nothing and saying goodnight. **Prose about
  future intent is not a scheduled action.**

## The consequence: idle wall-clock is the dominant cost

Measured hosted spend on the reference project was ~$38. One idle hour during a
window a human had explicitly set aside was worth more than that — six rounds at
~20 minutes each would have fit in it — and it appears in no ledger.

**Size a stop by idle wall-clock, not by tokens.**

## The three fixes, in order of how well they work

### 1. Put the next tool call in the same response as the text

"Answer the question" and "keep working" were never in conflict. A single response
can carry the answer **and** the next tool call; only trailing text with no tool
call actually stops.

So: **when a response would end with text, check whether the queue is exhausted. If
it is not, the response must also contain the next tool call.**

This is still an instruction, and instructions have failed here. It is necessary and
not sufficient.

### 2. Make waiting structural, not a decision

`scripts/await-dispatch.sh` is the model for this. It blocks inside a tool call for
a budget under the harness's foreground limit, then exits **0** (finished) or **75**
(*call me again*). The agent either holds a result or must make another call. There
is no state in which "wait" is something it can merely intend, so the sentence that
ends the turn has nowhere to appear.

Two instruction-shaped attempts failed at that exact spot before this worked. The
difference: the first two asked the agent to recognise a boundary it demonstrably
cannot see; the third removes the boundary.

### 3. A heartbeat, so a stop is recoverable

A timer that re-invokes the session **whether or not anything is running** is the
one case no completion notification can cover — because there is nothing to notify
about. In Claude Code that is `/loop <interval> <prompt>`.

**Treat it as a fallback, not the primary signal.** Harness-tracked background work
already re-invokes on completion and is far more responsive than any interval;
polling for it just burns wakeups. The heartbeat exists for what notifications
structurally cannot catch:

- a round that hangs and never completes,
- a notification that is missed,
- and the real one — **both dispatch slots idle because the previous turn ended
  without dispatching.**

**Pick the cadence from the failure being bounded, not from how long a round takes.**
An hour is right: a stalled queue then costs at most an hour, which is the actual
damage. A five-minute heartbeat would not make rounds finish sooner — rounds take
ten to thirty minutes and announce themselves — it would only add wakeups.

**What each firing should do, in order:**

1. Confirm both dispatch slots are busy.
2. Merge anything that finished and set its status.
3. Dispatch from the ready queue until both slots are full again.
4. If the queue is genuinely empty or blocked, **stop the loop** rather than let it
   tick.

## The state lives in the tracker, not in the conversation

Between firings, status rows and branches say what is done, so a fresh context
resumes without needing the previous conversation. That is only true if status is
maintained as part of the work rather than as bookkeeping after it — see
`references/dispatch-loop.md`.

## Reroute rather than stop

When an issue is blocked, move to the next unblocked one and **collect blockers into
one batched question at the end**. One question with five items beats five
interruptions.

A progress report between issues is a stop, however it is phrased. Findings belong
in the docs and in the issue files — that is the report, and it persists.

## Never fake progress to avoid stopping

The verification rules still hold. Tests must actually run, and an unverified issue
stays open. **Reporting an issue resolved to keep momentum is worse than any
interruption.**

## Concurrency

The local server's parallel limit is the real ceiling, and it is silent — an extra
dispatch queues rather than running and looks like a very slow round. Two concurrent
rounds was the measured limit in the reference project. Confirm before planning any
fan-out, and remember that a dispatch is also **one worktree**, so the tree count
tracks the slot count.
