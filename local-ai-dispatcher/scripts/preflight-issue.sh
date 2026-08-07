#!/usr/bin/env zsh
#
# preflight-issue.sh <task-id> [--quiet]
#
# Checks an issue against the mechanical authoring defects that have each already
# cost a round. Run it while AUTHORING, when there is still time to fix the issue
# cheaply; dispatch-issue.sh also runs it and refuses to dispatch on exit 9.
#
#   Exit 0   all hard checks pass (warnings may still print)
#   Exit 9   a hard check failed; fix the issue text before dispatching
#
# TWO THINGS ABOUT WRITING GUARDS, both learned by nearly shipping the opposite:
#
#   1. Every grep pipeline here ends in `|| true`. This script runs under ERR_EXIT
#      and PIPE_FAIL, and a grep that matches nothing exits 1 — which is the
#      COMMON path for most of these checks. A guard that kills the script on
#      every healthy issue looks identical to a guard that works, right up until
#      someone tries to get through it.
#
#   2. Test every new check on input that should PASS, not only on input that
#      should fail. The failure mode of a filter is not "misses a bad case", it is
#      "blocks the good ones", and only a negative control finds that.
#
# Heuristics over prose WARN rather than block, for the same reason.

set -u
setopt ERR_EXIT PIPE_FAIL

source "${0:A:h}/_common.sh"
load_conf "$0"

QUIET=0
ISSUE=""
while (( $# )); do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    *)       ISSUE="$1"; shift ;;
  esac
done

[[ -n "$ISSUE" ]] || { print -u2 "usage: preflight-issue.sh <task-id> [--quiet]"; exit 1 }
FILE=$(task_file "$ISSUE")
[[ -f "$FILE" ]] || { print -u2 "preflight: $FILE does not exist (TASK_DIR=$TASK_DIR, TASK_EXT=$TASK_EXT)"; exit 1 }

# Checks run against the SPEC only — everything above the first `## Review`,
# `## Work log`, or `## Sequencing` heading. Those sections narrate what went
# wrong in a past round, and discussing a bad path there is correct prose, not a
# defect. An earlier version scanned the whole file and rejected an issue for
# documenting its own post-mortem.
SPEC=$(mktemp -t preflight-spec)
trap 'rm -f "$SPEC"' EXIT
awk '/^## (Review|Work log|Sequencing)/{exit} {print}' "$FILE" > "$SPEC"

# A code task must meet stricter checks than a docs or decision task, which
# legitimately names no source file and runs no test suite. If the task format
# carries a module/type field, use it; otherwise fall back to CODE_TASK_DEFAULT.
#
# The fallback defaults to STRICT on purpose. Guessing "docs" skips the hard
# verification check, and an issue reading as clean while the check that matters
# most never ran is exactly how seven defective tasks got queued.
MODULE_RAW=$(task_module "$FILE")
IS_CODE=$CODE_TASK_DEFAULT
case "${MODULE_RAW:l}" in
  *doc*|*decision*|*research*|*spike*) IS_CODE=0 ;;
  ?*) IS_CODE=1 ;;
esac

FAILED=0
say()  { (( QUIET )) || print "$@" }
pass() { say "  PASS  $1" }
warn() { say "  WARN  $1"; say "        $2" }
fail() { print -u2 "  FAIL  $1"; print -u2 "        $2"; FAILED=1 }

say "preflight $FILE  (module: ${MODULE_RAW:-none}, code: $IS_CODE)"

# --- Check 1 — the module/type field, when the format has one ----------------
# An empty module field made this script classify a task as non-code, which
# SKIPPED the hard verification check. Seven tasks sat that way, each reading as
# clean while the check that matters most was never run.
#
# Only enforced when the format actually carries the field. With TASK_STYLE=none
# there is nothing to fill in and CODE_TASK_DEFAULT decides instead.
if [[ "$TASK_STYLE" == none ]]; then
  pass "no module field in this format; treating as code=$IS_CODE (CODE_TASK_DEFAULT)"
elif [[ -z "${MODULE_RAW// /}" ]]; then
  fail "the module field is empty" \
"An empty module classifies this as a non-code task and SKIPS the verification
check. Fill it in, or set TASK_STYLE=none if your format has no such field."
else
  pass "module is set ($MODULE_RAW)"
fi

# --- Check 2 — the task must be claimed before work starts -------------------
# The tracker is what a human reads to know what is being worked on. Tasks were
# going straight from open to done, so an actively running dispatch showed as
# untouched. Gate it rather than trusting anyone to remember.
#
# Skipped entirely when the format carries no status. That is a supported setup,
# not a defect — but you lose the signal that says which task is live, so
# something else has to carry it.
if [[ "$TASK_STYLE" == none ]]; then
  pass "no status field in this format; claim check skipped"
