#!/usr/bin/env zsh
#
# dispatch-issue.sh NNNN [--round N] [--model local|hosted] [--timeout S]
#                        [--stall S] [--force]
#
# Runs ONE round of implementation on one issue, through OpenCode, in the current
# worktree. The implementer implements: it does not commit, does not branch, and
# does not set status. Review owns all three.
#
# Guards, in order of how often they matter:
#
#   wall-clock timeout   the model has looped before, and macOS has no `timeout`
#   stall watchdog       a hung inference request produces silence, not an error.
#                        Its first real firing killed a dead round at 720s instead
#                        of 1800s.
#   round cap            a task that is not converging escalates to a human
#                        instead of burning an afternoon
#   clean-tree           so this round's diff is attributable to this round
#   changed-prompt       re-dispatching an unchanged issue re-runs a prompt already
#                        proven not to work
#   no-progress          a run that "succeeds" and changes nothing is a failure
#                        that reports as success — `opencode run` exits 0 anyway
#   sandbox-reject scan  an auto-rejected write is TERMINAL and still exits 0
#   harness verification the suite is run by the harness, not by the model, and
#                        the real count is written into the round's own log
#
# Exit codes
#   0  the round ran and changed something — go review it
#   2  bad arguments
#   3  round cap exceeded
#   4  dirty working tree
#   5  opencode not found
#   6  the local model server is not answering
#   7  NO CHANGES — a failed round; do not re-dispatch unchanged
#   8  wrong branch
#   9  preflight rejected the issue
#  10  round > 1 with an unchanged issue or no `## Review` section

set -u
setopt ERR_EXIT PIPE_FAIL

source "${0:A:h}/_common.sh"
load_conf "$0"

MODEL_CHOICE=local
ROUND=1
FORCE=0
ISSUE=""

while (( $# )); do
  case "$1" in
    --round)   ROUND="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --stall)   STALL="$2"; shift 2 ;;
    --model)   MODEL_CHOICE="$2"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *)         ISSUE="$1"; shift ;;
  esac
done

die() { print -u2 "dispatch: $1"; exit "${2:-1}" }

[[ -n "$ISSUE" ]] || die "usage: dispatch-issue.sh NNNN [--round N] [--model local|hosted]" 2
[[ "$ISSUE" =~ '^[0-9]{4}$' ]] || die "issue must be 4 digits, got '$ISSUE'" 2
SPEC_FILE="$ISSUE_DIR/$ISSUE.md"
[[ -f "$SPEC_FILE" ]] || die "$SPEC_FILE does not exist" 2

# Every mechanical check derived from a past failed round lives in
# preflight-issue.sh, and each one is there because a round was already lost to
# the thing it looks for. Refusing a known-defective issue is the cheapest guard
# in the harness: it costs a second, the alternative costs a full round plus a
# review.
if [[ -x "$REPO_ROOT/scripts/preflight-issue.sh" ]]; then
  "$REPO_ROOT/scripts/preflight-issue.sh" "$ISSUE" || die \
"preflight rejected $SPEC_FILE (above). Fix the issue text, commit the planning
update, then dispatch. Never dispatch an issue already known to be defective in
the hope the model works around it — the round will only rediscover it." 9
fi

# A re-dispatch needs a changed prompt. This is the guard that has fired most
# often for the right reason.
if (( ROUND > 1 && ! FORCE )); then
  PREV_LOG="$RUN_LOG_DIR/$ISSUE-round$((ROUND-1)).log"
  if [[ -f "$PREV_LOG" ]]; then
    [[ "$SPEC_FILE" -nt "$PREV_LOG" ]] || die \
"$SPEC_FILE has not changed since round $((ROUND-1)) ran.
Re-dispatching an unchanged prompt re-runs a prompt already proven not to work.
Write a '## Review' section explaining what to do differently, or split it." 10
    grep -q '^## Review' "$SPEC_FILE" || die \
"round $ROUND, but $SPEC_FILE has no '## Review' section.
The model has no way to know what went wrong last round.

Add one. If the previous round produced NOTHING -- a timeout, an empty tree --
say exactly that under the heading, along with what has changed since so this
round will not repeat it. 'Nothing to review' is itself the review, and the
model needs to read it. Do NOT reach for --force; the heading costs a minute
and the round costs twenty." 10
  fi
fi

if (( ROUND > MAX_ROUNDS && ! FORCE )); then
  die "round $ROUND exceeds the cap of $MAX_ROUNDS. The task is not converging.
Rewrite the issue with more specific guidance, split it, or take it back.
Three failed rounds is information about the ISSUE, not about the model.
Override with --force only if you know why the extra round will differ." 3
fi

# Work happens on a per-issue branch, in its own worktree. The default branch is
# never touched directly, and the branch keeps every round's commit as the record
# of how the work went.
BRANCH="issue/$ISSUE"
CURRENT=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT" != "$BRANCH" ]]; then
  die "on branch '$CURRENT', expected '$BRANCH'.
