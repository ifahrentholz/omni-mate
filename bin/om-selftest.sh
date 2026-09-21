#!/usr/bin/env bash
# om-selftest.sh — the repository's whole test procedure, executed.
#
#   bash bin/om-selftest.sh      run every check; exit 0 only if all passed
#
# There is still no test suite, because there is still almost nothing here that
# a test suite would suit. What there is, is a procedure AGENTS.md used to spell
# out in prose and leave to whoever was reading it. Prose drifts, and a tired
# operator skips the step that mattered — so the procedure lives here instead:
# three phases, every check reported by name, and an exit code that means
# something.
#
#   1. syntax     bash -n over every shell artifact the repository tracks,
#                 discovered rather than listed, so a new script is covered the
#                 day it is added
#   2. bundle     the agent and every rendered crewmate parse, and every policy
#                 they name resolves to a callable — a plausible-looking path
#                 that imports nothing fails here instead of at dispatch
#   3. lifecycle  register a project, cut a task worktree, and prove
#                 bin/om-teardown.sh refuses to destroy work that lives nowhere
#                 else — the one check whose failure loses something real
#
# HERMETIC, and structurally so rather than by promise. om-lib.sh falls back to
# the repository root when OM_HOME is unset, and this repository root doubles as
# a live fleet home: a self-test that inherited that default would register its
# throwaway project and cut its worktrees inside the operator's running fleet.
# So OM_HOME is exported into a fresh temp directory BEFORE om-lib.sh is
# sourced, which points every derived path — data/ state/ projects/ worktrees/ —
# at the temp tree for this process and for every om-*.sh it invokes. The temp
# tree holds the throwaway repositories too, and it is removed on exit,
# including on failure and on interrupt.
#
# Nothing here decides whether work is safe to delete. bin/om-teardown.sh owns
# that judgment and is the only place that may; this script asserts what it
# decides, and never second-guesses it.
set -euo pipefail

