#!/usr/bin/env bash
# om-teardown.sh — remove a task's worktree, but never its unlanded work.
#
#   om-teardown.sh <id>            tear down, refusing if work would be lost
#   om-teardown.sh <id> --check    report the verdict, change nothing
#   om-teardown.sh <id> --force    discard anyway (captain-authorized ONLY)
#
# This script owns the complete landed-work test, and its refusal is a finding,
# not an obstacle. Work counts as landed when the tree is clean AND every
# commit on the task branch is reachable from either the project's upstream
# base (it merged) or the branch's own upstream (it is pushed and lives on the
# forge). Anything else — uncommitted edits, untracked files, commits that
# exist nowhere but this worktree — means tearing down would destroy the only
# copy, and the script stops.
#
# A scout worktree is different: it is declared scratch, so it may be discarded
# once its report has been harvested into data/<id>/report.md. That harvest
# runs first, and a scout with no report is refused like anything else.
#
# --force exists because the captain may legitimately say "throw it away". It
# is never the agent's own call.
set -euo pipefail
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"
om_ensure_home

id="${1:-}"; shift || true
[ -n "$id" ] || om_die "usage: om-teardown.sh <id> [--check|--force]"
[ -f "$OM_STATE/$id.meta" ] || om_die "unknown task: $id"

mode=teardown
while [ $# -gt 0 ]; do
  case "$1" in
    --check) mode=check; shift ;;
    --force) mode=force; shift ;;
    *) om_die "unknown argument: $1" ;;
  esac
done

kind="$(om_meta_get "$id" kind || echo ship)"
project="$(om_meta_get "$id" project || echo '?')"
wt="$(om_meta_get "$id" worktree || true)"
branch="$(om_meta_get "$id" branch || true)"
base="$(om_meta_get "$id" base || echo main)"
ppath="$OM_PROJECTS/$project"

# ── Harvest a scout's report before anything can remove it ──────────────────
harvested=no
if [ -n "$wt" ] && [ -f "$wt/.om/report.md" ]; then
  mkdir -p "$OM_DATA/$id"
  cp "$wt/.om/report.md" "$OM_DATA/$id/report.md"
  harvested=yes
fi

# ── The landed-work test ────────────────────────────────────────────────────
verdict=landed
reasons=""
add_reason() { reasons="${reasons}  - $1
"; }

if [ -z "$wt" ] || [ ! -d "$wt" ]; then
  verdict=gone
  add_reason "no worktree on disk at ${wt:-<unrecorded>}"
else
  if dirty="$(om_worktree_dirty_count "$wt")"; then
    if [ "$dirty" != "0" ]; then
      verdict=unlanded
      add_reason "$dirty uncommitted or untracked file(s) in the worktree"
    fi
  else
    # Git cannot read this directory, so nothing about its contents can be
    # proven — least of all that removing it loses nothing. Fail safe: refuse,
    # and say why. The old code aborted the whole script with status 128 here
    # and printed no verdict at all, which a caller could not tell from silence.
    verdict=unlanded
    add_reason "git cannot read this worktree — contents unprovable, refusing to guess"
  fi

  # Commits that live only here: on the branch, reachable from neither the
  # upstream base nor the branch's own remote.
  if git -C "$wt" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    # Somewhere-other-than-here is what makes work safe to remove, and there
    # are three somewheres. The LOCAL base branch counts: a local-only project
    # delivers by merging into it, and after that the worktree holds no copy of
    # anything. Leaving it out made every local-only task permanently
    # un-tearable — the work had landed exactly as its mode intended, and the
    # test still called it unlanded because no remote had heard of it.
    haverefs=""
    for ref in "$base" "origin/$base" "origin/$branch"; do
      if git -C "$wt" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
        haverefs="$haverefs ^$ref"
      fi
    done
    if [ -n "$haverefs" ]; then
      # shellcheck disable=SC2086
      orphans="$(git -C "$wt" rev-list --count HEAD $haverefs 2>/dev/null || echo 0)"
    else
      # Not even the base resolves. Nothing can be proven safe, so nothing is.
      orphans="$(git -C "$wt" rev-list --count HEAD 2>/dev/null || echo 0)"
      add_reason "no ref to compare against ($base, origin/$base, origin/$branch all absent)"
    fi
    if [ "$orphans" != "0" ]; then
      verdict=unlanded
      add_reason "$orphans commit(s) exist only in this worktree"
    fi
  fi
fi

# A scout's scratch worktree is discardable once its report is safe.
if [ "$kind" = scout ] && [ "$verdict" = unlanded ]; then
  if [ "$harvested" = yes ] || [ -f "$OM_DATA/$id/report.md" ]; then
    verdict=scratch
    reasons=""
    add_reason "scout worktree is scratch; report harvested to data/$id/report.md"
  else
    add_reason "scout has written no .om/report.md — nothing to harvest yet"
  fi
fi

report_verdict() {
  echo "id=$id"
  echo "kind=$kind"
  echo "project=$project"
  echo "branch=${branch:-?}"
  echo "verdict=$verdict"
  echo "report_harvested=$harvested"
  # An `if`, not a `&&` short-circuit: with no reasons to print, a trailing
  # `[ -n "$reasons" ] && …` returns 1, and under `set -e` that aborts the
  # script — so a perfectly clean teardown would report failure.
  if [ -n "$reasons" ]; then
    printf 'reasons:\n%s' "$reasons"
  fi
}

if [ "$mode" = check ]; then
  report_verdict
  exit 0
fi

if [ "$verdict" = unlanded ] && [ "$mode" != force ]; then
  report_verdict
  cat >&2 <<MSG

REFUSED: tearing down $id would destroy the only copy of this work.
This is a finding, not an obstacle. Land it, or bring the captain the
choice to discard it — and only then run with --force.
MSG
  exit 3
fi

# ── Removal ─────────────────────────────────────────────────────────────────
if [ -n "$wt" ] && [ -d "$wt" ] && [ -d "$ppath/.git" ]; then
  # A plain remove is the default and refuses a dirty worktree on its own — a
  # second, independent guard behind the landed-work test. --force is used only
  # where that test already established there is nothing to lose: a harvested
  # scout scratch worktree, or a captain-authorized discard.
  if [ "$verdict" = scratch ] || [ "$mode" = force ]; then
    git -C "$ppath" worktree remove --force "$wt" 2>/dev/null \
      || om_die "worktree remove --force failed for $wt"
  else
    git -C "$ppath" worktree remove "$wt" 2>/dev/null \
      || om_die "worktree remove refused for $wt — git still sees work there"
  fi
fi
if [ -d "$ppath/.git" ]; then git -C "$ppath" worktree prune 2>/dev/null || true; fi

# The branch is kept when it holds commits and was never pushed; deleting it
# would be the same loss the test above just refused.
if [ -n "$branch" ] && [ -d "$ppath/.git" ]; then
  if [ "$verdict" = landed ] || [ "$verdict" = scratch ] || [ "$mode" = force ]; then
    git -C "$ppath" branch -D "$branch" >/dev/null 2>&1 || true
  fi
fi

rm -rf "$OM_STATE/crew/$id"
om_meta_set "$id" state "torn-down"
om_meta_set "$id" torn_down "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
om_meta_set "$id" teardown_verdict "$verdict"
mkdir -p "$OM_STATE/archive"
mv "$OM_STATE/$id.meta" "$OM_STATE/archive/$id.meta"

report_verdict
echo "removed=yes"
