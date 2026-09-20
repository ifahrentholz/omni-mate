---
name: bearings
description: >-
  Where everything stands, in four sections. Use when the captain says
  /bearings, asks for status, or opens a session with nothing substantive while
  tasks are live. "/bearings file" also writes today's dated report.
---

# bearings

A digest the captain can read in fifteen seconds and act on. It is built from
bounded state, not from memory of this conversation.

## Gather, in one shell call

```sh
bin/om-state.sh fleet; bin/om-project.sh list; tail -20 data/backlog.md 2>/dev/null
```

Add `--prs` to the fleet call only when the captain asked for PR detail or a
task's delivery hangs on it — each one is a network round trip.

## The four sections

Omit any section that would be empty. Never write "none" under a heading.

```
**Unter Segel** — <n> Crewmates
- `t007` flaky-login · api · seit 20 min · 3 Commits, noch nicht gepusht
- `t009` scout: CI-Laufzeit · api · Report liegt

**Wartet auf dich**
- `t005` PR #42 offen, CI grün — mergen?
- `t008` Teardown verweigert, 2 Commits nur lokal

**Gelandet seit zuletzt**
- `t004` dark-mode → PR #41 gemerged

**Stockt**
- `t006` seit 40 min still, letzte Aktivität in `auth/`
```

Rules that make it useful:

- **"Wartet auf dich" is the point of the whole digest.** It goes second so it
  is above the fold, and every line in it is a decision the captain can make in
  one word. If that section is empty, say so in the opening line and keep the
  digest short.
- At most four items per section. Beyond that, keep the blocking ones and end
  with `- +N weitere`.
- Every claim comes from the gathered state. You measured nothing.
- Never report an unchanged fleet as progress. If nothing moved since the last
  digest, say that in one line instead of repeating it.

End with a single question only if something is actually waiting. A digest that
ends with "was möchtest du tun?" when nothing is blocked is noise.

## `/bearings file`

Also write `data/status-report-<YYYY-MM-DD>.md`, replacing today's from
scratch rather than appending, and link it from the chat digest. The file may
be longer than the digest and may carry the detail the digest dropped.

## `/bearings include PRs`

Opt into the live forge lookup (`bin/om-state.sh fleet --prs`) for every task
with a branch. Slower, and worth it before a merge round.
