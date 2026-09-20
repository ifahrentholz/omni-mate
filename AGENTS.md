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

There is no test suite. There is a repeatable manual run, and it catches the
things that actually break:

```sh
export OM_HOME=$(mktemp -d)
bash -n bin/*.sh bin/omni-mate install.sh              # syntax

# the bundle and every rendered crewmate must parse, and every policy resolve
python -c "from pathlib import Path; from omnigent.spec.parser import parse; \
           print(parse(Path('agents/omni-mate')).name)"

# then, against a throwaway git repo with an origin:
bin/om-project.sh add <repo> --mode direct-PR
bin/om-task.sh new <proj> ship smoke-test
bin/om-teardown.sh t001 --check      # unlanded  -> refuses
#   commit, push, then:
bin/om-teardown.sh t001              # landed    -> removes, archives meta
```

Use the omnigent tool's own interpreter for the parse check — the repository
has no Python environment of its own.

Verify a policy actually resolves rather than assuming the path is right:

```python
import importlib
mod, _, fn = path.rpartition(".")
getattr(importlib.import_module(mod), fn)(**arguments)   # raises if wrong
```

## Conventions

- **English** for everything in the repository. Chat mirrors the captain's
  language; artifacts do not.
- Prose in skills and scripts explains *why*, not *what*. The what is readable.
- Never add an agent name as a commit co-author.
- Do not document a feature this bundle does not have. The README's "not
  ported" section exists so the gaps stay honest.
