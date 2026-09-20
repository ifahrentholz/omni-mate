---
name: om-dispatch
description: >-
  Provision a task and launch its crewmate. Use for every crewmate launch: owns
  the worktree mechanic, the brief template, the sys_session_create call, and
  what to record afterwards. Never hand-roll a spawn.
user-invocable: false
metadata:
  internal: true
---

# om-dispatch

Three steps, in this order, every time. Steps 1 and 3 are mechanical and belong
to scripts; step 2 is the only part that is yours.

## 1. Provision

```sh
bin/om-task.sh new <project> <ship|scout> <slug>
```

The slug is two or three words naming the work, not the agent: `flaky-login`,
not `coder`. The script allocates the id, fetches the project's upstream, cuts
a disposable worktree off a fresh base, renders a per-task crewmate config
whose working directory IS that worktree, and records the binding. It prints
everything you need:

    id=t007
    kind=ship
    project=api
    worktree=/…/worktrees/t007-flaky-login
    branch=om/t007-flaky-login
    base=main
    base_fetched=yes
    mode=direct-PR
    config_path=state/crew/t007
    brief=data/t007/brief.md

`base_fetched=no` means the network was unreachable and the worktree was cut
off a possibly stale base. That belongs in the brief, and it belongs in your
report if the work later looks confused about the state of main.

**Never create a worktree by hand, and never launch a crewmate into a project
clone.** The clone is the fleet's reference copy; two crewmates in it collide,
and hard rule 1 covers you writing there at all.

## 2. Write the brief

Write it to the printed `brief=` path with your own file tool, and send the
same text as the crewmate's first message. Two copies on purpose: the message
is what the crewmate reads, the file is what survives teardown and what you
re-read when the work comes back looking wrong.

The brief is English. It is the whole of what the crewmate knows.

```markdown
# <task id> — <one line naming the work>

**Project** <name> · **Branch** `<branch>` off `<base>` · **Mode** <mode>
**Worktree** <absolute path> — your working directory, and the only place you write.

## Task
<What to build, or what to find out. Concrete enough that two readers would
build the same thing. Name the files you already know are involved.>

## Out of scope
<The nearest adjacent thing, named. This is what stops a crewmate from
"improving" something nobody reviewed.>

## Acceptance
<How you know it is done. Behaviour, not effort. For ship work, the gates that
must be green and the command that proves it.>

## Delivery
<Exactly what to do when the work is green. One of:
 - direct-PR: commit, push `<branch>`, open a PR with gh. Do not merge.
 - no-mistakes: run the project's no-mistakes pipeline first, then as above.
 - local-only: commit to `<branch>` and stop. Do not push.
 Scout: write `.om/report.md` in your worktree. Change nothing that ships.>

## Autonomy
<What is approved, named specifically. Default: nothing outward beyond your own
branch and PR. If the captain approved something particular — an install, a
network call, a credential — write that exact thing here. If they approved
nothing extra, say so: "Nothing beyond the above.">

## Context
<What you already know that saves the crewmate a search: the failing command
and its output, the issue link, what a previous crewmate tried, what
`data/learnings.md` says about this project. Facts only, with sources. No
speculation — a guess in a brief becomes a premise.>
```

Three things a brief must never do: name the captain, tell the crewmate to ask
the captain anything, or describe a project's architecture from memory. The
crewmate reads the code.

## 3. Launch

```
sys_session_create(
  config_path = "state/crew/<id>",
  title       = "<id>-<slug>",
  message     = "<the full brief text>"
)
```

`title` is the task, never the agent — `t007-flaky-login`, not `claude`. The
captain sees it in the Subagents panel, and a ship crewmate can be opened there
and taken over.

Record what comes back:

```sh
bin/om-task.sh show <id>   # then write the conversation_id into state/<id>.meta
```

Write `session=<conversation_id>` and `state=running` into the task's meta with
your file tool. Without the conversation id you cannot steer the crewmate and
cannot read its history, and after a restart you will not know it exists.

## Fanning out

Several independent tasks dispatch in the SAME turn — emit the
`sys_session_create` calls together and they run concurrently. Provision them
all first, then launch them all.

**A fan-out is one step, and it produces one message to the captain**, not one
per crewmate:

    **⚓ 3 Crewmates unter Segel** — `t007` flaky-login · `t008` dark-mode · `t009` scout: CI-Laufzeit

Then end the turn. **That line is the whole message** — nothing follows it.
Not "Meldung, sobald der Bericht da ist", not "ich melde mich", not "sag
Bescheid, wenn du etwas brauchst". A promise to report back is the one sentence
that is always redundant: reporting back is the job, the captain knows it, and
Omnigent wakes you when a crewmate finishes whether you said so or not.

Six at once is the hard ceiling, and it is a policy, not a suggestion. If the
work genuinely needs more, that is a decision for the captain, not a bigger
fan-out.

## After launching

End the turn, and end it on the dispatch line. Do not check on a crewmate you
just started, do not read its
history to see how it is getting on, and do not tell the captain that it is
running. Supervision is `om-supervise`, and it begins when something wakes you.