# ── The temp root, and its removal ──────────────────────────────────────────
# One variable, set once, removed by a dedicated trap. Cleanup appended to
# ad-hoc command lines is harder to audit and harder for a guardrail to let
# through; this way there is exactly one `rm -rf` in the file and it is guarded.
TMPROOT=""
cleanup() {
  # `|| true`, and it is not sloppiness. set -e is still in force inside an EXIT
  # trap, so a failing rm makes the shell exit with rm's status and overwrite
  # the result the run had already earned: measured, a green 59/59 run reported
  # itself as a failure with rc=9 when rm was forced to fail. Cleanup is
  # housekeeping and must never be able to change the verdict. A temp directory
  # that survives is a mess; a false FAILED is a lie.
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then
    rm -rf "$TMPROOT" 2>/dev/null || {
      printf 'note: could not remove %s — left behind\n' "$TMPROOT" >&2
      true
    }
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

tmp_parent="${TMPDIR:-/tmp}"
TMPROOT="$(mktemp -d "${tmp_parent%/}/om-selftest.XXXXXX")"
export OM_HOME="$TMPROOT/home"
mkdir -p "$OM_HOME"

# Sourced AFTER the override, deliberately: om-lib.sh resolves OM_HOME at source
# time and exports OM_DATA/OM_STATE/… derived from it, so overriding first is
# what makes the isolation structural. It also hands us OM_CODE_ROOT, resolved
# through the install symlink exactly the way every other om-*.sh resolves it,
# and om_die.
# shellcheck source=om-lib.sh
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/om-lib.sh"

case "$OM_HOME" in
  "$TMPROOT"/*) ;;
  *) om_die "refusing to run: OM_HOME resolved to $OM_HOME, outside $TMPROOT" ;;
esac

# ── Reporting ───────────────────────────────────────────────────────────────
# Every helper ends in an `if` or a `case`, never a trailing `[ … ] && …`: that
# form returns 1 when the test is false, and under `set -e` a function ending
# that way aborts its caller. AGENTS.md lists it as an invariant because it has
# bitten this repository before.
checks_passed=0
checks_failed=0
failure_list=""

check_pass() {
  checks_passed=$((checks_passed + 1))
  if [ -n "${2:-}" ]; then
    printf '  PASS  %s  (%s)\n' "$1" "$2"
  else
    printf '  PASS  %s\n' "$1"
  fi
}

check_fail() {
  checks_failed=$((checks_failed + 1))
  failure_list="${failure_list}  - ${1}
      ${2:-}
"
  printf '  FAIL  %s\n        %s\n' "$1" "${2:-}"
}

assert_eq() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    check_pass "$1" "$3"
  else
    check_fail "$1" "expected '$2', got '$3'"
  fi
}

assert_dir() { # <name> <path>
  if [ -d "$2" ]; then
    check_pass "$1" "$2"
  else
    check_fail "$1" "not a directory: $2"
  fi
}

assert_file() { # <name> <path>
  if [ -f "$2" ]; then
    check_pass "$1" "$2"
  else
    check_fail "$1" "not a file: $2"
  fi
}

assert_absent() { # <name> <path>
  if [ ! -e "$2" ]; then
    check_pass "$1" "$2"
  else
    check_fail "$1" "still present: $2"
  fi
}

assert_contains() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) check_pass "$1" "$3" ;;
    *) check_fail "$1" "expected '$3' in: $(printf '%s' "$2" | tr '\n' ' ')" ;;
  esac
}

# ── Running the scripts under test ──────────────────────────────────────────
# A non-zero exit from a script under test is data, not an accident, so it must
# not abort the run. `|| RUN_STATUS=$?` is what keeps `set -e` out of the way,
# and stdout and stderr are kept apart because om-teardown.sh's refusal is on
# stderr while its verdict is on stdout, and the difference is part of what is
# being asserted.
RUN_STATUS=0
RUN_OUT=""
RUN_ERR=""

run_capture() {
  RUN_STATUS=0
  "$@" >"$TMPROOT/.run.out" 2>"$TMPROOT/.run.err" || RUN_STATUS=$?
  RUN_OUT="$(cat "$TMPROOT/.run.out")"
  RUN_ERR="$(cat "$TMPROOT/.run.err")"
}

# Reads one "key=value" line out of a script's reported output. A here-string
# rather than a pipe: `sed … | head -1` makes head exit first, and under
# `pipefail` sed's SIGPIPE would become the value of the whole substitution.
kv() { # <text> <key>
  awk -F= -v k="$2" '$1 == k { sub(/^[^=]*=/, ""); print; exit }' <<<"$1"
}

# The self-test's own commits carry their own identity, passed per invocation
# rather than exported: GIT_AUTHOR_* in the environment would leak into every
# om-*.sh child and quietly rewrite whatever they commit. gpg signing and the
# default branch name are pinned for the same reason — the run must not depend
# on how the operator configured their machine.
scratch_git() {
  git -c user.name='om-selftest' \
      -c user.email='om-selftest@localhost' \
      -c commit.gpgsign=false \
      -c init.defaultBranch=main \
      "$@"
}

# ── The operator's fleet, before and after ──────────────────────────────────
# The hermetic claim is worth asserting rather than promising, because the whole
# failure mode it guards against is silent: a self-test that inherited the real
# OM_HOME would register its throwaway project and cut its worktrees in the
# operator's running fleet, and every check here would still pass. So the shape
# of the code root is fingerprinted before anything runs and compared at the
# end. `git worktree list` is the load-bearing half — it is shared across the
# whole clone, so a worktree cut in the wrong place shows up in it no matter
# which checkout this script was launched from.
fleet_fingerprint() {
  git -C "$OM_CODE_ROOT" worktree list --porcelain 2>/dev/null || true
  local d
  for d in projects worktrees data state config; do
    printf '== %s\n' "$d"
    ls -1A "$OM_CODE_ROOT/$d" 2>/dev/null | sort || true
  done
}

fleet_fingerprint > "$TMPROOT/.fleet-before"

# ── Phase 1: syntax ─────────────────────────────────────────────────────────
# Enumerated through git, not find: this repository root doubles as a live fleet
# home, so a bare `find . -name '*.sh'` would sweep in every shell script of
# every cloned project under projects/ and worktrees/. `ls-files -co
# --exclude-standard` is tracked files plus untracked ones git would keep,
# which is exactly the repository's own artifacts — and it includes this script
# from the moment it exists, so phase 1 covers itself.
has_shell_shebang() {
  local first
  first="$(head -1 "$1" 2>/dev/null || true)"
  case "$first" in
    '#!'*bash*|'#!'*sh|'#!'*sh\ *) return 0 ;;
  esac
  return 1
}

list_shell_artifacts() {
  local f
  # Through a temp file rather than `< <(…)`. Process substitution forks a child
  # that shares this script's own file descriptor, and bash 3.2 — still the
  # system bash on macOS — can lose its place in the script when it does. A
  # plain redirect has no such failure mode, and the -z pairing keeps paths with
  # spaces intact.
  # `|| true` so a git that cannot read this tree reports as "discovered none"
  # below, with a summary line, rather than aborting under `set -e` and leaving
  # the run with no summary at all.
  git -C "$OM_CODE_ROOT" ls-files -z -co --exclude-standard > "$TMPROOT/.tracked" || true
  while IFS= read -r -d '' f; do
    [ -f "$OM_CODE_ROOT/$f" ] || continue
    case "$f" in
      *.sh) printf '%s\n' "$f" ;;
      # An extensionless launcher counts when its shebang says it is a shell
      # script. bin/omni-mate is the one today; the rule is what matters.
      bin/*) if has_shell_shebang "$OM_CODE_ROOT/$f"; then printf '%s\n' "$f"; fi ;;
    esac
  done < "$TMPROOT/.tracked"
}

phase_syntax() {
  echo
  echo "== phase 1: syntax =="
  local f found=0
  list_shell_artifacts > "$TMPROOT/.artifacts"
  while IFS= read -r f; do
    found=$((found + 1))
    run_capture bash -n "$OM_CODE_ROOT/$f"
    if [ "$RUN_STATUS" -eq 0 ]; then
      check_pass "bash -n $f"
    else
      check_fail "bash -n $f" "exit $RUN_STATUS: $(printf '%s' "$RUN_ERR" | tr '\n' ' ')"
    fi
  done < "$TMPROOT/.artifacts"

  if [ "$found" -gt 0 ]; then
    check_pass "shell artifacts discovered" "$found file(s)"
  else
    check_fail "shell artifacts discovered" "git ls-files found none — wrong code root?"
  fi
}

# ── Phase 2: bundle parse and policy resolution ─────────────────────────────
# The repository has no Python environment of its own, so the parse runs on
# omnigent's own interpreter. Its path is derived, never hardcoded: the console
# script on PATH is a symlink into wherever the tool was installed, and its
# shebang names the interpreter outright.
resolve_symlink() {
  local src="$1" dir
  while [ -L "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  printf '%s' "$src"
}

find_omnigent_python() {
  local entry shebang body first last cand cands=""
  entry="$(command -v omnigent 2>/dev/null || true)"
  if [ -n "$entry" ]; then
    entry="$(resolve_symlink "$entry")"
    shebang="$(head -1 "$entry" 2>/dev/null || true)"
    if [ "${shebang#\#!}" != "$shebang" ]; then
      body="${shebang#\#!}"
      first="${body%% *}"
      last="${body##* }"
      # "#!/usr/bin/env python3" names the interpreter in its last word.
      if [ "$(basename "$first")" = env ]; then
        cand="$(command -v "$last" 2>/dev/null || true)"
      else
        cand="$first"
      fi
      if [ -n "$cand" ]; then
        cands="$cands$cand
"
      fi
    fi
    cands="$cands$(dirname "$entry")/python3
$(dirname "$entry")/python
"
  fi
  cands="${cands}python3
python
"
  # Confirmed, not assumed: an interpreter that cannot import omnigent is the
  # wrong one however plausible its path looks.
  while IFS= read -r cand; do
    if [ -n "$cand" ] \
       && command -v "$cand" >/dev/null 2>&1 \
       && "$cand" -c 'import omnigent' >/dev/null 2>&1; then
      printf '%s' "$cand"
      return 0
    fi
  done <<<"$cands"
  return 1
}

# The same five markers bin/om-task.sh substitutes, substituted the same way.
# There is no renderer to import — om-task.sh's sed lives inline in cmd_new —
# so the guard against the two drifting apart is the `{{` check below: a marker
# added to a template but not to om-task.sh surfaces here, not at dispatch.
render_crew_template() { # <template> <id> <worktree> <project> <branch> <gate> <out>
  sed -e "s#{{TASK_ID}}#$2#g" \
      -e "s#{{WORKTREE}}#$3#g" \
      -e "s#{{PROJECT}}#$4#g" \
      -e "s#{{BRANCH}}#$5#g" \
      -e "s#{{GATE_PUSHES}}#$6#g" \
      "$1" > "$7"
}

PYBIN=""

phase_bundle() {
  echo
  echo "== phase 2: bundle parse and policy resolution =="

  PYBIN="$(find_omnigent_python || true)"
  if [ -z "$PYBIN" ]; then
    check_fail "omnigent's interpreter found" \
      "no interpreter on this machine could 'import omnigent'; tried the shebang of \$(command -v omnigent), the python next to it, and plain python3/python. Install omnigent, or put it on PATH."
    return 0
  fi
  check_pass "omnigent's interpreter found" "$PYBIN"

  # Rendered into a temp directory per kind, because Omnigent's spec parser
  # resolves an agent from a DIRECTORY holding config.yaml — the same form
  # om-task.sh writes and sys_session_create is given.
  local crew="$TMPROOT/crew" kind tmpl rendered
  local fake_wt="$TMPROOT/crew-worktree"
  mkdir -p "$crew"
  for tmpl in "$OM_CODE_ROOT"/agents/omni-mate/crew/*.yaml; do
    [ -f "$tmpl" ] || continue
    kind="$(basename "$tmpl" .yaml)"
    mkdir -p "$crew/$kind"
    rendered="$crew/$kind/config.yaml"
    render_crew_template "$tmpl" t000 "$fake_wt" selftest-project om/t000-selftest false "$rendered"
    if grep -q '{{' "$rendered"; then
      check_fail "crew/$kind renders with no placeholder left" \
        "$(grep -o '{{[A-Z_]*}}' "$rendered" | sort -u | tr '\n' ' ') survived — om-task.sh substitutes five markers and this template wants more"
    else
      check_pass "crew/$kind renders with no placeholder left"
    fi
  done

  local before="$checks_failed"
  run_capture "$PYBIN" "$TMPROOT/phase2.py" \
    "$OM_CODE_ROOT/agents/omni-mate" "$crew" "$fake_wt"
  local line outcome name detail
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    outcome="${line%%	*}"
    line="${line#*	}"
    name="${line%%	*}"
    detail="${line#*	}"
    if [ "$outcome" = PASS ]; then
      check_pass "$name" "$detail"
    else
      check_fail "$name" "$detail"
    fi
  done <<<"$RUN_OUT"

  # A crash inside the helper is itself a failure, and it would otherwise show
  # up as silence: no check lines and a summary that still says everything
  # passed.
  if [ "$RUN_STATUS" -ne 0 ] && [ "$checks_failed" -eq "$before" ]; then
    check_fail "phase 2 helper ran" \
      "exit $RUN_STATUS with no check reported: $(printf '%s' "$RUN_ERR" | tr '\n' ' ')"
  fi
}

# ── Phase 3: worktree lifecycle ─────────────────────────────────────────────
# End to end against a throwaway repository with a real origin — a local bare
# repo, so a push is a push and nothing reaches the network.
phase_lifecycle() {
  echo
  echo "== phase 3: worktree lifecycle =="

  local origin="$TMPROOT/origin/demo.git" seed="$TMPROOT/seed"
  mkdir -p "$TMPROOT/origin"
  scratch_git init --bare --quiet "$origin"
  # om-project.sh's default-branch lookup goes through origin/HEAD, so the bare
  # repo's HEAD is named outright rather than inherited from whatever
  # init.defaultBranch the operator happens to have — or does not have.
  scratch_git --git-dir="$origin" symbolic-ref HEAD refs/heads/main

  scratch_git init --quiet "$seed"
  scratch_git -C "$seed" symbolic-ref HEAD refs/heads/main
  printf '# demo\n\nThrowaway project for bin/om-selftest.sh.\n' > "$seed/README.md"
  scratch_git -C "$seed" add -A
  scratch_git -C "$seed" commit --quiet -m 'seed the throwaway project'
  scratch_git -C "$seed" remote add origin "$origin"
  scratch_git -C "$seed" push --quiet origin main

  # The BARE path on purpose: om-project.sh's `[ -d "$src/.git" ]` is false for
  # it, so it takes the plain-clone branch and the clone's origin is this bare
  # repo — a real origin the crewmate can push to.
  run_capture "$OM_CODE_ROOT/bin/om-project.sh" add "$origin" --mode direct-PR
  if [ "$RUN_STATUS" -ne 0 ]; then
    check_fail "om-project.sh add exits 0" \
      "exit $RUN_STATUS: $(printf '%s' "$RUN_ERR" | tr '\n' ' ')"
    return 0
  fi
  check_pass "om-project.sh add exits 0"

  local project
  project="$(kv "$RUN_OUT" project)"
  assert_eq "project registered under its slug" demo "$project"
  assert_eq "clone reports main as its default branch" main "$(kv "$RUN_OUT" default_branch)"
  assert_dir "clone exists in the temp home" "$OM_PROJECTS/$project/.git"
  assert_eq "clone's origin is the throwaway bare repo" "$origin" \
    "$(scratch_git -C "$OM_PROJECTS/$project" remote get-url origin 2>/dev/null || true)"

  run_capture "$OM_CODE_ROOT/bin/om-task.sh" new "$project" ship smoke-test
  if [ "$RUN_STATUS" -ne 0 ]; then
    check_fail "om-task.sh new exits 0" \
      "exit $RUN_STATUS: $(printf '%s' "$RUN_ERR" | tr '\n' ' ')"
    return 0
  fi
  check_pass "om-task.sh new exits 0"

  local id wt branch base base_ref cfgrel
  id="$(kv "$RUN_OUT" id)"
  wt="$(kv "$RUN_OUT" worktree)"
  branch="$(kv "$RUN_OUT" branch)"
  base="$(kv "$RUN_OUT" base)"
  base_ref="$(kv "$RUN_OUT" base_ref)"
  cfgrel="$(kv "$RUN_OUT" config_path)"

  assert_dir "worktree cut" "$wt"
  assert_eq "branch is om/<id>-<slug>" "om/$id-smoke-test" "$branch"
  if scratch_git -C "$OM_PROJECTS/$project" rev-parse --verify --quiet \
       "refs/heads/$branch" >/dev/null 2>&1; then
    check_pass "branch exists in the clone" "$branch"
  else
    check_fail "branch exists in the clone" "no refs/heads/$branch"
  fi

  # AGENTS.md's invariant, and it is worth spelling out twice: `base` is the
  # plain branch name that later comparisons build "origin/<base>" out of;
  # `base_ref` is what the worktree was actually cut from. Recording
  # "origin/main" as base would send every later lookup after
  # "origin/origin/main", which resolves to nothing, quietly.
  assert_eq "base is a plain branch name" main "$base"
  assert_eq "base_ref is the remote-tracking ref" origin/main "$base_ref"
  case "$base" in
    origin/*) check_fail "base never carries an origin/ prefix" "base=$base" ;;
    *) check_pass "base never carries an origin/ prefix" "base=$base" ;;
  esac

  run_capture "$OM_CODE_ROOT/bin/om-task.sh" show "$id"
  assert_eq "recorded base matches the reported base" "$base" "$(kv "$RUN_OUT" base)"
  assert_eq "recorded base_ref matches the reported base_ref" "$base_ref" \
    "$(kv "$RUN_OUT" base_ref)"
  assert_eq "recorded worktree matches the reported worktree" "$wt" \
    "$(kv "$RUN_OUT" worktree)"

  # AGENTS.md's other invariant: config_path is a DIRECTORY holding config.yaml,
  # because that is how Omnigent's spec parser resolves an agent. A bare .yaml
  # path is not the form to rely on.
  assert_eq "config_path is reported relative to the home" "state/crew/$id" "$cfgrel"
  assert_dir "config_path is a directory" "$OM_HOME/$cfgrel"
  assert_file "config_path holds config.yaml" "$OM_HOME/$cfgrel/config.yaml"
  if grep -q '{{' "$OM_HOME/$cfgrel/config.yaml" 2>/dev/null; then
    check_fail "rendered crew config has no placeholder left" \
      "$(grep -o '{{[A-Z_]*}}' "$OM_HOME/$cfgrel/config.yaml" | sort -u | tr '\n' ' ')"
  else
    check_pass "rendered crew config has no placeholder left"
  fi

  # Read off the parsed spec rather than grepped out of the YAML: the worktree
  # isolation is whatever the parser ends up with, not whatever the file looks
  # like it says.
  if [ -n "$PYBIN" ]; then
    run_capture "$PYBIN" -c 'import sys
from pathlib import Path
from omnigent.spec.parser import parse
print(parse(Path(sys.argv[1])).os_env.cwd)' "$OM_HOME/$cfgrel"
    if [ "$RUN_STATUS" -ne 0 ]; then
      check_fail "rendered config's os_env.cwd is the worktree" \
        "parse failed: $(printf '%s' "$RUN_ERR" | tr '\n' ' ')"
    else
      assert_eq "rendered config's os_env.cwd is the worktree" "$wt" "$RUN_OUT"
    fi
  fi

  # ── The check that matters most ───────────────────────────────────────────
  # A commit that exists in this worktree and nowhere else. The two entry points
  # behave differently on purpose, and both halves are asserted: --check reports
  # and returns, the plain teardown is the one that refuses.
  printf 'work that exists nowhere else\n' > "$wt/unlanded.txt"
  scratch_git -C "$wt" add -A
  scratch_git -C "$wt" commit --quiet -m 'unlanded work'

  run_capture "$OM_CODE_ROOT/bin/om-teardown.sh" "$id" --check
  assert_eq "teardown --check on unlanded work exits 0" 0 "$RUN_STATUS"
  assert_contains "teardown --check reports the unlanded verdict" "$RUN_OUT" "verdict=unlanded"
  assert_dir "teardown --check changed nothing" "$wt"

  run_capture "$OM_CODE_ROOT/bin/om-teardown.sh" "$id"
  assert_eq "plain teardown on unlanded work exits 3" 3 "$RUN_STATUS"
  assert_contains "plain teardown refuses on stderr" "$RUN_ERR" "REFUSED"
  assert_dir "refused teardown left the worktree on disk" "$wt"
  assert_file "refused teardown left the task record" "$OM_STATE/$id.meta"

  # Land it, and the same command that just refused must now go through.
  scratch_git -C "$wt" push --quiet origin "$branch"
  run_capture "$OM_CODE_ROOT/bin/om-teardown.sh" "$id"
  assert_eq "teardown after the push exits 0" 0 "$RUN_STATUS"
  assert_contains "teardown reports the landed verdict" "$RUN_OUT" "verdict=landed"
  assert_contains "teardown reports the removal" "$RUN_OUT" "removed=yes"
  assert_absent "worktree removed" "$wt"
  assert_absent "rendered crew config removed" "$OM_STATE/crew/$id"
  assert_absent "live task record gone" "$OM_STATE/$id.meta"
  assert_file "task meta archived" "$OM_STATE/archive/$id.meta"
}

# Phase 3's closing check, kept outside phase_lifecycle so it still runs when
# that phase bailed on a failed prerequisite — a half-finished lifecycle is
# exactly when a stray write is most likely, and least likely to be noticed.
assert_fleet_unmoved() {
  fleet_fingerprint > "$TMPROOT/.fleet-after"
  if cmp -s "$TMPROOT/.fleet-before" "$TMPROOT/.fleet-after"; then
    check_pass "the operator's fleet is unmoved" "worktrees and home directories identical"
  else
    check_fail "the operator's fleet is unmoved" \
      "$(diff "$TMPROOT/.fleet-before" "$TMPROOT/.fleet-after" | tr '\n' ' ')"
  fi
}

# ── The phase 2 helper ──────────────────────────────────────────────────────
# Written out rather than inlined so the shell keeps all the formatting and the
# counting, and this file keeps only what genuinely needs an interpreter. It
# prints one tab-separated record per check: "<PASS|FAIL>\t<name>\t<detail>".
cat > "$TMPROOT/phase2.py" <<'PY'
import importlib
import sys
from pathlib import Path

from omnigent.spec.parser import parse

failures = 0


def emit(outcome, name, detail=""):
    global failures
    if outcome == "FAIL":
        failures += 1
    print("%s\t%s\t%s" % (outcome, name, " ".join(str(detail).split())), flush=True)


def load(label, path, expected_name):
    try:
        spec = parse(Path(path))
    except Exception as exc:
        emit("FAIL", "%s parses" % label, "%s: %s" % (type(exc).__name__, exc))
        return None
    if spec.name != expected_name:
        emit("FAIL", "%s parses" % label,
             "expected name %r, got %r" % (expected_name, spec.name))
        return None
    emit("PASS", "%s parses" % label, "name=%s" % spec.name)
    return spec


def resolve_policies(label, spec):
    # Walked off the PARSED spec, not re-read from the YAML: a policy the parser
    # dropped or renamed has to surface here as a check that never ran, rather
    # than as a file we read ourselves and agreed with.
    guardrails = getattr(spec, "guardrails", None)
    policies = list(getattr(guardrails, "policies", None) or [])
    if not policies:
        emit("FAIL", "%s declares policies" % label, "the parsed spec has none")
        return
    for policy in policies:
        name = "%s policy %s resolves" % (label, policy.name)
        ref = getattr(policy, "function", None)
        if ref is None:
            emit("FAIL", name, "not a function policy; there is nothing to resolve")
            continue
        # AGENTS.md's idiom. Importing is not enough: these are kwargs-only
        # factories, so it is the CALL that catches a misspelled argument as
        # well as a path that points at nothing.
        try:
            mod, _, fn = ref.path.rpartition(".")
            factory = getattr(importlib.import_module(mod), fn)
            factory(**(ref.arguments or {}))
        except Exception as exc:
            emit("FAIL", name, "%s: %s: %s" % (ref.path, type(exc).__name__, exc))
        else:
            emit("PASS", name, ref.path)


bundle_path, crew_root, expected_cwd = sys.argv[1], sys.argv[2], sys.argv[3]

bundle = load("bundle", bundle_path, "omni-mate")
if bundle is not None:
    resolve_policies("bundle", bundle)

kinds = sorted(p.name for p in Path(crew_root).iterdir() if p.is_dir())
if not kinds:
    emit("FAIL", "crew templates rendered", "no rendered crewmate under %s" % crew_root)
for kind in kinds:
    label = "crew/%s" % kind
    spec = load(label, Path(crew_root) / kind, "%s-t000" % kind)
    if spec is None:
        continue
    resolve_policies(label, spec)
    cwd = str(getattr(getattr(spec, "os_env", None), "cwd", None))
    if cwd == expected_cwd:
        emit("PASS", "%s os_env.cwd is the rendered worktree" % label, cwd)
    else:
        emit("FAIL", "%s os_env.cwd is the rendered worktree" % label,
             "expected %s, got %s" % (expected_cwd, cwd))

sys.exit(1 if failures else 0)
PY

# ── Run ─────────────────────────────────────────────────────────────────────
echo "omni-mate self-test"
echo "  code root: $OM_CODE_ROOT"
echo "  temp home: $OM_HOME  (removed on exit)"

phase_syntax
phase_bundle
phase_lifecycle
assert_fleet_unmoved

echo
echo "== summary =="
if [ "$checks_failed" -ne 0 ]; then
  printf '%s' "$failure_list"
fi
printf '  %d passed, %d failed\n' "$checks_passed" "$checks_failed"
if [ "$checks_failed" -ne 0 ]; then
  echo "  FAILED"
  exit 1
fi
echo "  OK"
