---
name: devtrail-rollup
description: Roll devlogs up into weekly reviews, and weekly reviews up into monthly.
triggers:
  - "roll up the week"
  - "monthly review"
  - "/devtrail-rollup"
user_invocable: true
---

# Devlog → weekly → monthly

**This friction is why the original vault had zero monthly reviews.**
Devlogs piled up daily and nobody rolled them upward.

## 🔑 Paths

```bash
devtrail path devlog    devtrail path weekly    devtrail path monthly
```

## What it does

| Target | Reads | Writes into |
|---|---|---|
| Weekly | That week's 5–7 devlogs | The empty sections of the weekly review |
| Monthly | That month's 4–5 weekly reviews | The empty sections of the monthly review |

**Dataview already produces the lists.** What this skill adds is
**summary and pattern-finding**, not lists.

## Steps

### 1. Find the target

If the note already exists, **fill only the empty sections.** Never overwrite
what the user wrote. If it does not exist, tell them to create it from the
template in Obsidian.

### 2. Read

Read that period's devlogs. **Skip the auto-generated sections** — Dataview
code blocks and things like "notes created today" are not content.

### 3. What to fill

Weekly review:
- **Main theme** — the week in one word
- **What I learned** — collect the "what I learned today" lines, deduplicated
- **Three notes worth revisiting** — as real links
- **Unfinished** — anything left unchecked in the devlogs

Monthly review:
- **Top 3 things I learned** — themes that repeat across weeks
- **Wins** — merged PRs, finished projects
- **What to improve** — what keeps slipping

### 4. Rules

- **Do not invent what is not there.** If there are only 3 days of devlogs,
  say "based on 3 days"
- **The one-line summary is the user's to write.** Leave "this week in one
  line" blank — a retro someone else wrote is not a retro
- Point out gaps in the days

## Report

```
Weekly review 2026-W34 · read 5 devlogs
  Main theme: auth refactor
  4 things learned · 2 unfinished
  ⚠️ 2 missing days (08-19, 08-20)
  ✍️ "This week in one line" is yours to fill in
```
