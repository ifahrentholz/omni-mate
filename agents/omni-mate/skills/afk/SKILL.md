---
name: afk
description: >-
  Away posture with an active alarm. Use when the captain says /afk, says they
  are stepping away, or when data/afk-contract.md exists: records the mandate,
  keeps the fleet moving inside it, wakes itself on a heartbeat, and alerts the
  captain out of band when something genuinely cannot wait.
---

# afk

The captain is leaving the desk. The fleet keeps sailing, nothing that needs
their authority happens without them — and if something goes wrong that cannot
wait for their return, they hear about it.

## How reaching them actually works

Two mechanisms, and it is worth knowing which is which.

- **You are woken by the inbox whenever a crewmate finishes.** That needs no
  timer and costs nothing. Work completing is never something you have to go
  looking for.
- **Silence is what a heartbeat is for.** A wedged crewmate, a PR that went red
  an hour ago, an external wait that never cleared — none of these produce an
  inbox wake, and while the captain is away nobody notices them. So away mode,
  and only away mode, sets a slow repeating timer to look.

Waking yourself is not reaching the captain. The alert channel is
`bin/om-alert.sh`, and it is the only outbound path there is.

## 1. Before they go: prove you can reach them

```sh
bin/om-alert.sh --channels
```

**Do this first, and tell them the truth about the answer.** A promise to alert
that cannot be delivered is worse than no promise, because they will plan their
absence around it.

- **Channels configured** → say which, and offer a live test
  (`bin/om-alert.sh --test`) if they have not used it this session.
- **Nothing configured** → say so plainly in the same line you accept the away
  posture. Do not soften it:

      Ich kann dich unterwegs nicht erreichen, captain — kein Alarmkanal
      konfiguriert. Ich halte alles für deine Rückkehr bereit. Kanal jetzt
      einrichten? [so lassen / ntfy einrichten]

  On a mac with nothing configured, Notification Center is the automatic
  fallback: it reaches them at this machine, and nowhere else. Say that
  distinction — "I can reach you here, not on your phone" — rather than
  reporting a channel and letting them assume more.

## 2. Record the contract

Read back what you understood in one line and get a yes:

    Verstanden, captain: ~2h weg, `t007` und `t009` laufen weiter, ich merge
    nichts, und ich alarmiere per ntfy, wenn etwas blockiert. [passt / ändern]

On confirmation write `data/afk-contract.md`:

```markdown
# Away contract — <ISO timestamp>

**Captain's words** <verbatim — what they actually said, not your paraphrase>
**Expected back** <what they said, or "unstated">
**Mandate** <what may proceed without them, named specifically>
**Parked** <what must wait: merges, anything outward, anything destructive>
**Reach** <the channels om-alert.sh reported, or "none — holding everything">
**Heartbeat** <the timer_id, or "not armed" and the condition that would arm it>
```

Verbatim matters. On their return the contract is what you both check the
window against, and a paraphrase quietly widens the mandate.

## 3. Arm the heartbeat — but only if there is silence to watch

**An empty fleet gets no heartbeat.** Nothing is running, so nothing can fail
quietly, and a timer would wake you every fifteen minutes to confirm that
nothing is still nothing. Say so in the contract, name the condition that would
change it ("arm on first dispatch"), and move on.

With work under way:

```
sys_timer_set(seconds = 900, repeat = true, note = "afk-heartbeat")
```

900s unless `config/afk-heartbeat` says otherwise. Record the returned
`timer_id` in the contract file — you need it to cancel, and after a restart it
is the only way to know a heartbeat is already armed. Never arm a second one.

Shorter is not better. Each firing costs a turn whether or not anything
happened, and completed work already arrives on its own. The heartbeat exists
to notice silence, and silence does not need checking every minute.

## 4. On each heartbeat firing

One shell call, then decide:

```sh
bin/om-state.sh fleet
```

**Alert-worthy — reach out:**

- Everything is blocked behind one decision only the captain can make.
- A crewmate failed, or wedged with no progress across two heartbeats.
- Work finished and the mandate does not cover delivering it, so it is sitting
  there going stale.
- A boot failure: a harness that will not start.

**Not alert-worthy — note it and stay quiet:**

- Progress of any kind. A crewmate finishing cleanly inside the mandate.
- A fleet that is simply still working.
- Anything you already alerted about. **Never alert twice for the same thing** —
  record what you sent in `state/.afk-alerted` (one line per task and reason)
  and check it before sending.

To alert:

```sh
bin/om-alert.sh "t007 blockiert" "Merge-Entscheidung nötig, alles andere wartet"
```

**Read its exit code and believe it.** `delivered=0` means the captain has NOT
been told, whatever the channel claimed. Record the failed attempt, keep the
item in the return digest, and try the next heartbeat — an alert channel that
is down while they are away is itself a fact they need on their return.

If nothing crosses the line, **end the turn silently.** A heartbeat that found
nothing produces no message at all.

## 5. Append to the return digest as you go

Keep a `## While you were away` section in `data/afk-contract.md`, written when
things happen rather than reconstructed at the end. A compaction or a restart
in between would otherwise lose it. Record what you alerted about and whether
it was delivered.

## 6. On return

Any ordinary message means they are back — treat it that way even if it is
about something else.

1. **Cancel the heartbeat**: `sys_timer_cancel(timer_id)`. A timer left running
   burns a turn every fifteen minutes forever.
2. **Deliver the digest first**, before answering what they asked:

       **Zurück, captain.** In den 2h: `t007` ist durch (PR #42, CI grün),
       `t009` hat seinen Report. Geparkt: der Merge von #42.
       Ich habe dich um 14:20 per ntfy erreicht — die Notification hier am
       Rechner ist fehlgeschlagen.

3. **Archive** the contract to `data/afk-contracts/<entry-time>.md` and clear
   `state/.afk-alerted`. An unarchived contract means you are still treating
   them as away, and so will the next session.

A message beginning `/afk` refreshes the window rather than ending it. Anything
else ends it. Bias ambiguous input toward ending: a present captain takes
precedence.

## What away mode never does

It never widens approval authority. Merges, force, discards, anything outward,
irreversible or security-sensitive wait for the captain — being unreachable is
not consent, and an alert is not an answer.