else
  STATUS=$(task_status "$FILE")
  if [[ "$STATUS" == "in-progress" ]]; then
    pass "task is claimed (in-progress)"
  else
    fail "task status is '$STATUS', not 'in-progress'" \
"Claim it before dispatching:  ./scripts/set-issue-status.sh $ISSUE in-progress
Set it back to 'open' if the round is abandoned — a task stuck at in-progress
with nothing running reads as claimed and nobody picks it up."
  fi
fi

# --- Check 3 (HARD) — scratch paths outside the worktree ---------------------
# The sandbox auto-rejects external_directory writes and the rejection is
# terminal. Four rounds have been damaged or lost to this. A line that WARNS
# about those paths is fine; a line that directs work there is not.
OUTSIDE=$(grep -nE '(^|[^A-Za-z0-9_/])((/private)?/(var/)?tmp/|\$TMPDIR)' "$SPEC" \
  | grep -viE 'reject|cannot|never|not |outside|denie|denied|fail|instead of' || true)
if [[ -n "$OUTSIDE" ]]; then
  fail "directs work to a path outside the worktree" \
"$OUTSIDE
The sandbox auto-rejects writes there and the round produces nothing. Use a
$SCRATCH_DIR/-relative path."
else
  pass "no scratch path outside the worktree"
fi

