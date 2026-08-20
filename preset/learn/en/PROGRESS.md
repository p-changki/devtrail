---
tags:
  - type/study
type: study-progress
status: active
---

# 📈 PROGRESS — days and grasp

> Not a score — **where you got stuck**.
> If you do not write down what blocked you, it blocks you again.

Grasp: `✅ on my own` / `🟡 needed a hint` / `🔴 have to revisit`

---

## Daily log

> Copy the block below and stack new entries on top.

```
### Day N (YYYY-MM-DD)
- What: dayNN ____________________
- Grasp: ✅ / 🟡 / 🔴
- Stuck on:
- One line today:
```

---

### Day 1 (____-__-__)
- What: day01
- Grasp: ⬜
- Stuck on:
- One line today:

---

## Sections

> Status: `⬜ not started` / `🟡 in progress` / `✅ done`

| Section | Range | Status | Revisit? |
|---|---|---|---|
| Basics | day01–08 | ⬜ | |
| 🎓 Checkpoint | milestone-1 | ⬜ | |
| Deeper | day09– | ⬜ | |

## 🔴 To revisit (automatic)

```dataview
LIST
FROM "{{PATH}}"
WHERE contains(file.content, "🔴")
SORT file.mtime DESC
LIMIT 10
```