Start the issue in its own worktree:
  git worktree add -b $BRANCH ../$(basename $REPO_ROOT)-$ISSUE <default-branch>
Never dispatch in the primary checkout — it pins the default branch and every
finished issue queues behind this round while the repo reads as idle." 8
fi

if [[ -n "$(git status --porcelain)" ]]; then
  die "working tree is dirty. Commit the previous round to $BRANCH (or discard
it) so this round's diff is attributable." 4
fi

command -v opencode >/dev/null || die "opencode not found on PATH" 5

case "$MODEL_CHOICE" in
  local)
    curl -sf -m 5 "$LOCAL_ENDPOINT/models" >/dev/null \
      || die "the local model server is not answering at $LOCAL_ENDPOINT.
Start it and load the model, or pass --model hosted." 6
    MODEL=$(curl -sf -m 5 "$LOCAL_ENDPOINT/models" \
      | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -1)
    OPENCODE_MODEL_ARG=()
    [[ -n "$MODEL" ]] || die "$LOCAL_ENDPOINT/models returned no model id." 6
    ;;
  hosted)
    MODEL="$HOSTED_MODEL"
    OPENCODE_MODEL_ARG=(--model "$MODEL")
    print "dispatch: NOTE -- this round is BILLED. The local model is \$0.00; this is not."
    ;;
  *)
    die "unknown --model '$MODEL_CHOICE'. Use local (default) or hosted." 2
    ;;
esac

mkdir -p "$RUN_LOG_DIR"
LOG="$RUN_LOG_DIR/$ISSUE-round$ROUND.log"
BASE_SHA=$(git rev-parse HEAD)

read -r -d '' PROMPT <<EOF || true
Work issue $ISSUE. Read $SPEC_FILE, then AGENTS.md.

This is round $ROUND of at most $MAX_ROUNDS. If a previous round left review
feedback in the issue's "## Review" section, that feedback is the task.

Rules for this run, which override anything in the issue that disagrees:
  1. Implement only what issue $ISSUE asks for. Do not start another issue.
  2. Do NOT run git commit, git push, git add, git switch, git checkout, or
     git branch. You are already on the correct branch. Leave changes in the
     working tree for review.
  3. Do NOT change the issue's Status row. Review decides that.
  4. Run the verification command the issue names and paste its real output.
     Never claim a test passed without output showing it ran. A run with no
     result line is a FAILURE, not an ambiguity — an expected line that is
     absent is the finding.
  5. If you are blocked, or find yourself repeating an action that already
     failed, STOP and report what blocked you. A clear stop is a good outcome.
     Repeating a failing command is not.
  6. Your sandbox AUTO-REJECTS writes outside this worktree: /tmp, /var/tmp,
     \$TMPDIR, and anything under ~ that is not here. Put every scratch file,
     probe and throwaway fixture under $SCRATCH_DIR/ in this worktree. That
     rejection is TERMINAL — the run ends where it happens. If one occurs,
     retry inside the worktree; do not narrate a plan and stop.
  7. Every file path you write must be WORKTREE-RELATIVE. Never absolute. Two
     rounds have died on one mistyped character in a long absolute path; the
     sandbox correctly read it as outside the worktree and killed the run
     mid-edit.
  8. If a command is rejected or a tool call fails twice the same way, change
     approach; do not retry it. If the write tool fails twice on one file,
     create it with a shell heredoc instead: cat > path/File <<'EOF' ... EOF.
     A ceiling is not something a retry can clear.
  9. Do NOT spawn a subagent — no Explore, no Task, no delegation of any kind.
     The issue names every file, type and signature you need. Subagent handoffs
     are implicated in four of the last five failed rounds and produced nothing.
 10. Read the files the issue names, then START EDITING. Do not survey the
     repository first, and do not run the test suite before you have written
     anything. One round read twelve files without writing a line, filled its
     context, was compacted, and died — it had treated a fully-specified issue
     as a research task.
 11. Build incrementally. Declare the types, build, then fill the bodies. A
     partial file that compiles can be finished; a large write that never lands
     leaves nothing behind. Every timeout in this harness was a round creating a
     large new file at once.
 12. NEVER end a round with a question. You have no one to ask — whatever you
     ask goes into a log nobody reads until after you have stopped. Do every
     unambiguous part first, take the most literal reading of the criteria, and
     state any assumption in one sentence at the END, after the suite has run.

Finish with a short report: what you changed, what you ran, what it printed,
and anything you could not do.
EOF

print "dispatch: issue $ISSUE, round $ROUND/$MAX_ROUNDS, model ${MODEL:-unknown} (${MODEL_CHOICE}), timeout ${TIMEOUT}s, stall ${STALL}s"
print "dispatch: log -> $LOG"

