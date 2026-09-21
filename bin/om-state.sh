#!/usr/bin/env bash
# om-state.sh — current fleet state, reconciled from disk and git.
#
#   om-state.sh fleet [--prs]     every live task, one block each
#   om-state.sh task <id> [--prs] one task
#
# Task records say what was *recorded*; this says what is *true right now*.
# Use it before re-escalating anything, and before believing a task is done.
# --prs adds a live forge lookup per task and needs an authenticated `gh`; it
# costs a network round trip each, so it is opt-in.
set -euo pipefail
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"
om_ensure_home

want_prs=no

emit_task() {
  local id="$1"
  local kind project wt branch base state created
  kind="$(om_meta_get "$id" kind || echo '?')"
  project="$(om_meta_get "$id" project || echo '?')"
  wt="$(om_meta_get "$id" worktree || true)"
  branch="$(om_meta_get "$id" branch || echo '?')"
  base="$(om_meta_get "$id" base || echo main)"
  state="$(om_meta_get "$id" state || echo '?')"
  created="$(om_meta_get "$id" created || echo '?')"

  echo "[$id] $kind · $project · $state"
  echo "  branch: $branch (off $base)  created: $created"

  if [ -z "$wt" ] || [ ! -d "$wt" ]; then
    echo "  worktree: GONE (${wt:-unrecorded}) — reconcile before assuming anything"
  else
    local dirty ahead pushed
    if ! dirty="$(om_worktree_dirty_count "$wt")"; then
      # The directory is there and git disowns it. Say so and move on: one
      # broken record must not stop the rest of the fleet from being reported.
      echo "  worktree: BROKEN ($wt) — present on disk, not a git worktree"
      echo "  reconcile this task before acting on it"
      echo
      return 0
    fi
    # Try the local base, then the remote-tracking one. A clone cut while some
    # other branch was checked out has no local `main` at all, so counting
    # against "$base" alone printed '?' for every task in the fleet view —
    # while om-teardown.sh, asking the same question, answered it fine because
    # it falls back to origin/. Two views of one fact should not disagree.
    local base_cmp=""
    for ref in "$base" "origin/$base"; do
      if git -C "$wt" rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
        base_cmp="$ref"; break
      fi
    done
    if [ -n "$base_cmp" ]; then
      ahead="$(git -C "$wt" rev-list --count HEAD "^$base_cmp" 2>/dev/null || echo '?')"
    else
      ahead="? (no ref $base or origin/$base)"
    fi
    if git -C "$wt" rev-parse --verify --quiet "origin/$branch" >/dev/null 2>&1; then
      local unpushed
      unpushed="$(git -C "$wt" rev-list --count HEAD "^origin/$branch" 2>/dev/null || echo '?')"
      pushed="yes ($unpushed unpushed)"
    else
      pushed="no"
    fi
    echo "  worktree: $wt"
    echo "  uncommitted: $dirty  commits ahead of $base: $ahead  pushed: $pushed"
    if [ -f "$wt/.om/report.md" ]; then echo "  report: present in worktree (not yet harvested)"; fi
  fi
  if [ -f "$OM_DATA/$id/report.md" ]; then echo "  report: data/$id/report.md"; fi
  if [ -f "$OM_DATA/$id/brief.md" ]; then echo "  brief: data/$id/brief.md"; fi

  if [ "$want_prs" = yes ] && command -v gh >/dev/null 2>&1 && [ -d "$OM_PROJECTS/$project/.git" ]; then
    local pr
    pr="$(gh pr list --repo "$(git -C "$OM_PROJECTS/$project" remote get-url origin 2>/dev/null)" \
          --head "$branch" --state all --limit 1 \
          --json number,state,isDraft,url,mergeable 2>/dev/null || true)"
    if [ -n "$pr" ] && [ "$pr" != "[]" ]; then echo "  pr: $pr"; fi
  fi
  echo
}

cmd_fleet() {
  local ids; ids="$(om_task_ids)"
  if [ -z "$ids" ]; then
    echo "fleet: empty — no live tasks"
    return 0
  fi
  local id
  for id in $ids; do emit_task "$id"; done
}

sub="${1:-}"; shift || true
for a in "$@"; do [ "$a" = "--prs" ] && want_prs=yes; done

case "$sub" in
  fleet) cmd_fleet ;;
  task)
    tid="${1:-}"
    [ -n "$tid" ] || om_die "usage: om-state.sh task <id>"
    [ -f "$OM_STATE/$tid.meta" ] || om_die "unknown task: $tid"
    emit_task "$tid"
    ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
