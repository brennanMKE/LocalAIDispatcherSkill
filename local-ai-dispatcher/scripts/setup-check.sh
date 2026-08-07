#!/usr/bin/env zsh
#
# setup-check.sh — verify the delegation harness before the first dispatch.
#
# This is the start-of-project checklist turned into a command. Every item here
# corresponds to something that failed SILENTLY on a real project: no error
# message, no non-zero exit, just a round that produced nothing or a rule the
# delegate never saw.
#
#   Exit 0   ready to dispatch
#   Exit 1   at least one hard check failed
#
# Run it again after changing the model, the config, or the machine.

set -u
setopt PIPE_FAIL

source "${0:A:h}/_common.sh"
load_conf "$0" || exit 1

FAILED=0
ok()   { print "  ok    $1" }
warn() { print "  warn  $1"; print "        $2" }
bad()  { print -u2 "  FAIL  $1"; print -u2 "        $2"; FAILED=1 }

print "setup-check in $REPO_ROOT"

# --- 1. AGENTS.md, and whether it actually reaches the model ----------------
# The single most important discovery on the reference project: OpenCode does not
# read CLAUDE.md. Asked to state a rule with only CLAUDE.md present, the model
# answered UNKNOWN while claiming CLAUDE.md was in its system prompt. Every
# licensing and signing rule was invisible to the delegate, and nothing errored.
if [[ -f AGENTS.md ]]; then
  ok "AGENTS.md exists ($(grep -c '^## Rule' AGENTS.md 2>/dev/null || print 0) numbered rules)"
  if grep -qiE '^\s*(see|read|refer to).*(CLAUDE|CONTRIBUTING)\.md' AGENTS.md; then
    warn "AGENTS.md points at another file for its rules" \
"Inline them. A model that ignores 'do not read any files' will also not follow
a pointer. Duplicate the non-negotiables verbatim and keep them in sync."
  fi
  print "        VERIFY BY RECITATION: ask the model to state a rule from AGENTS.md"
  print "        with no file reads. If it answers UNKNOWN, the file is not reaching"
  print "        the system prompt and nothing will tell you."
else
  bad "no AGENTS.md at the repo root" \
"OpenCode loads AGENTS.md, not CLAUDE.md. Start from the skill's
assets/AGENTS.md.template and inline every non-negotiable rule."
fi

# --- 2. The config the scripts read ------------------------------------------
if [[ -f .dispatch.conf ]]; then
  ok ".dispatch.conf present"
else
  warn "no .dispatch.conf — every script is running on defaults" \
"Copy assets/dispatch.conf.template and set at least VERIFY_CMD and
VERIFY_LINE_RE, or the harness cannot grade a round independently."
fi
[[ -n "$VERIFY_CMD" ]] && ok "VERIFY_CMD is set ($VERIFY_CMD)" \
  || bad "VERIFY_CMD is empty" \
"The harness must run verification itself. Two rounds have closed by asserting a
passing count they never measured; the reviewer caught it one round late."

# --- 3. No `timeout` binary on macOS -----------------------------------------
# `timeout` and `gtimeout` are both absent without coreutils. A dispatch with no
# wall-clock bound can loop indefinitely, which has happened.
if command -v timeout >/dev/null || command -v gtimeout >/dev/null; then
  ok "a timeout binary exists (the scripts use their own watchdog regardless)"
else
  ok "no timeout binary — expected on macOS; dispatch-issue.sh runs its own watchdog"
fi

