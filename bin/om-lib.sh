#!/usr/bin/env bash
# om-lib.sh — shared resolution for every om-*.sh script. Source it, never run it.
#
# Home resolution, in order:
#   1. $OM_HOME, when set (an operator running several homes on one machine)
#   2. the nearest ancestor of $PWD carrying a .om-home marker
#   3. the repository this script lives in, resolved through the install symlink
#
# Step 2 is not a nicety, it is the load-bearing one. Omnigent's shell tool
# passes a fixed environment allowlist through to commands — PATH, HOME, PWD
# and friends — and OM_HOME is not on it. An agent running in a home other than
# the checkout therefore invokes these scripts with OM_HOME unset, and without
# a marker to find they would all quietly operate on the checkout instead:
# cloning projects into the shared template, writing records there, and cutting
# worktrees in the wrong place. The session's working directory IS the home, so
# that is what we resolve from.
#
# A home owns data/ state/ config/ projects/ worktrees/. Scripts come from the
# tracked code root, which is the same directory unless the home says otherwise.
set -euo pipefail

om_code_root() {
  local src="${BASH_SOURCE[0]}" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  (cd -P "$(dirname "$src")/.." && pwd)
}

OM_CODE_ROOT="$(om_code_root)"

om_find_home() {
  if [ -n "${OM_HOME:-}" ]; then
    printf '%s' "$OM_HOME"
    return 0
  fi
  local d="$PWD"
  while [ "$d" != "/" ] && [ -n "$d" ]; do
    if [ -f "$d/.om-home" ]; then
      printf '%s' "$d"
      return 0
    fi
    d="$(dirname "$d")"
  done
  printf '%s' "$OM_CODE_ROOT"
}

OM_HOME="$(om_find_home)"
export OM_CODE_ROOT OM_HOME

OM_DATA="$OM_HOME/data"
OM_STATE="$OM_HOME/state"
OM_CONFIG="$OM_HOME/config"
OM_PROJECTS="$OM_HOME/projects"
OM_WORKTREES="$OM_HOME/worktrees"
export OM_DATA OM_STATE OM_CONFIG OM_PROJECTS OM_WORKTREES

om_ensure_home() {
  mkdir -p "$OM_DATA" "$OM_STATE" "$OM_STATE/crew" "$OM_CONFIG" "$OM_PROJECTS" "$OM_WORKTREES"
  # The marker is what makes this directory findable as a home from a working
  # directory alone, with no environment to rely on.
  [ -f "$OM_HOME/.om-home" ] || printf 'omni-mate home\n' > "$OM_HOME/.om-home"
}

om_die() { echo "${0##*/}: $*" >&2; exit 1; }

# A task id is <t><NNN>-<slug>: sortable, greppable, and safe as a branch
# segment, a directory name, and a session title all at once.
om_slug() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-40
}

om_next_id() {
  local counter="$OM_STATE/.task-counter" n
  n=$(cat "$counter" 2>/dev/null || echo 0)
  n=$((n + 1))
  printf '%s' "$n" > "$counter"
  printf 't%03d' "$n"
}

# Reads one field out of a task's meta record. Meta is flat key=value so that
# both bash and an agent reading the raw file get the same answer.
om_meta_get() {
  local id="$1" key="$2" file="$OM_STATE/$1.meta" value
  [ -f "$file" ] || return 1
  # tail -1, not head -1. om_meta_set rewrites in place, so a well-formed
  # record holds each key once — but anything that appends instead (a hand
  # edit, an agent with a file tool) leaves the older value on top, and a
  # reader that takes the first one silently reports stale state. Last wins.
  value="$(sed -n "s/^${key}=//p" "$file" | tail -1)"
  # A MISSING KEY must fail, not succeed with nothing. Every caller writes
  # `om_meta_get <id> <key> || echo <default>`, and while this returned 0 for a
  # key that was not there, every one of those defaults was dead code: the
  # caller got the empty string and carried on with it. Measured consequence —
  # a record missing its `base=` line drove the landed-work test to
  # "no ref to compare against" and called merged work unlanded, which is the
  # permanently-un-tearable failure 46b291b was supposed to have closed.
  [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

om_meta_set() {
  local id="$1" key="$2" value="$3" file="$OM_STATE/$1.meta" tmp
  tmp="$(mktemp)"
  if [ -f "$file" ]; then grep -v "^${key}=" "$file" > "$tmp" || true; fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

# Counts a worktree's uncommitted and untracked files, or fails.
#
# `git status --porcelain | wc -l` looks harmless and is not: git exits 128 when
# the directory exists but is not a working tree (a dangling .git file, a
# worktree whose clone was removed), 2>/dev/null hides the message, pipefail
# promotes the 128 to the pipeline, and the plain assignment takes the whole
# script down under set -e. Measured: om-teardown.sh --check printed NOTHING and
# returned 128 on such a fixture — the verdict its caller depends on never
# appeared at all. Callers must decide what a broken worktree means; that is not
# a decision to make inside a counter.
#
# Prints the count and returns 0, or prints nothing and returns 1.
om_worktree_dirty_count() {
  local wt="$1" out
  git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  out="$(git -C "$wt" status --porcelain -uall 2>/dev/null)" || return 1
  # No `grep -c` here, and that is the second lesson from the same audit: on a
  # CLEAN worktree the output is empty, grep matches nothing, and grep exits 1 —
  # which pipefail hands back as "this worktree is unreadable". The first
  # version of this very function had that bug and made every clean teardown
  # refuse. An empty string is zero lines; say so directly.
  if [ -z "$out" ]; then
    printf '0\n'
  else
    # printf adds exactly one trailing newline, which is what wc -l counts by.
    printf '%s\n' "$out" | wc -l | tr -d ' '
  fi
}

om_task_ids() {
  [ -d "$OM_STATE" ] || return 0
  find "$OM_STATE" -maxdepth 1 -name 't[0-9][0-9][0-9]*.meta' 2>/dev/null \
    | sed -e 's#.*/##' -e 's/\.meta$//' | sort
}
