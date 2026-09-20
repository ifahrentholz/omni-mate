---
name: om-supervise
description: >-
  Handle a wake and decide what is real. Use on every wake and whenever judging
  whether work is actually done: owns inbox draining, state reconciliation,
  stuck-crewmate recovery, and what does and does not reach the captain.
user-invocable: false
metadata:
  internal: true
---

# om-supervise

Supervision here costs nothing while nothing is happening. Omnigent wakes you
when a crewmate finishes; there is no watcher to arm, no poll to schedule, and
no reason to look at a running crewmate. **Waiting is silent and free. Looking
is neither.**

## On every wake

1. **Drain once.** `sys_read_inbox` — once per wake. It drains; a second call
   returns the same items and charges you again.
2. **Reconcile before believing.** A crewmate's result says what it *thinks*
   happened. `bin/om-state.sh task <id>` says what is true on disk right now:
   uncommitted files, commits ahead, whether the branch was actually pushed,
   whether a report exists. Run it before you accept a "done", and always
   before re-escalating anything you escalated before.
3. **Act on the reconciled picture**, not the reported one.

The gap between the two is the whole reason this step exists. A crewmate
reporting `result: done` with three uncommitted files has not delivered; a
crewmate reporting `blocked` whose branch is pushed and green may have.

## What each outcome means

| the crewmate says | you do |
| --- | --- |
| `result: done` | Reconcile. If it holds, load `om-deliver`. |
| `result: blocked` with a cause | Decide: re-dispatch fresh with the cause quoted, or bring the captain the decision. Never debug it yourself. |
| nothing readable | Inspect ONCE with `sys_session_get_history`. Then treat as blocked. |
| a question its brief answers | The brief was thin. Steer once with the answer; fix the brief file so the next crewmate does not ask again. |
| a question only the captain can answer | Escalate it, alone, as one decision. |

## Steering a live crewmate

```
sys_session_send(session_id = "<conversation_id>", args = "<what changed>")
```

Steer for one reason: the crewmate lacks a fact it cannot get for itself — a
decision the captain just made, a correction to its scope, an answer to its
question. Do not steer to ask how it is going, and do not steer to encourage
it.

One steer. If it does not land, the crewmate is stuck.

## A stuck crewmate

Stuck means: silent far longer than the work warrants, looping over the same
files, asking the same thing twice, or unreachable.

1. `bin/om-state.sh task <id>` — is there work in the worktree? Something is
   being produced even if nothing is being said.
2. `sys_session_get_history` — once. Read what it is actually doing.
3. Decide, and say which you picked and why:
   - **Steer** — it is confused about something you can state in a sentence.
   - **Close and re-dispatch** — `sys_session_close`, then a fresh crewmate
     into the SAME worktree with the same brief plus a note on what the last
     attempt did. Never provision a second worktree for one task: that splits
     the work across two copies and loses half of it.
   - **Report it** — a ship crewmate is a real terminal, and the captain can
     open it in the Subagents panel and take over. Say so plainly when that is
     the honest next step.

**Never tear down to unstick something.** Hard rule 3. The worktree holds the
only copy of whatever it did get done.

## When the captain has taken over

If the captain typed into a crewmate's terminal, its history will show it.
Treat it as authoritative — it outranks the brief — reconcile the task's state
against what they did, and say in your next message what changed and what it
means for the contract. Do not undo it, and do not re-steer over the top of it.

## What reaches the captain

Almost nothing does, while work is under way.

**Never news:** a crewmate started. A crewmate is still running. A poll came
back empty. Time passed. A retry happened. You are about to do something. The
fleet is unchanged.

**Always news, immediately:**

- A decision only the captain can make.
- A failure, with its evidence.
- Work finished and waiting on them.
- A boot failure — a harness that will not start is a broken machine, not a
  task to retry.
- Anything that would need authority you do not have.

**Batch the rest** into the next message you were going to send anyway. Batching
is a presentation choice and never hides a failure, a decision, or a risk.

## Several crewmates at once

Wakes arrive one at a time. Handle the one that woke you, then check whether
the rest of the fleet changes what you would say — and send ONE message, not
one per crewmate.

If two finish close together, wait for the second before reporting the first
only when the second is seconds away and they are one piece of work in the
captain's mind. Otherwise report what is finished; a captain who has to wait to
hear about done work is being managed, not served.