START=$SECONDS
opencode run "${OPENCODE_MODEL_ARG[@]}" "$PROMPT" >"$LOG" 2>&1 &
RUN_PID=$!

# Two watchdogs. The wall-clock one bounds a round that is working but slow; the
# stall one bounds a round that has stopped producing anything at all.
#
# A hung inference request writes a session row with 0/0 tokens and no finish
# reason, then sits silent. OpenCode's own chunkTimeout did not fire; the log's
# mtime is the cheap, reliable signal, because a live round appends constantly.
( sleep "$TIMEOUT"
  kill -TERM "$RUN_PID" 2>/dev/null
  sleep 10
  kill -KILL "$RUN_PID" 2>/dev/null ) &
WATCHDOG=$!

( while kill -0 "$RUN_PID" 2>/dev/null; do
    sleep 30
    [[ -f "$LOG" ]] || continue
    LAST=$(file_mtime "$LOG")
    NOW=$(now_epoch)
    if (( NOW - LAST >= STALL )); then
      print -u2 "\ndispatch: STALLED -- no log output for ${STALL}s. Killing."
      print -u2 "dispatch: this is the hung-inference shape, not a slow round."
      kill -TERM "$RUN_PID" 2>/dev/null
      sleep 10
      kill -KILL "$RUN_PID" 2>/dev/null
      break
    fi
  done ) &
STALLDOG=$!

STATUS=0
wait "$RUN_PID" || STATUS=$?
kill "$WATCHDOG" 2>/dev/null || true
kill "$STALLDOG" 2>/dev/null || true
ELAPSED=$(( SECONDS - START ))

print "\ndispatch: exit $STATUS after ${ELAPSED}s"
if (( ELAPSED >= TIMEOUT )); then
  print -u2 "dispatch: TIMED OUT — killed at ${TIMEOUT}s. Treat as a non-converging round."
fi

print "\n--- last 40 lines of $LOG ---"
tail -40 "$LOG"

# A sandbox auto-reject is TERMINAL: the model does not recover, and the run ends
# wherever it happened. `opencode run` still exits 0, so without this the harness
# reports a successful round. Note `grep -c` prints 0 AND exits 1 on no match.
REJECTS=$(grep -ac 'auto-rejecting' "$LOG" 2>/dev/null || true)
REJECTS=${REJECTS:-0}
if (( REJECTS > 0 )); then
  print -u2 "\ndispatch: $REJECTS SANDBOX AUTO-REJECT(S) — the run was cut short there."
  print -u2 "dispatch: check the rejected path for a typo before blaming the model."
  print -u2 "dispatch: an absolute path outside the worktree is the usual cause."
  grep -a -B1 'auto-rejecting' "$LOG" | tail -6 | sed 's/^/  /' >&2
fi

print "\n--- working tree after round $ROUND (base $BASE_SHA) ---"
if [[ -z "$(git status --porcelain)" ]]; then
  print "NO CHANGES. The run produced nothing — count it as a failed round."
  print "Do NOT re-dispatch unchanged. Write the '## Review' section in this turn:"
  print "'nothing to review' is itself the review, and the next round must read it."
  exit 7
fi

# Ground truth for the suite, recorded next to whatever the round claimed.
# Two rounds have closed by asserting a passing count they never measured — one
# invented the arithmetic, one wrote "all tests pass" while four failed. The
# reviewer catches it by re-running, but that is one round late. Printing the
# real line into the round's own log puts the claim and the fact in one artifact.
if [[ -n "$VERIFY_CMD" ]]; then
  print "\n--- verification, run by the harness (not by the model) ---"
  SUITE_OUT="$RUN_LOG_DIR/$ISSUE-round$ROUND-verify.txt"
  ( cd "$VERIFY_DIR" && eval "$VERIFY_CMD" 2>&1 ) > "$SUITE_OUT" 2>&1 &
  SUITE_PID=$!
  ( sleep "$VERIFY_TIMEOUT"; kill -KILL "$SUITE_PID" 2>/dev/null ) &
  SUITE_DOG=$!
  wait "$SUITE_PID" 2>/dev/null || true
  kill "$SUITE_DOG" 2>/dev/null || true
  if [[ -n "$VERIFY_LINE_RE" ]]; then
    SUITE_LINE=$(grep -aE "$VERIFY_LINE_RE" "$SUITE_OUT" | tail -1 || true)
    if [[ -n "$SUITE_LINE" ]]; then
      print -r -- "$SUITE_LINE"
    else
      print "NO LINE MATCHING /$VERIFY_LINE_RE/. The suite did not build, or a test is blocking."
      print "An expected line that is absent is a FINDING, not an inconclusive result."
      print "First error:"
      grep -m1 -aE 'error:|Error:|FAILED' "$SUITE_OUT" || print "  (none found — see $SUITE_OUT)"
    fi
  else
    tail -20 "$SUITE_OUT"
  fi
fi

git status --short
print ""
git diff --stat
