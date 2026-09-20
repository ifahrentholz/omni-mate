---
name: om-intake
description: >-
  Turn a captain's request into an explicit task contract before any crewmate
  exists. Use at the start of every new request: decides answer / ship / scout /
  decision, settles scope, delivery path and autonomy, and refuses to guess.
user-invocable: false
metadata:
  internal: true
---

# om-intake

Every task gets a contract before it starts. The machinery refuses to guess,
because a crewmate that has to infer its own scope will infer a bigger one.

## 1. What kind of request is this?

Four shapes. Pick the cheapest one that actually fits.

| shape | it looks like | what happens |
| --- | --- | --- |
| **answer** | "what does this repo do?", "which mode is `foo` on?" | You answer from your own records or a cheap read. No crewmate. |
| **ship** | "fix the flaky login test", "add dark mode" | A change the captain wants in a project. Ship crewmate, worktree, delivery path. |
| **scout** | "why is CI slow?", "is it worth moving to X?" | A question about a project that needs real investigation. Scout crewmate, report, no change. |
| **decision** | "should we do A or B?" | The captain needs to choose. Often a scout first, then the captain. Never decide for them. |

Two rules about this table:

- **Reading a project is not changing it.** A question you can answer by
  reading one file is an answer, not a scout task. Do not spawn a crewmate to
  look something up.
- **A change is never an answer.** However small. Hard rule 1 has no size
  threshold, because "trivial" is a guess you make before you look.

A request can carry several. "Fix the flaky test and tell me why it was flaky"
is one ship task; the why comes back in its result. "Fix these three unrelated
bugs" is three ship tasks, because three crewmates in three worktrees do not
collide and one crewmate doing three things produces one unreviewable diff.

## 2. What the contract has to settle

Do not dispatch until each of these has an answer. Where one is missing and the
captain has to supply it, ask for exactly that one thing.

- **Project.** Which registered project. If it is not registered, that is the
  first thing to settle — `bin/om-project.sh add <url>`, and say which mode you
  are giving it and why.
- **Scope.** What is in, and the nearest thing that is out. One sentence each.
- **Acceptance.** How a crewmate knows it is done. For ship work this is
  behaviour, not effort: "the test passes ten runs in a row", not "look at the
  test".
- **Delivery.** The project's mode decides this, not you. Read it with
  `bin/om-project.sh mode <project>`. Do not ask the captain what a record
  already answers.
- **Autonomy.** What the crewmate may do without coming back. Default: nothing
  outward beyond its own branch and PR. Anything that reaches the network, runs
  a bootstrap, touches credentials, or writes outside the worktree needs the
  captain's word first, named specifically in the brief.

## 3. Where autonomy comes from

Autonomy is granted, never assumed, and it never widens on its own.

- The captain's word in this conversation, for this request.
- A project's standing `+yolo`, and only for merges, and only inside the
  request they already made.

A recommendation authorizes nothing. A passing review authorizes nothing. A
scout's finding that some change is clearly needed authorizes nothing — it is a
finding to route, and routing it means bringing the captain the option.

## 4. The cheapest fit wins, and you propose it

Say which shape you picked, in one line, with a default, and get on with it:

    Ship-Task auf `api`, direct-PR. Scope: nur der Login-Test. [los / erst scouten]

Escalating costs the captain one word. Ceremony they did not need costs a
worktree, a crewmate, and twenty minutes. When in doubt, propose the smaller
shape and name what it leaves out.

## 5. When you must stop and ask

Only these. Everything else is a judgment call you make yourself and state.

- The request could mean two materially different pieces of work.
- It needs a project that is not registered, or a mode the captain has not set.
- It would need autonomy you do not have (anything outward, anything
  destructive, anything irreversible, anything security-sensitive).
- It asks you to change a project directly. That is hard rule 1: say what you
  will do instead — dispatch a crewmate — and do it.

Then load `om-dispatch`.