# --- 4. The local model server -----------------------------------------------
if curl -sf -m 5 "$LOCAL_ENDPOINT/models" >/dev/null 2>&1; then
  MODEL_ID=$(curl -sf -m 5 "$LOCAL_ENDPOINT/models" \
    | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p' | head -1)
  ok "local server answering at $LOCAL_ENDPOINT (model: ${MODEL_ID:-unknown})"
else
  bad "no local model server at $LOCAL_ENDPOINT" \
"Start it and load a model, or every dispatch falls back to a billed round."
fi

# --- 5. The parallel limit, which is SILENT ----------------------------------
# LM Studio's PARALLEL setting does not report itself. A dispatch beyond it queues
# rather than running, and is indistinguishable from a very slow round.
if command -v lms >/dev/null; then
  # `lms ps` prints SIZE as "37.73 GB", which splits into two awk fields and
  # shifts everything after it. Join the unit back on first, then the columns are
  # ID / MODEL / STATUS / SIZE / CONTEXT / PARALLEL / DEVICE / TTL.
  PAR=$(lms ps 2>/dev/null | sed -E 's/([0-9]) (GB|MB|KB|TB)/\1\2/' \
        | awk '$1 != "IDENTIFIER" && NF >= 6 {print $6; exit}')
  if [[ -n "$PAR" && "$PAR" =~ '^[0-9]+$' ]]; then
    if [[ "$PAR" == "$LOCAL_PARALLEL" ]]; then
      ok "server PARALLEL=$PAR matches LOCAL_PARALLEL"
    else
      warn "server reports PARALLEL=$PAR but LOCAL_PARALLEL=$LOCAL_PARALLEL" \
"An extra concurrent dispatch queues SILENTLY. Make them agree."
    fi
  else
    warn "could not read PARALLEL from 'lms ps'" \
"Check it by hand before planning any fan-out."
  fi
else
  warn "lms not on PATH — cannot read the server's PARALLEL limit" \
"Confirm it another way. Exceeding it produces no error, only a very slow round."
fi

# --- 6. The output-token cap, which truncates tool calls silently ------------
# A model capped at 8192 output tokens cannot emit a large file inside one write
# call: the generation is cut mid-call, the content key never arrives, and the
# schema rejects it. One round re-emitted the identical failing call 188 times
# over 25 minutes. It reads as flakiness rather than as a ceiling.
OC_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/opencode.json"
if [[ -f "$OC_CONF" ]]; then
  CAP=$(grep -oE '"output"[[:space:]]*:[[:space:]]*[0-9]+' "$OC_CONF" | grep -oE '[0-9]+' | head -1)
  if [[ -n "$CAP" ]]; then
    if (( CAP >= 16384 )); then
      ok "opencode output cap is $CAP"
    else
      bad "opencode output cap is only $CAP" \
"That budget must hold the model's reasoning AND an entire file, JSON-escaped,
inside one write tool call. Raise it to 16384 in $OC_CONF. The symptom is
'SchemaError(Missing key at [\"content\"])' repeating until the round dies."
    fi
  else
    warn "no explicit output limit in $OC_CONF" \
"Set limit.output to at least 16384 so a large write can land in one call."
  fi
else
  warn "no opencode config at $OC_CONF" \
"The output cap defaults low on some providers; set it explicitly."
fi

# --- 7. Run logs must not enter the diff -------------------------------------
if [[ -f .gitignore ]] && grep -q "$RUN_LOG_DIR" .gitignore; then
  ok "$RUN_LOG_DIR is gitignored"
else
  bad "$RUN_LOG_DIR is not in .gitignore" \
"Round logs are artifacts, not deliverables, and an untracked-file list is what
the clean-tree guard reads."
fi
if [[ -f .gitignore ]] && grep -q "^/*${SCRATCH_DIR}/*$" .gitignore; then
  ok "$SCRATCH_DIR/ is gitignored"
else
  warn "$SCRATCH_DIR/ is not in .gitignore" \
"The implementer is told to put every scratch file there. If it is tracked, its
probes pollute the round's diff and the clean-tree guard misfires."
fi

# --- 8. The primary checkout must stay on the default branch -----------------
# Dispatching in it pins the default branch: no finished issue can be merged, and
# seven completed branches once queued behind one running round while the repo
# read as idle.
CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || print '?')
if [[ "$CUR" == issue/* ]]; then
  IS_LINKED=0
  git rev-parse --git-common-dir >/dev/null 2>&1 && \
    [[ "$(git rev-parse --git-dir)" != "$(git rev-parse --git-common-dir)" ]] && IS_LINKED=1
  if (( IS_LINKED )); then
    ok "on $CUR inside a linked worktree — correct place for a dispatch"
  else
    bad "the PRIMARY checkout is on $CUR" \
"Switch it back to the default branch and dispatch from a worktree:
  git worktree add -b $CUR ../$(basename $REPO_ROOT)-NNNN <default-branch>
A pinned default branch hides every finished issue behind the running round."
  fi
else
  ok "on '$CUR' (not an issue branch)"
fi

# --- 9. Is cost measurable at all? -------------------------------------------
# Decide how cost will be measured BEFORE the first delegated round. Retrofitting
# it onto completed work recovers only what the harness happened to report along
# the way.
if [[ -f "$HOME/.local/share/opencode/opencode.db" ]]; then
  ok "OpenCode session database present — local token volume is recoverable"
else
  warn "no OpenCode session database yet" \
"It appears after the first run. It is the ONLY durable record of local token
volume; the dispatch logs carry none and the server exposes no usage endpoint."
fi

print ""
if (( FAILED )); then
  print -u2 "setup-check: NOT READY — fix the FAIL items above before dispatching."
  exit 1
fi
print "setup-check: ready."
