#!/usr/bin/env zsh
#
# _common.sh — shared configuration and task-file access for the dispatcher scripts.
#
# Sourced, never executed. Every script here calls `load_conf` first, which sets
# REPO_ROOT, cds to it, and applies .dispatch.conf over the defaults.
#
# THE TASK TRACKER IS PLUGGABLE. These scripts need exactly two things from
# whatever system you use to break work down:
#
#   1. one file per task, at a path they can compute from a task id
#   2. optionally, a status field they can read and write
#
# Everything else — numbering, folder name, extra metadata, how you file things —
# is yours. `TASK_STYLE` selects how status and module are stored:
#
#   table        `| **Status** | open |` rows (the `issues` skill's format)
#   frontmatter  YAML `status: open` between `---` fences
#   none         no status field at all; the claim check is skipped
#
# If your format is none of those, override `task_status`, `set_task_status` and
# `task_module` in .dispatch.conf — it is sourced after these are defined, so a
# redefinition there wins.
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

# --- Defaults. Documented in assets/dispatch.conf.template. -------------------

# Where task files live, and how a task id maps to one. The defaults match the
# `issues` skill (issues/0042.md) because that is the most common setup, not
# because anything here requires it.
: ${TASK_DIR:=${ISSUE_DIR:-issues}}
: ${TASK_EXT:=.md}
: ${TASK_ID_RE:=^[0-9]{4}$}
: ${TASK_STYLE:=table}
# When the format carries no module/type field, assume the task is code and apply
# the strict checks. Being wrong in that direction costs a warning; being wrong in
# the other direction silently skips the verification check, which is the one that
# matters most.
: ${CODE_TASK_DEFAULT:=1}

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

# --- Task file access ---------------------------------------------------------

# The path holding one task's spec.
task_file() { print -r -- "$TASK_DIR/$1$TASK_EXT" }

# The task's current status, or empty when the format carries none. Empty is a
# valid answer, not an error — TASK_STYLE=none is a supported setup.
task_status() {
  local f="$1"
  case "$TASK_STYLE" in
    table)
      grep -m1 '^| \*\*Status\*\*' "$f" 2>/dev/null \
        | sed 's/^| \*\*Status\*\* | *//; s/ *|$//' || true ;;
    frontmatter)
      awk '/^---[[:space:]]*$/{n++; next} n==1 && /^status:/{sub(/^status:[[:space:]]*/,""); print; exit}' \
        "$f" 2>/dev/null || true ;;
    *) print -r -- "" ;;
  esac
}

# Rewrite the status in place. Returns 1 when the format has no status field, so
# callers can say so rather than silently doing nothing.
set_task_status() {
  local f="$1" s="$2"
  case "$TASK_STYLE" in
    table)
      grep -q '^| \*\*Status\*\*' "$f" || return 1
      sed -i '' -E "s/^(\| \*\*Status\*\* \| ).*(\|)\$/\1$s \2/" "$f" 2>/dev/null \
        || sed -i -E "s/^(\| \*\*Status\*\* \| ).*(\|)\$/\1$s \2/" "$f" ;;
    frontmatter)
      grep -q '^status:' "$f" || return 1
      sed -i '' -E "s/^status:.*\$/status: $s/" "$f" 2>/dev/null \
        || sed -i -E "s/^status:.*\$/status: $s/" "$f" ;;
    *) return 1 ;;
  esac
}

# What kind of work this is, used only to decide whether the strict code checks
# apply. Empty means "the format does not say", which is different from "docs".
task_module() {
  local f="$1"
  case "$TASK_STYLE" in
    table)
      grep -m1 '^| \*\*Module\*\*' "$f" 2>/dev/null \
        | sed 's/^| \*\*Module\*\* | *//; s/ *|$//' || true ;;
    frontmatter)
      awk '/^---[[:space:]]*$/{n++; next} n==1 && /^module:/{sub(/^module:[[:space:]]*/,""); print; exit}' \
        "$f" 2>/dev/null || true ;;
    *) print -r -- "" ;;
  esac
}

# --- Repo resolution ----------------------------------------------------------

# Resolve the repo root from the script's own location rather than from $PWD.
# Each worktree carries its own copy of scripts/, so this lands in the worktree
# the dispatch is actually running in — which is also how per-task token
# attribution works. `git rev-parse` is the fallback for an out-of-tree copy.
#
# .dispatch.conf is sourced LAST so a project can override any default above,
# including the task_* functions.
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
