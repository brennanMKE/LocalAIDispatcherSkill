#!/usr/bin/env zsh
#
# tally-local-tokens.sh [--markdown] [--model SUBSTRING] [--prefix WORKTREE-PREFIX]
#
# Tallies what the local model has actually processed, per issue.
#
# WHY THIS SCRIPT EXISTS, which is the part worth carrying to another project:
# nothing else records it. The dispatch logs carry no token counts, LM Studio
# exposes no historical usage endpoint, and a dispatcher subagent's reported token
# figure appears once in a completion notification and is gone when the session
# ends. OpenCode's SQLite database records tokens_input / tokens_output per
# session and SURVIVES — which is why this file is regenerable rather than a
# snapshot someone has to remember to update.
#
# Issue attribution comes from the session's working directory: a dispatch runs in
# ../<project>-NNNN, so the worktree name is the issue number. That is another
# reason a dispatch must never run in the primary checkout — it would land in
# "(main)" with no issue attached.
#
# The hosted column is a COUNTERFACTUAL, not a saving: what the same traffic would
# have cost on the hosted model this local one replaces. Actual cost is $0.00.

set -u
setopt ERR_EXIT PIPE_FAIL

DB="${OPENCODE_DB:-$HOME/.local/share/opencode/opencode.db}"
[[ -f "$DB" ]] || { print -u2 "tally: no OpenCode database at $DB"; exit 1 }
command -v sqlite3 >/dev/null || { print -u2 "tally: sqlite3 not on PATH"; exit 1 }

MARKDOWN=0
MODEL_MATCH="${MODEL_MATCH:-}"
PREFIX="${PREFIX:-$(basename "$(git rev-parse --show-toplevel 2>/dev/null || print .)")}"

while (( $# )); do
  case "$1" in
    --markdown) MARKDOWN=1; shift ;;
    --model)    MODEL_MATCH="$2"; shift 2 ;;
    --prefix)   PREFIX="$2"; shift 2 ;;
    -h|--help)  sed -n '2,25p' "$0"; exit 0 ;;
    *) print -u2 "tally: unknown argument '$1'"; exit 2 ;;
  esac
done

# What the same traffic would have cost hosted. State the rate wherever the
# derived number appears — a figure whose derivation is invisible is
# indistinguishable from an invented one.
IN_RATE=${IN_RATE:-3.0}
OUT_RATE=${OUT_RATE:-15.0}

MODEL_CLAUSE=""
[[ -n "$MODEL_MATCH" ]] && MODEL_CLAUSE="AND model LIKE '%${MODEL_MATCH}%'"

QUERY="
SELECT
  CASE
    WHEN directory LIKE '%${PREFIX}-%'
      THEN substr(directory, instr(directory, '${PREFIX}-') + ${#PREFIX} + 1)
    ELSE '(main)'
  END AS issue,
  SUM(tokens_input),
  SUM(tokens_output),
  COUNT(*)
FROM session
WHERE directory LIKE '%${PREFIX}%'
  ${MODEL_CLAUSE}
GROUP BY issue
ORDER BY issue;
"

rows=$(sqlite3 -separator '|' "$DB" "$QUERY")

if (( MARKDOWN )); then
  print "| Issue | Sessions | Input tokens | Output tokens | Total | Hosted equivalent |"
  print "|---|---|---|---|---|---|"
else
  printf "%-8s %9s %14s %13s %14s %12s\n" ISSUE SESSIONS INPUT OUTPUT TOTAL "IF HOSTED"
fi

typeset -i ti=0 to=0 ts=0
while IFS='|' read -r issue tin tout sess; do
  [[ -n "$issue" ]] || continue
  # The worktree name is the LAST path component, but a session started in a
  # subdirectory carries more after it. Keep only the id. Taking a fixed 4
  # characters here instead would silently truncate any non-NNNN task id.
  issue=${issue%%/*}
  ti+=$tin; to+=$tout; ts+=$sess
  total=$(( tin + tout ))
  cost=$(printf "%.2f" $(( tin / 1000000.0 * IN_RATE + tout / 1000000.0 * OUT_RATE )))
  label=$issue
  [[ "$issue" != "(main)" ]] && label="#$issue"
  if (( MARKDOWN )); then
    printf "| %s | %s | %'d | %'d | %'d | \$%s |\n" "$label" "$sess" "$tin" "$tout" "$total" "$cost"
  else
    printf "%-8s %9s %14s %13s %14s %12s\n" "$label" "$sess" \
      "$(printf "%'d" $tin)" "$(printf "%'d" $tout)" "$(printf "%'d" $total)" "\$$cost"
  fi
done <<< "$rows"

grand=$(( ti + to ))
saved=$(printf "%.2f" $(( ti / 1000000.0 * IN_RATE + to / 1000000.0 * OUT_RATE )))

if (( MARKDOWN )); then
  printf "| **Total** | **%d** | **%'d** | **%'d** | **%'d** | **\$%s** |\n" "$ts" "$ti" "$to" "$grand" "$saved"
  print ""
  print "Actual cost: **\$0.00** — the model runs locally. The last column is what this"
  print "traffic would have cost hosted at \$${IN_RATE}/MTok in, \$${OUT_RATE}/MTok out."
else
  print ""
  printf "%-8s %9s %14s %13s %14s %12s\n" TOTAL "$ts" \
    "$(printf "%'d" $ti)" "$(printf "%'d" $to)" "$(printf "%'d" $grand)" "\$$saved"
  print ""
  print "Actual cost: \$0.00 — the model runs locally. The last column is what this"
  print "traffic would have cost hosted at \$${IN_RATE}/MTok in, \$${OUT_RATE}/MTok out."
fi

# The number that matters most is not in this table: INPUT OUTWEIGHS OUTPUT BY
# ROUGHLY 100 TO 1. That is the shape of an agentic loop, not of this model —
# every turn resends the accumulated context, so a long round re-reads its own
# transcript hundreds of times. It is the strongest argument for running the
# implementer locally: on a hosted model that ratio IS the bill.
#
# And the second: THE MOST EXPENSIVE ROUNDS ARE THE ONES THAT FAILED. Well over
# half the total volume in the reference project went on rounds that were rejected
# or abandoned. That is the cost of authoring defects, and it is invisible in the
# dollar column precisely because it is free. Free failure is the kind that stops
# being noticed.
