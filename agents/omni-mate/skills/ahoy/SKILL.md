---
name: ahoy
description: >-
  Pick up where you left off. Use when the captain says /ahoy, returns after
  being away, or starts a session cold: recaps what happened while they were
  gone, then walks them through open decisions one at a time.
---

# ahoy

The captain has been away — for ten minutes or two days — and wants back in
without reading a transcript.

## 1. If this is the session's first real message

There is nothing to recap: a new session has no "since last time" it can see.
Run `bearings` instead and say nothing about having fallen back.

## 2. Otherwise: what happened since they last spoke

Gather the same bounded state `bearings` uses, plus anything the fleet did
in this conversation since the captain's last real message. Report it as
outcomes, in at most five lines. Not a timeline — a state change:

    **Seit vorhin, captain:** `t007` ist durch (PR #42, CI grün), `t009` hat
    seinen Report, `t006` steht seit 40 Minuten still.

An away contract at `data/afk-contract.md` means they went away deliberately.
Deliver the return digest it accumulated, then archive the contract to
`data/afk-contracts/<entry-time>.md` and say the away posture is lifted.

## 3. Then: the decisions, one at a time

Collect everything visibly waiting on the captain — open PRs, refused
teardowns, parked scout findings, questions a crewmate raised that you could
not answer. Order them by what it costs to get them wrong, heaviest first.
Then ask about **one**.

    **1 von 3** — `t005` PR #42, CI grün, 40 Zeilen in `auth/`.

    **Mergen?** [ja / erst reviewen / später]

After each answer: act on it in the same turn, then ask the next one. Do not
list all three up front — a captain who is handed three decisions answers the
easy one and forgets the other two.

Stop the walk the moment they ask for something else. A live request outranks
your queue, and the rest of the decisions are still there afterwards.

## 4. When nothing is waiting

Say so in one line and ask what is next. Do not manufacture a digest to fill
the silence.

    Alles ruhig, captain — nichts wartet auf dich. Was steht an?
