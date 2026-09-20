# omni-mate

**Talk to one agent. Ship with a crew.**

omni-mate is an [Omnigent](https://omnigent.ai/) agent setup that gives you a
*first mate*: one agent you talk to, which runs a crew of coding agents for
you. It takes a request, decides whether it is work to ship or a question to
scout, writes the brief, cuts a disposable git worktree, spawns a crewmate into
it, supervises the fleet, and brings back finished PRs, approved local merges,
or investigation reports.

You are the captain. You talk to the first mate and to nobody else.

It is a port of [kunchenguid/firstmate](https://github.com/kunchenguid/firstmate)'s
model onto Omnigent — the doctrine, not the plumbing. See
[What came from firstmate](#what-came-from-firstmate-and-what-did-not) for what
that means in practice.

## Why

Running one coding agent is easy. Running three in parallel makes you a
tab-juggler: babysitting sessions, copying context between repos, forgetting
which terminal had the failing test.

omni-mate inverts that. One conversation, one interface, and a crew below deck.

```
            you (the captain)
                  │  requests, decisions, "merge it"
                  ▼
        ┌──────────────────────┐
        │  omni-mate           │  reads projects, writes briefs and records,
        │  the first mate      │  supervises — never changes a project itself
        └──┬────────┬───────┬──┘
           ▼        ▼       ▼
        ┌──────┐ ┌──────┐ ┌──────┐   one crewmate per task, each in its own
        │ t007 │ │ t008 │ │ t009 │   git worktree, ship crewmates visible and
        │ ship │ │ ship │ │scout │   takeover-able in the Subagents panel
        └──┬───┘ └──┬───┘ └──┬───┘
           ▼        ▼        ▼
     PR ──────── PR ──────── report at data/t009/report.md
```

## The five rules it will not break

1. **It never changes a project itself.** Not a typo, not a one-line fix. Every
   project change is a crewmate's job in an isolated worktree.
2. **It never merges without your explicit word.** A project marked `+yolo` is
   the only standing exception.
3. **It never tears down unlanded work.** A refusal to discard is reported to
   you as a finding, not worked around.
4. **Crewmates never talk to you.** Everything reaches you through the first
   mate, in its words.
5. **It reports outcomes faithfully.** Failures come with evidence. It states
   no facts of its own — every number came from a crewmate or a tool.

Rules 1–3 are not only prompt discipline. Crewmates carry Omnigent guardrail
policies that deny writes outside their worktree, the first mate's own
`gh pr merge` hits an approval card before it runs, and the landed-work test
that guards rule 3 lives in a script, not in a model's judgment.

## Install

```bash
git clone git@github.com:ifahrentholz/omni-mate.git
cd omni-mate && ./install.sh
```

Links `bin/omni-mate` into `~/.local/bin`. Elsewhere: `--dir ~/bin`. Undo:
`--uninstall`. Your shell config is not touched.

| requirement | why |
| --- | --- |
| `omnigent` | runs the agent — see [omnigent.ai](https://omnigent.ai/) |
| a Claude provider | `omnigent setup` if none is configured |
| `git` | the crew works in git worktrees |
| `gh`, authenticated | only for `direct-PR` and `no-mistakes` projects |
| `claude` CLI | only for *visible* ship crewmates — see [Crew harness](#crew-harness) |

Then, from anywhere:

```bash
omni-mate
```

**You speak first.** Omnigent has no agent-initiated *first* turn, so the first
mate leads its opening reply with what matters rather than greeting you. (Once
a session is running it can wake itself — that is what away mode is built on.)

## Talk to it

```
> ahoy! nimm mein repo github.com/me/api und fix den flaky login test

  Projekt `api` registriert, direct-PR. Ship-Task `t007`, captain — Crewmate
  ist unter Segel.

  … (minutes later, when the crewmate finishes)

  ✓ t007 flaky-login → PR #42 · CI grün

  - `tests/login.spec.ts:44` — Race auf den Session-Cookie, jetzt awaited
  - Gates: `npm test` → pass · `npm run typecheck` → pass

  Mergen? [ja / erst reviewen / nein]

> ja
```

## Commands

| command | what it does |
| --- | --- |
| `/ahoy` | Pick up where you left off: what changed while you were gone, then open decisions one at a time |
| `/bearings` | Four-section digest of where everything stands. `/bearings file` also writes today's dated report; `include PRs` adds live forge lookups |
| `/afk` | Away posture: records your mandate, keeps the fleet moving inside it, parks everything needing your authority — and **alerts you out of band** when something genuinely cannot wait. See [Being reached while away](#being-reached-while-away) |
| `/quiet` | Same restraint while you stay and chat. Only `/quiet off` lifts it |
| `/stow` | Sweep the session for knowledge that belongs on disk, and say what is safe to forget |

## Being reached while away

`/afk` is not only a digest you collect on return. While you are away the first
mate wakes itself on a slow heartbeat, looks for the things that produce no
event of their own — a wedged crewmate, a PR gone red, an external wait that
never cleared — and reaches you out of band when one of them cannot wait.

**One boundary, and it is a real one: the session has to stay open.** A timer
fires into a live conversation, so leaving the terminal open is what keeps away
mode armed. Ending the session ends the heartbeat with it. (Verified both ways:
a timer fires reliably in a live, idle session; a session closed by a headless
`-p` run takes its timers with it.)

An empty fleet gets no heartbeat at all — nothing can fail quietly when
nothing is running. Work finishing never needs the heartbeat — Omnigent wakes the first mate the
moment a crewmate is done, away or not. The heartbeat exists to notice
*silence*, which is why 15 minutes is plenty and why it only runs while you are
gone.

### Alert channels

Configure `config/alert`, one channel per line:

```
notify                          # macOS Notification Center — this machine only
ntfy https://ntfy.sh/<topic>    # push to your phone; the topic IS the secret
webhook https://…               # POST {"title":…,"message":…}
command <any shell command>     # gets OM_ALERT_TITLE / OM_ALERT_MESSAGE
say                             # speak it aloud
```

With no config file, macOS Notification Center is used when available and
nothing else is attempted — that reaches you *at the machine*, not on your
phone, and `/afk` says so in those words rather than letting you assume more.

**The moment `config/alert` exists, it is the whole list.** The macOS default is
a fallback for having no config, not a line that is always added, so a file
containing only `ntfy …` turns the local notification off. If you want both,
write both:

```
notify
ntfy https://ntfy.sh/<topic>
```

```bash
bin/om-alert.sh --channels   # what is configured
bin/om-alert.sh --test       # prove it works before you rely on it
```

The script exits 0 only when a channel actually accepted the alert, 1 when
every channel failed, and 2 when none is configured. The first mate reads that
code and believes it: an alert it could not deliver is recorded as undelivered,
kept for your return, and never reported as "you were told". Every attempt is
appended to `state/alerts.log`.

## Projects and delivery modes

The first mate clones each project under `projects/` and records how its work
ships:

| mode | what a finished task does |
| --- | --- |
| `direct-PR` | crewmate pushes its branch and opens a PR; you merge (default) |
| `no-mistakes` | the project's no-mistakes pipeline runs first, then as above |
| `local-only` | crewmate commits to its branch and stops; no forge involved |

Any mode may carry `+yolo` — your standing grant to merge without being asked
again, inside the request you already made. It relaxes rule 2 and nothing else.

```bash
bin/om-project.sh add git@github.com:me/api.git --mode no-mistakes
bin/om-project.sh mode api direct-PR+yolo
bin/om-project.sh list
```

## How a task actually works

The one mechanic worth understanding: **a crewmate gets its own worktree
because it gets its own agent config.**

`sys_session_send` cannot set a working directory, and a fixed `tools.agents`
roster would pin every worker to the home's directory — so the whole crew would
share one checkout and collide. Instead `bin/om-task.sh new` cuts a worktree and
renders a per-task config whose `os_env.cwd` *is* that worktree, and the first
mate launches it with `sys_session_create(config_path=…)`. That is what
`spawn: true` in the bundle is for.

```bash
bin/om-task.sh new api ship flaky-login   # worktree + branch + crew config
bin/om-state.sh fleet                      # what is true right now, not what was recorded
bin/om-teardown.sh t007 --check            # would this destroy anything?
bin/om-teardown.sh t007                    # refuses if it would
```

Read each script's header before first use; they own their own contracts.

## Crew harness

Ship crewmates run on `claude-native`: a real Claude Code terminal you can open
in Omnigent's Subagents panel to **watch, or take over** when one wedges. Scouts
run headless on `claude-sdk`, since nobody watches an investigation.

That visibility is not a chat channel — crewmates never talk to you, and you
should not work through them. It exists for two things: seeing that real work is
happening, and rescuing a stuck worker. If you take one over, the first mate
treats that as authoritative and reconciles it.

To run the whole crew headless instead, change one line in
`agents/omni-mate/crew/ship.yaml`:

```yaml
harness: claude-sdk   # was: claude-native
```

## Layout

```
agents/omni-mate/
  config.yaml          the first mate's contract — the heart of the setup
  crew/ship.yaml       ship crewmate TEMPLATE, rendered per task
  crew/scout.yaml      scout crewmate TEMPLATE
  skills/om-*          procedures, loaded at the trigger points config.yaml names
bin/                   the deterministic mechanics; read each header
  om-alert.sh          the only outbound path to a captain who is away
data/                  briefs, reports, backlog, captain preferences   (private)
projects/              clones, read-only to the first mate             (private)
worktrees/             one disposable worktree per live task           (private)
state/                 task records and rendered crew configs          (private)
```

Everything private is gitignored. The repository is a shared template; what a
home accumulates while sailing stays on the machine that sailed it.

Run several isolated homes on one machine with `OM_HOME=~/other-home omni-mate`.

## What came from firstmate, and what did not

firstmate is an agent distro of ~280k lines of shell that builds a crew
infrastructure on top of harnesses that have none: tmux windows as a visible
crew, a bash watcher as a tokenless supervisor, turn-end hooks for twelve
harnesses, status event logs, steering inboxes.

**Omnigent already has most of that**, so porting the plumbing would have been
rebuilding what is underfoot:

| firstmate builds | Omnigent provides |
| --- | --- |
| tmux windows as a visible crew | Subagents panel, `*-native` harnesses, open and take over |
| `fm-watch.sh` zero-token watcher, per-harness turn-end hooks | `async: true` and an inbox wake when a crewmate finishes |
| `.status` event log, crew-state reconciliation | `sys_session_list` / `_get_info` / `_get_history` |
| `fm-send.sh` steering inboxes | `sys_session_send` by `session_id` |
| harness adapters for twelve harnesses | Omnigent's harness layer |

**What was ported is the doctrine**: the captain/first-mate authority model, the
ship-versus-scout split, worktree isolation, delivery modes and merge authority,
the escalation etiquette, and the command surface. Two of firstmate's guarantees
are actually *stronger* here, because Omnigent can enforce at the policy layer
what firstmate can only instruct: a crewmate physically cannot write outside its
worktree, and a merge physically cannot run without an approval card.

**Not ported** (firstmate has them; this does not):

- **Secondmates** — persistent second mates in isolated homes, local or over SSH.
- **Relay** — answering public mentions on X and Discord.
- **Backend choice** — firstmate runs on tmux, Herdr, Zellij, Orca or cmux.
  Here the session backend is Omnigent's.
- **Public relay.** firstmate answers mentions on X and Discord. Omnigent ships
  a Slack socket-mode bot (`omnigent integration slack`) that would serve the
  same purpose better for private work, but omni-mate does not wire it up yet.
- **Whole-home remote second mates.** Omnigent can do it — register both
  machines as hosts on one server — but it needs a server deployment, so it is
  not built here.

## Credit

The model, the vocabulary, and most of the good ideas are
[kunchenguid/firstmate](https://github.com/kunchenguid/firstmate) (MIT). This is
that model rebuilt on Omnigent, not a fork of its code.
