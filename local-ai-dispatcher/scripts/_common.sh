#!/usr/bin/env zsh
#
# _common.sh — shared configuration loading for the dispatcher scripts.
#
# Sourced, never executed. Every script here calls `load_conf` first, which sets
# REPO_ROOT, cds to it, and applies .dispatch.conf over the defaults.
#
# Two portability notes, both learned the hard way:
#
#   * `cat` and `date` are not reliably available to a script an agent harness
#     runs, even when the calling shell has both. `ls`, `sed`, `grep`, `awk`,
#     `sort` and `tail` all work in the same context. The zsh builtins are used
#     instead — `$(</dev/stdin)` and `zsh/datetime` — and they are better anyway.
#
#   * macOS has no `timeout` or `gtimeout` without coreutils. Every bound in this
#     harness is a backgrounded watchdog, not a wrapper binary.

zmodload zsh/datetime 2>/dev/null || true

# Defaults. Documented in assets/dispatch.conf.template; a project overrides them
# by writing .dispatch.conf at its repo root.
: ${ISSUE_DIR:=issues}
: ${RUN_LOG_DIR:=.dispatch-runs}
: ${TIMEOUT:=1800}
: ${STALL:=420}
: ${MAX_ROUNDS:=3}
: ${LOCAL_ENDPOINT:=http://127.0.0.1:1234/v1}
: ${LOCAL_PARALLEL:=2}
: ${HOSTED_MODEL:=anthropic/claude-sonnet-5}
: ${VERIFY_CMD:=}
: ${VERIFY_DIR:=.}
: ${VERIFY_LINE_RE:=}
: ${VERIFY_TIMEOUT:=300}
: ${UNTESTABLE_PATH_RE:=}
: ${SOURCE_EXTS:=swift|ts|tsx|js|jsx|py|go|rs|kt|java|rb|c|h|cpp|hpp|cc|m|mm}
: ${BASELINE_FILE:=}
: ${SCRATCH_DIR:=build}

# Resolve the repo root from the script's own location rather than from $PWD.
# Each worktree carries its own copy of scripts/, so this lands in the worktree
# the dispatch is actually running in — which is also how per-issue token
# attribution works. `git rev-parse` is the fallback for an out-of-tree copy.
load_conf() {
  local script_dir="${1:A:h}"
  REPO_ROOT="${script_dir:h}"
  if [[ ! -d "$REPO_ROOT/.git" && ! -f "$REPO_ROOT/.git" ]]; then
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
      print -u2 "not inside a git repository"; return 1
    }
  fi
  cd "$REPO_ROOT" || return 1
  [[ -f .dispatch.conf ]] && source ./.dispatch.conf
  return 0
}

# `stat -f` is BSD, `stat -c` is GNU. Prints the mtime of $1 as an epoch second,
# or 0 if it cannot be read.
file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || print 0
}

now_epoch() { print "${EPOCHSECONDS:-0}" }
