---
name: om-deliver
description: >-
  Take finished work along its project's delivery path and close the task out.
  Use when a crewmate reports done: owns the delivery modes, merge authority,
  the scout report path, and teardown.
user-invocable: false
metadata:
  internal: true
---

# om-deliver

Work is not done when a crewmate says so. It is done when it has landed the way
its project's mode says, or when its report exists — and when the task's
worktree is safely gone.

## Before anything: reconcile

```sh
bin/om-state.sh task <id>
```

If the tree is dirty, or commits sit unpushed on a mode that expects a PR, the
work is not delivered. That is a finding: report it and route it back, do not
paper over it by pushing yourself. Hard rule 1 — you do not touch project
branches.

## Ship work, by mode

Read the mode; do not ask the captain what the registry answers.

### `direct-PR`

The crewmate pushed its branch and opened the PR. You verify it exists, read
its state, and bring the captain the outcome:

    **✓ t007 flaky-login** → PR offen · CI grün · Risiko niedrig

    - `tests/login.spec.ts:44` — Race auf den Session-Cookie, jetzt awaited
    - Gates: `npm test` → pass · `npm run typecheck` → pass

    **Mergen?** [ja / erst reviewen / nein]

You merge only on the captain's word. When they give it, `gh pr merge` is
yours to run — and it will surface an approval card before it goes through,
because the merge gate is policy, not just discipline. That card is a backstop,
not the permission itself: the captain's word in chat comes first.

### `no-mistakes`

Identical, with one thing before it: the crewmate ran the project's
no-mistakes pipeline and its result is part of the report. If it did not run,
the work is not ready — route it back with that as the reason.

### `local-only`

No forge. The crewmate committed to its branch and stopped. Merging is a local
fast-forward into the default branch, it is still a merge, and it still needs
the captain's explicit word. Ask, then do it in the project clone — this is the
narrow exception hard rule 1 names, and it covers a clean fast-forward and
nothing else. Never force, never rebase over anything, never touch work that is
not this task's.

### `+yolo`

A standing merge grant from the captain, for that project, inside the request
they already made. It relaxes rule 2 and nothing else: not force, not discard,
not destructive, not irreversible, not security-sensitive. A `+yolo` merge is
still reported after the fact, never silently.

## Scout work

The report is the deliverable. `bin/om-teardown.sh` harvests
`<worktree>/.om/report.md` into `data/<id>/report.md` before it removes
anything, so the report survives the worktree by design.

Report the finding, not the report:

    **✓ t009 scout: CI-Laufzeit** → 4 von 11 Minuten gehen an einen Schritt

    - `.github/workflows/ci.yml:28` — installiert Dependencies dreimal
    - Zwei Fixes möglich, beide klein → `data/t009/report.md`

    **Einen davon einplanen?** [den Cache-Fix / beide / später]

A finding authorizes nothing. If the scout turned up work worth doing, that is
a new intake, and the captain decides whether it happens.

## Teardown

```sh
bin/om-teardown.sh <id>
```

Run it once the work has landed or the report is harvested. The script owns the
complete landed-work test and refuses when tearing down would destroy the only
copy of something.

**A refusal is a finding.** Report it and route it:

    **⚠ t008 lässt sich nicht abbauen** — 2 Commits existieren nur im Worktree

    Nicht gepusht, nicht gemergt. Der Worktree bleibt stehen, bis das geklärt ist.

    **Was damit?** [PR daraus / weiterarbeiten lassen / verwerfen]

Only the captain's clear word turns into `--force`, and only for that one task.
Never infer it from "clean it up", "we don't need that anymore", or a general
tidying instruction — ask which tasks they mean and say what each one would
lose.

`bin/om-teardown.sh <id> --check` reports the verdict without changing
anything. Use it when you want to know whether a task is closable before you
raise it.

## Closing out

After a successful teardown:

- Append a line to `data/backlog.md`: what shipped, where it landed, the date.
- If the task taught this home something that will be true next time — a
  project's test command, a gate that always fails first, a convention a
  crewmate had to discover — put it in `data/learnings.md`, dated, with
  evidence. Curate it: rewrite and prune rather than appending forever.
- Say the outcome once, in one line, and stop. A finished task needs no
  retrospective.
