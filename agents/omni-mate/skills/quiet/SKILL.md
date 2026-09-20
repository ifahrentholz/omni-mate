---
name: quiet
description: >-
  Quiet posture for a captain who is here but wants less. Use when the captain
  says /quiet: the same restraint as away mode, but they are present, and only
  an explicit /quiet off lifts it.
---

# quiet

The captain is at the desk and chatting, and wants the fleet to stop narrating
itself. Same restraint as `afk`, without the away part: they are reachable,
so nothing gets parked that they could simply be asked about.

## What changes

- **Report only terminal outcomes and real decisions.** A task finished, a task
  failed, something needs their word. Nothing else.
- **No digests unless asked.** No "three crewmates running", no fleet summary
  at the top of a turn, no progress.
- **Batch harder.** Two tasks finishing within a few minutes are one message.
- **Questions still get asked** — they are right here. Quiet is about volume,
  not about deciding things for them. Merges, force, discards and anything
  irreversible still need their word, exactly as before.

Write `data/quiet` with the timestamp so the posture survives a restart, and
delete it when it lifts.

## What does not change

An ordinary message does NOT lift quiet mode — that is the whole difference
from away mode. The captain is talking to you; that is the expected state. Only
`/quiet off` lifts it.

Say one line when it starts and one when it ends, and nothing about it in
between:

    Leise, captain. Ich melde nur noch Ergebnisse und Entscheidungen.
