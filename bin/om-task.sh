#!/usr/bin/env bash
# om-task.sh — task allocation and crewmate provisioning.
#
#   om-task.sh new <project> <ship|scout> <slug>   allocate id, worktree, crew config
#   om-task.sh list                                 one row per live task
#   om-task.sh show <id>                            the task's full record
#
# `new` is the only way a crewmate comes into existence, and it is deliberately
# deterministic: it allocates the id, cuts a disposable worktree off a fresh
# base, renders a per-task agent config whose cwd IS that worktree, and records
# the binding. The first mate then writes the brief and launches the crewmate
# with sys_session_create(config_path=...). Nothing here decides anything —
# every judgment (is this ship or scout? what goes in the brief?) stays with
# the agent, and every mechanic stays here.
#
# The rendered config is what buys worktree isolation: sys_session_send cannot
# set a working directory, so a crewmate that must live in its own worktree has
# to be launched from a config that names it. That is the whole trick.
set -euo pipefail
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"
om_ensure_home

cmd_new() {
  local project="${1:-}" kind="${2:-}" slug_in="${3:-}"
  [ -n "$project" ] && [ -n "$kind" ] && [ -n "$slug_in" ] \
    || om_die "usage: om-task.sh new <project> <ship|scout> <slug>"
  case "$kind" in ship|scout) ;; *) om_die "kind must be ship or scout, got: $kind" ;; esac

  local ppath="$OM_PROJECTS/$project"
  [ -d "$ppath/.git" ] || om_die "unknown project: $project (register it with om-project.sh add)"

  local slug id wt branch base base_ref
  slug="$(om_slug "$slug_in")"
  [ -n "$slug" ] || om_die "slug reduced to nothing: $slug_in"
  id="$(om_next_id)"
  wt="$OM_WORKTREES/$id-$slug"
  branch="om/$id-$slug"

  # A crewmate starts from current upstream, not from whatever this clone last
  # saw. A fetch that cannot reach the network is not fatal: the worktree is
  # still cut, and the brief says which base it got.
  local fetched=no
  if git -C "$ppath" fetch --quiet origin 2>/dev/null; then fetched=yes; fi
  # Two names for one thing, and they are not interchangeable. `base` is the
  # plain branch name ("main") — that is what gets recorded, and what later
  # comparisons build "origin/<base>" out of. `base_ref` is what the worktree
  # is actually cut from: the remote-tracking ref when there is one, so a
  # crewmate starts from current upstream rather than from whatever this clone
  # last checked out. Recording "origin/main" as the base would make every
  # later lookup ask for "origin/origin/main" and quietly find nothing.
  local base_ref
  base_ref="$(git -C "$ppath" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$base_ref" ]; then
    base="${base_ref#origin/}"
  else
    base="$(git -C "$ppath" rev-parse --abbrev-ref HEAD)"
    base_ref="$base"
  fi
  git -C "$ppath" rev-parse --verify --quiet "$base_ref" >/dev/null \
    || om_die "base ref does not resolve: $base_ref"

  git -C "$ppath" worktree add --quiet -b "$branch" "$wt" "$base_ref" \
    || om_die "worktree add failed for $id ($branch off $base_ref)"

  mkdir -p "$OM_DATA/$id"

  # The delivery mode decides whether this crewmate may push its own branch.
  # local-only projects gate every outward command; the rest expect a task
  # branch and a PR, which is the crewmate's finish line, not a merge.
  local mode gate_pushes
  mode="$("$OM_CODE_ROOT/bin/om-project.sh" mode "$project" 2>/dev/null || echo direct-PR)"
  [ -n "$mode" ] || mode="direct-PR"
  case "${mode%+yolo}" in
    local-only) gate_pushes=true ;;
    *) gate_pushes=false ;;
  esac

  local tmpl="$OM_CODE_ROOT/agents/omni-mate/crew/$kind.yaml"
  [ -f "$tmpl" ] || om_die "missing crew template: $tmpl"
  # A DIRECTORY holding config.yaml, not a bare file. Omnigent's spec parser
  # resolves an agent by looking for config.yaml inside the path it is given,
  # so `state/crew/<id>/config.yaml` is the form sys_session_create accepts
  # without ambiguity.
  mkdir -p "$OM_STATE/crew/$id"
  local out="$OM_STATE/crew/$id/config.yaml"
  sed -e "s#{{TASK_ID}}#$id#g" \
      -e "s#{{WORKTREE}}#$wt#g" \
      -e "s#{{PROJECT}}#$project#g" \
      -e "s#{{BRANCH}}#$branch#g" \
      -e "s#{{GATE_PUSHES}}#$gate_pushes#g" \
      "$tmpl" > "$out"

  om_meta_set "$id" id "$id"
  om_meta_set "$id" kind "$kind"
  om_meta_set "$id" project "$project"
  om_meta_set "$id" slug "$slug"
  om_meta_set "$id" branch "$branch"
  om_meta_set "$id" base "$base"
  om_meta_set "$id" base_ref "$base_ref"
  om_meta_set "$id" base_fetched "$fetched"
  om_meta_set "$id" worktree "$wt"
  om_meta_set "$id" config "$out"
  om_meta_set "$id" mode "$mode"
  om_meta_set "$id" state provisioned
  om_meta_set "$id" created "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Relative config path: sys_session_create resolves config_path against the
  # session's working directory, which is the home.
  echo "id=$id"
  echo "kind=$kind"
  echo "project=$project"
  echo "worktree=$wt"
  echo "branch=$branch"
  echo "base=$base"
  echo "base_ref=$base_ref"
  echo "base_fetched=$fetched"
  echo "mode=$mode"
  echo "config_path=state/crew/$id"
  echo "brief=data/$id/brief.md"
}

cmd_list() {
  local id
  for id in $(om_task_ids); do
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "$id" \
      "$(om_meta_get "$id" kind || echo '-')" \
      "$(om_meta_get "$id" project || echo '-')" \
      "$(om_meta_get "$id" state || echo '-')" \
      "$(om_meta_get "$id" branch || echo '-')"
  done
}

cmd_show() {
  local id="${1:-}"
  [ -n "$id" ] || om_die "usage: om-task.sh show <id>"
  [ -f "$OM_STATE/$id.meta" ] || om_die "unknown task: $id"
  cat "$OM_STATE/$id.meta"
}

case "${1:-}" in
  new) shift; cmd_new "$@" ;;
  list) shift; cmd_list "$@" ;;
  show) shift; cmd_show "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
