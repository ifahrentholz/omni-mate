#!/usr/bin/env bash
# om-project.sh — the fleet's project registry.
#
#   om-project.sh add <url-or-path> [--mode <mode>]   clone or adopt a project
#   om-project.sh list                                 registry, one row per project
#   om-project.sh mode <project> [<mode>]              read or set the delivery mode
#   om-project.sh path <project>                       absolute path to the clone
#
# Delivery modes decide how a crewmate's finished work reaches main:
#   no-mistakes  validate through the project's no-mistakes pipeline, then PR
#   direct-PR    push the branch and open a PR (the default)
#   local-only   merge locally, never push; for projects with no forge
# Any mode may carry "+yolo", the captain's standing grant to merge without
# asking again. Without it, merging waits for the captain's explicit word.
#
# The registry is data/projects.md — readable by the captain, parsed here.
set -euo pipefail
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"
om_ensure_home

REGISTRY="$OM_DATA/projects.md"

registry_init() {
  [ -f "$REGISTRY" ] && return 0
  cat > "$REGISTRY" <<'HDR'
# Projects

Fleet navigation registry. One row per project: where it lives and how its work
ships. Maintained by `bin/om-project.sh`; safe for the captain to read and edit.

| project | mode | origin |
| --- | --- | --- |
HDR
}

valid_mode() {
  case "${1%+yolo}" in
    no-mistakes|direct-PR|local-only) return 0 ;;
    *) return 1 ;;
  esac
}

cmd_add() {
  local src="${1:-}"; shift || true
  local mode="direct-PR"
  while [ $# -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      *) om_die "unknown argument: $1" ;;
    esac
  done
  [ -n "$src" ] || om_die "usage: om-project.sh add <url-or-path> [--mode <mode>]"
  valid_mode "$mode" || om_die "invalid mode: $mode (no-mistakes | direct-PR | local-only, each optionally +yolo)"

  local name dest
  name="$(om_slug "$(basename "${src%.git}")")"
  dest="$OM_PROJECTS/$name"

  if [ -d "$dest" ]; then
    echo "already registered: $name -> $dest"
  elif [ -d "$src/.git" ]; then
    # Adopting a checkout the captain already has. A symlink would make the
    # worktree paths ambiguous, so clone from it instead and keep its origin.
    git clone --origin origin "$src" "$dest" >/dev/null 2>&1 || om_die "clone from $src failed"
    local up; up="$(git -C "$src" remote get-url origin 2>/dev/null || true)"
    [ -n "$up" ] && git -C "$dest" remote set-url origin "$up"
  else
    git clone "$src" "$dest" >/dev/null 2>&1 || om_die "clone of $src failed"
  fi

  registry_init
  local origin; origin="$(git -C "$dest" remote get-url origin 2>/dev/null || echo "-")"
  if ! grep -q "^| $name |" "$REGISTRY" 2>/dev/null; then
    printf '| %s | %s | %s |\n' "$name" "$mode" "$origin" >> "$REGISTRY"
  fi
  echo "project=$name"
  echo "path=$dest"
  echo "mode=$mode"
  echo "default_branch=$(cmd_default_branch "$name")"
}

cmd_list() {
  registry_init
  cat "$REGISTRY"
}

cmd_mode() {
  local name="${1:-}" mode="${2:-}"
  [ -n "$name" ] || om_die "usage: om-project.sh mode <project> [<mode>]"
  registry_init
  if [ -z "$mode" ]; then
    grep "^| $name |" "$REGISTRY" | awk -F'|' '{gsub(/ /,"",$3); print $3}'
    return 0
  fi
  valid_mode "$mode" || om_die "invalid mode: $mode"
  grep -q "^| $name |" "$REGISTRY" || om_die "unknown project: $name"
  local tmp; tmp="$(mktemp)"
  awk -F'|' -v n=" $name " -v m=" $mode " 'BEGIN{OFS="|"} $2==n {$3=m} {print}' "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  echo "$name mode=$mode"
}

cmd_path() {
  local name="${1:-}"
  [ -n "$name" ] || om_die "usage: om-project.sh path <project>"
  [ -d "$OM_PROJECTS/$name" ] || om_die "unknown project: $name"
  echo "$OM_PROJECTS/$name"
}

cmd_default_branch() {
  local name="${1:-}" dest="$OM_PROJECTS/${1:-}"
  [ -d "$dest" ] || om_die "unknown project: $name"
  # origin/HEAD when the clone recorded one, else whatever HEAD points at.
  git -C "$dest" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's#^origin/##' \
    || git -C "$dest" rev-parse --abbrev-ref HEAD
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  list) shift; cmd_list "$@" ;;
  mode) shift; cmd_mode "$@" ;;
  path) shift; cmd_path "$@" ;;
  default-branch) shift; cmd_default_branch "$@" ;;
  *) sed -n '2,20p' "$0"; exit 1 ;;
esac
