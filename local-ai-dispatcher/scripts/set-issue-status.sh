#!/usr/bin/env zsh
#
# set-issue-status.sh <task-id> <status>
#
# Sets an issue's Status row to one of the five valid values, and refuses anything
# else. The tracker is what a human reads to know the state of the work, so an
# invalid or stale status is worse than no tracker at all.
#
#   open         filed, not started
#   in-progress  actively being worked — a dispatch is running, or it is under review
#   resolved     work landed on the default branch, awaiting the owner's confirmation
#   closed       the owner confirmed. ONLY THEY SET THIS.
#   wontfix      acknowledged, will not be addressed
#
# Two distinctions that are load-bearing:
#
#   resolved means MERGED, not merely accepted. A round that passes review but
#   sits unmerged is still in-progress; that is what stops a green branch being
#   mistaken for landed work.
#
#   Set it back to `open` when a round is abandoned. An issue stuck at
#   in-progress with nothing running is worse than one marked open, because it
#   reads as claimed and nobody picks it up.
#
# Exit 0 set, 1 usage/validation error.

set -u
setopt ERR_EXIT PIPE_FAIL

source "${0:A:h}/_common.sh"
load_conf "$0"

ISSUE="${1:-}"
STATUS="${2:-}"

VALID=(open in-progress resolved closed wontfix)

if [[ -z "$ISSUE" || -z "$STATUS" ]]; then
  print -u2 "usage: set-issue-status.sh <task-id> <${(j:|:)VALID}>"
  exit 1
fi

FILE=$(task_file "$ISSUE")
[[ -f "$FILE" ]] || { print -u2 "set-issue-status: $FILE does not exist"; exit 1 }

if [[ ${VALID[(Ie)$STATUS]} -eq 0 ]]; then
  print -u2 "set-issue-status: '$STATUS' is not a valid status.
Valid: ${(j:, :)VALID}
'closed' belongs to the project owner, not to an agent — use 'resolved' when
work lands and let them confirm."
  exit 1
fi

if [[ "$STATUS" == closed ]]; then
  print -u2 "set-issue-status: refusing to set 'closed'.
'resolved' says the work landed; 'closed' says the owner verified it. Keeping
them separate is the entire reason there are two states."
  exit 1
fi

if ! set_task_status "$FILE" "$STATUS"; then
  print -u2 "set-issue-status: $FILE carries no status field for TASK_STYLE=$TASK_STYLE.
Either add one, set TASK_STYLE in .dispatch.conf (table | frontmatter | none),
or track status however you already do — nothing else in this harness depends on
this script. Preflight simply skips the claim check when TASK_STYLE=none."
  exit 1
fi

print "set-issue-status: $ISSUE -> $STATUS"
print -r -- "  now: $(task_status "$FILE")"
