---
tags:
  - type/study
type: study-weekly
status: active
---

# 🔄 WEEKLY-REVIEW — weekly study retro

> Once a week. Five minutes.
> Copy the block below and stack new entries on top.

```
## YYYY-Www (MM-DD – MM-DD)

### What I did this week
- day__ – day__

### 🔴 To revisit
- 

### This week in one line
> 

### Next week (one or two things)
- 
```

---

## Study notes touched this week

```dataview
TABLE WITHOUT ID file.folder AS "Day", dateformat(file.mtime, "MM-dd") AS "Modified"
FROM "{{PATH}}"
WHERE file.mtime >= date(today) - dur(7 days)
  AND file.name != "README" AND file.name != "PROGRESS"
  AND file.name != "SUBJECTS" AND file.name != "WEEKLY-REVIEW"
SORT file.mtime DESC
```

## Gaps

> How many days you took off shows in the date gaps above.
> **Coming back after a break matters more than a perfect streak.**
