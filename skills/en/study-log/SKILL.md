---
name: devtrail-study-log
description: Record study progress. Updates PROGRESS and WEEKLY-REVIEW.
triggers:
  - "log my studying"
  - "study log"
  - "/devtrail-study-log"
user_invocable: true
---

# Study log

## 🔑 Path

```bash
devtrail path study
```

The `learn` module must be installed. If it is not, point them at
`devtrail augment learn --apply`.

## What it does

| Target | What happens |
|---|---|
| `dayNN/` | Create or append today's study note |
| `PROGRESS.md` | Add one daily line · update the section status |
| `WEEKLY-REVIEW.md` | On weekends, add the weekly retro block |

## The point — "where I got stuck" is mandatory

```
- What: day12 generics
- Grasp: 🟡
- Stuck on: not sure when infer is needed in conditional types
- One line today: a generic is a function over types
```

**A grasp rating with an empty "stuck on" makes this log useless.**
You get stuck in the same place again and cannot remember why.

Grasp: `✅ on my own` / `🟡 needed a hint` / `🔴 have to revisit`

## Steps

### 1. Work out the day number

```bash
ls "$(devtrail path study)" | grep -E '^day[0-9]+$' | sort -V | tail -1
```

Propose last + 1 by default. Follow the user if they say otherwise.

### 2. The study note

Create the `dayNN/` folder and write in the `_day-template.md` shape.
**Only what was actually learned in the conversation.** Do not invent a
curriculum.

### 3. Update PROGRESS

Add the daily block **at the top**. Never delete existing entries.
Update the section status too (`⬜`/`🟡`/`✅`).

### 4. Check for gaps

If the last entry is 3+ days old, say so.

> **Do not nag.** "Looks like a 3-day break — let's pick it back up" is
> enough. Coming back after a break matters more than a perfect streak.

### 5. On weekends

Add this week's block to WEEKLY-REVIEW.
Collect everything marked 🔴 into "to revisit".

## Do not

- Leave "stuck on" empty
- Log something that was not learned — it must be grounded in the conversation
- Overwrite existing entries — always append
- Push them to go faster

## Report

```
✅ day13 regular expressions → Study/day13/
   Grasp 🟡 · 1 thing stuck on
   PROGRESS updated · section 'practice' 🟡
   ⚠️ Last entry was 4 days ago
```
