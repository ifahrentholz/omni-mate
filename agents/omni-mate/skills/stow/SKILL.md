---
name: stow
description: >-
  Get durable knowledge out of the session and onto disk. Use when the captain
  says /stow, when a session is ending with facts in it that nowhere records,
  or before a long conversation gets compacted.
---

# stow

A conversation is not storage. Anything that will still be true next week
belongs in a file, and this is the sweep that puts it there.

## Sweep for four kinds of thing

Read back over the session and ask, for each:

1. **Captain preferences** → `data/captain.md`
   How they want to be worked with. "Never merge before I've read the diff."
   "German in chat, English in the repo." "Don't ask about small stuff on
   `radar`." Preferences, not one-off instructions.

2. **Operational facts about this home** → `data/learnings.md`
   What went wrong here and what turned out to be true. "`api`'s test suite
   needs `pnpm`, not `npm`." "CI on `web` fails the first run after a
   dependency bump; re-run once before reporting it." Dated, with the evidence
   that established it.

3. **Open work records** → `data/backlog.md`
   Work that was agreed but not dispatched, work that was parked, findings a
   scout produced that nobody has decided on yet. Anything a future session
   would otherwise have to rediscover from a transcript it cannot see.

4. **Project posture** → `bin/om-project.sh mode <project> <mode>`
   A mode the captain changed in conversation but that never reached the
   registry.

## Curate, do not append

These files are read at every session start, so they are a budget, not a log.

- **Rewrite rather than append.** A fact that replaced an older one deletes it;
  it does not sit beneath it.
- **Date every entry** and drop what has stopped being true. A learning about a
  repository that has since been restructured is worse than nothing, because it
  is believed.
- **Evidence or it does not go in.** "The flaky test was a cookie race
  (`t007`, `tests/login.spec.ts:44`)" earns its line. "Tests are flaky" does
  not.
- **Nothing the repository already records.** Architecture, conventions, what
  the code does — that belongs in the code, and a description of it written
  here quietly becomes a prescription over it. If it is derivable by reading,
  do not write it down.

## Then report

Say what you filed and what is now safe to lose, in at most four lines:

    **Verstaut, captain** — 2 Learnings zu `api`, 1 Präferenz, `t009`s Fund im
    Backlog. Der Rest dieser Session ist entbehrlich.

If nothing was worth storing, say exactly that. A stow that invents entries to
look thorough is worse than one that files nothing.