# --- Check 4 (HARD for code) — names a concrete source file ------------------
# The strongest signal in the whole failure log: every code round that failed
# named zero source paths; every round that converged first try named exactly one.
# Extract every path-shaped token, then keep the ones whose extension is a source
# extension. Matching the extension inside the -o pattern instead looks correct
# and is not: `docs/findings.md` matches a pattern ending in `|m)` and reports a
# source file that does not exist. Anchoring the extension with `$` after the
# token is extracted is the only form that cannot do that.
NAMED=$(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+' "$SPEC" | sort -u \
  | grep -E "\.(${SOURCE_EXTS})\$" || true)
if [[ -n "$NAMED" ]]; then
  pass "names $(print -r -- "$NAMED" | grep -c . || true) source file(s)"
elif (( IS_CODE )); then
  fail "names no source file to create or edit" \
"Name the file, by full repo-relative path. 'Implement X' leaves the model to
invent a file layout mid-round; 'create path/to/X.ext' does not."
else
  warn "names no source file" \
"Fine for a docs or decision issue. Otherwise name the file."
fi

# --- Check 5 (HARD) — a path that cannot hold a tested unit ------------------
# A named path is a CLAIM ABOUT THE BUILD SYSTEM, and it can be wrong. One round
# burned itself discovering that the path the issue chose could not be linked
# into a test target; four queued issues carried the identical defect.
if [[ -n "$UNTESTABLE_PATH_RE" ]]; then
  BAD=$(grep -oE "$UNTESTABLE_PATH_RE" "$SPEC" | sort -u || true)
  if [[ -n "$BAD" ]]; then
    fail "names a path that cannot hold a tested unit" \
"$BAD
Move it somewhere the test target can reach. Check the path against the build
manifest before writing it into an issue."
  else
    pass "no untestable path named"
  fi
fi

# --- Check 6 (HARD for code) — names a verification command ------------------
# Without one, a round cannot be graded and "the model said it passed" is the
# only evidence. One round was accepted that way and later rejected.
if (( IS_CODE )); then
  # Match the literal command, or the exact line its output must contain. Matching
  # only the command's first word ('swift', 'npm') passes any issue that happens to
  # mention the language — a check that cannot fail is the defect this whole
  # harness exists to catch, and it applies to the harness too.
  if grep -qaF "$VERIFY_CMD" "$SPEC" \
     || { [[ -n "$VERIFY_LINE_RE" ]] && grep -qaE "$VERIFY_LINE_RE" "$SPEC" }; then
    # A count with no baseline is not evidence. A round once added eight tests in
    # a framework the summary line does not count: the reported number was
    # IDENTICAL with the new file deleted, and the criterion still "passed".
    if grep -qiE 'greater than|more than|must (be )?(exceed|increase)|higher than' "$SPEC"; then
      pass "names a verification command with a baseline count"
    else
      warn "names a verification command but no baseline count" \
"State what N must EXCEED, e.g. \"N must be greater than 83, the count on the
default branch before this change\". An absolute reading of a number proves only
that the number exists."
    fi
  else
    fail "names no verification command" \
"State the exact command and the exact line its output must contain. Otherwise
the round cannot be graded."
  fi
fi

# --- Check 7 (WARN) — the stated baseline matches reality --------------------
# A round was reviewed against a baseline of 216 when the default branch was 225.
# A stale number hides a small increase, which is precisely what the criterion
# exists to catch.
if [[ -n "$BASELINE_FILE" && -f "$BASELINE_FILE" ]]; then
  REAL=$(<"$BASELINE_FILE")
  # The phrase often wraps across a line break, so flatten whitespace before
  # matching — the first version of this check missed every wrapped one and
  # printed nothing, which read as "no baseline stated".
  STATED=$(tr '\n' ' ' < "$SPEC" \
    | grep -oE '(greater than|more than|higher than|baseline of|reported|currently) +[0-9]+' \
    | grep -oE '[0-9]+' | head -1 || true)
  if [[ -n "$STATED" && -n "$REAL" && "$STATED" != "$REAL" ]]; then
    warn "issue states a baseline of $STATED, but $BASELINE_FILE says $REAL" \
"A stale baseline hides a small increase. Update the issue before dispatching."
  elif [[ -n "$STATED" ]]; then
    pass "stated baseline $STATED matches $BASELINE_FILE"
  fi
fi

# --- Check 8 (HARD) — a referenced branch must be present in this tree -------
# One round was told to "start from issue/0011", but its worktree was cut from the
# default branch, which does not contain that branch's files. A one-field type
# change became a from-scratch reimplementation, and was rejected.
BRANCH_REFS=$(grep -oE 'issue/[0-9]{4}' "$SPEC" | sort -u || true)
BAD_BASE=""
for dep in ${(f)BRANCH_REFS}; do
  [[ -n "$dep" ]] || continue
  [[ "$dep" == "issue/$ISSUE" ]] && continue
  # A line telling the model NOT to start from a branch is guidance, not a base
  # requirement.
  grep -n "$dep" "$SPEC" | grep -qiE 'do not|don.t|never|not start|rather than|instead of' && continue
  git rev-parse --verify -q "$dep" >/dev/null 2>&1 || continue
  git merge-base --is-ancestor "$dep" HEAD 2>/dev/null || BAD_BASE+="$dep "
done
if [[ -n "$BAD_BASE" ]]; then
  fail "depends on a branch that is not in this tree: $BAD_BASE" \
"The issue tells the implementer to build on that branch, but it is not an
ancestor of HEAD, so none of its files are present. Cut this worktree from that
branch, or rewrite the issue to not depend on it."
else
  pass "no dependency on an absent branch"
fi

# --- Check 9 (WARN) — asks the implementer to discover rather than apply -----
# Verification is the REVIEWER's job; the implementer applies conclusions. One
# round died because review feedback told it to verify a fact, which needs a
# scratch directory the sandbox denies — the feedback itself made the round
# unrunnable.
VERIFY_ASK=$(grep -naE "rather than trusting|run .?-h.? |check (the )?current usage|verify (the )?current|verify (how|where|whether)|confirm whether|determine whether|find out (what|whether)" "$SPEC" || true)
if [[ -n "$VERIFY_ASK" ]]; then
  warn "asks the implementer to discover a fact rather than stating it" \
"$VERIFY_ASK
Run it yourself and write the result into a '## Givens' block as fact.
A criterion checking the round's own output is fine; a research task is not."
else
  pass "states facts rather than delegating discovery"
fi

# --- Check 10 (WARN) — is anything left to go and find? ----------------------
# A round spent its only productive minutes handing discovery to a subagent and
# then hung on the handoff. That handoff appears in four of the last five failed
# rounds. If the issue pastes every signature inline there is nothing to explore.
if (( IS_CODE )) && ! grep -qa '```' "$SPEC"; then
  warn "the spec contains no code block" \
"Issues carrying measured code converged in one round; issues describing the
work in prose did not. Paste the signatures the round must CALL, and the public
members of each result type."
else
  (( IS_CODE )) && pass "the spec pastes code"
fi

# --- Check 11 (WARN) — concurrency headroom ----------------------------------
# The local server's parallel limit is SILENT: an extra dispatch queues rather
# than running, and is indistinguishable from a very slow round.
RUNNING=$(pgrep -f 'opencode run' 2>/dev/null | grep -c . || true)
RUNNING=${RUNNING:-0}
if (( RUNNING >= LOCAL_PARALLEL )); then
  warn "$RUNNING dispatches already running (server limit is $LOCAL_PARALLEL)" \
"Another would queue silently rather than run. Wait for a slot."
else
  pass "$RUNNING/$LOCAL_PARALLEL dispatch slots in use"
fi

if (( FAILED )); then
  print -u2 "preflight: FAILED — fix $FILE, commit the planning update, then dispatch."
  exit 9
fi
say "preflight: ok"
exit 0
