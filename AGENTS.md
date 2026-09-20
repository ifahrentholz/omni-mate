# Working on omni-mate

This file is for an agent changing **omni-mate itself**. If you are the first
mate running a fleet, your contract is `agents/omni-mate/config.yaml` and the
`om-*` skills — not this file.

## What this repository is

An Omnigent agent bundle plus the deterministic scripts it drives. It is a
template a single operator clones, owns, and customises. There is nothing to
build and nothing to install beyond a symlink.

## Where the pieces live, and who owns what

| file | owns |
| --- | --- |
| `agents/omni-mate/config.yaml` | the first mate's whole contract: identity, the five hard rules, turn discipline, reporting style, the skill index |
| `agents/omni-mate/skills/om-*` | one procedure each, loaded at a trigger `config.yaml` names |
| `agents/omni-mate/crew/*.yaml` | crewmate TEMPLATES with `{{PLACEHOLDER}}` markers, rendered per task |
| `bin/om-*.sh` | every mechanic that can be exact; each script's header is its contract |
| `bin/om-alert.sh` | the only outbound path to an away captain, and the honesty contract about whether a message actually landed |
| `bin/omni-mate` | the launcher, and the only place that decides the session's working directory |

The dividing line, and it is the one rule worth defending here: **scripts own
the mechanics, agents own the judgment.** Anything that can be computed exactly
and repeatably belongs in `bin/`. Anything requiring understanding belongs in a
prompt or a skill. A script must never adjudicate meaning; intelligence must
never be spent on what a script does exactly.

## Invariants that are easy to break

- **A crewmate's worktree comes from its rendered config's `os_env.cwd`.**
  `sys_session_send` cannot set a working directory. Any change that moves
  crewmate launching from `sys_session_create(config_path=…)` to a declared
  `tools.agents` roster silently puts the whole crew in one checkout.
- **`config_path` must be a directory containing `config.yaml`.** Omnigent's
  spec parser resolves an agent that way; a bare `.yaml` path is not the form
  to rely on.
- **`base` is a branch name, `base_ref` is what the worktree is cut from.**
  Recording `origin/main` as `base` makes every later comparison look for
  `origin/origin/main` and quietly find nothing.
- **A trailing `[ test ] && command` as a function's last statement returns 1**,
  and under `set -euo pipefail` that aborts the caller. Use an `if` block for
  anything at the end of a function.
- **The landed-work test lives in `bin/om-teardown.sh` and nowhere else.** Do
  not add a second opinion about what "safe to delete" means.
- **A timer lives in the runner, bound to a live session.** Measured, both
  directions: `sys_timer_set` fires reliably into a live idle session — nobody
  typing, the agent still wakes and acts — and a session closed by a headless
  `-p` run takes its pending timers with it, firing nothing. Away mode is built
  on the first fact and bounded by the second, so a change that ends the
  session to "save resources" while away silently disarms the alarm.
- **`om-alert.sh`'s exit code is a contract, not a status line.** 0 means a
  channel accepted it, 1 means nobody was told, 2 means nothing is configured.
  Anything that treats a send as success without reading it will have the first
  mate reporting that the captain was alerted when they were not — which is
  hard rule 5 broken by a script.
- **Prefix agent-loaded skills `om-`; leave captain-typed ones bare.**
  `skills: all` lets the host's own skills through, and the Skill tool resolves
  an exact name before a plugin-qualified one — an unprefixed `dispatch` in
  some project would shadow the one the first mate asks for, silently. The five
  user-invocable skills are the exception: Omnigent's REPL registers each as
  `/<name>`, so prefixing them would make the command `/om-afk`. Before adding
  a sixth, check it against the REPL's built-ins (`COMMANDS` in
  `omnigent/repl/_repl.py`) — a built-in wins and the skill is skipped with
  only a log line.

## Changing the contract

`agents/omni-mate/config.yaml`'s prompt is always loaded, so it is a budget.
Keep it under ~2,000 words; anything longer belongs behind a skill trigger. A
change that would push it over prunes or moves something first.

Detail goes in a skill. The prompt says *when* to load it, the skill says *how*.

## Testing a change

There is no test suite. There is one script, and it runs the whole procedure:

```sh
bash bin/om-selftest.sh
```

It takes no arguments, asks nothing, and exits 0 only when every check passed;
otherwise the summary names which ones failed and what they saw. Three phases:

1. **Syntax** — `bash -n` over every shell artifact the repository carries,
   discovered rather than listed, so a script added tomorrow is covered today.
2. **Bundle** — the agent spec and every crewmate template parse (the templates
   are rendered first; raw `{{PLACEHOLDER}}` markers are not valid YAML), and
   every policy the *parsed* specs name is imported and called, because a path
   that merely looks plausible is not a path that resolves.
3. **Lifecycle** — `om-project.sh add` → `om-task.sh new` → `om-teardown.sh`
   end to end against a throwaway repo with a real origin, asserting the
   invariants above: `base` is a plain branch name and never `origin/<branch>`,
   `config_path` is a directory holding `config.yaml`, and the rendered
   `os_env.cwd` is the worktree that was cut.

   Teardown's two entry points behave differently on purpose, and the script
   asserts both halves — an earlier version of this section claimed `--check`
   refuses, and it does not:

   | invocation | on unlanded work |
   | --- | --- |
   | `om-teardown.sh <id> --check` | reports `verdict=unlanded` on stdout, exits **0**, changes nothing |
   | `om-teardown.sh <id>` | exits **3** with a `REFUSED:` block on stderr, worktree left intact |

   Push the branch, and that same plain invocation removes the worktree and
   archives the task meta.

The run is hermetic. It exports an `OM_HOME` of its own into a temp directory,
keeps every throwaway repo there, and removes the lot on exit — including on
failure and on interrupt. That is not tidiness: `bin/om-lib.sh` falls back to
the code root when `OM_HOME` is unset, so a self-test that inherited the
environment would register its fake project and cut its worktrees inside the
live fleet. The run's closing check fingerprints the code root before the
first phase and again after the last, so a stray write into the operator's
own fleet fails the run instead of passing unnoticed.

Phase 2 runs on omnigent's own interpreter — the repository has no Python
environment of its own. The path is derived at runtime, never hardcoded: resolve
`command -v omnigent` through its symlinks, read the interpreter out of its
shebang, and fall back to the `python` beside it. Each candidate has to actually
`import omnigent` before it is used, so a plausible-looking interpreter that
cannot see the package is rejected rather than trusted. If none can, phase 2
fails loudly and names what is missing rather than skipping.

What the script does not cover, and still needs a human:

- Anything about a **live session**: that `sys_timer_set` fires into an idle
  session, that a crewmate launched with `sys_session_create(config_path=…)`
  really lands in its own worktree, that away mode alerts reach a channel.
  These need a running agent and a real forge or messenger; the script asserts
  the *configuration* that makes them possible, not the behaviour.
- `bin/om-alert.sh`'s exit codes against a channel that is actually configured.
- Whether a prompt change is an improvement. No script adjudicates meaning.

## Conventions

- **English** for everything in the repository. Chat mirrors the captain's
  language; artifacts do not.
- Prose in skills and scripts explains *why*, not *what*. The what is readable.
- Never add an agent name as a commit co-author.
- Do not document a feature this bundle does not have. The README's "not
  ported" section exists so the gaps stay honest.
