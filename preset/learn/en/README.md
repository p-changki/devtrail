---
tags:
  - type/moc
type: moc
scope: folder
status: active
---

# 💻 Study

> A little every day, learning while you write it down.
> The point is not a score — it is **recording where you got stuck**.

## How to use it

```
1. Make a day01/ folder and write what you learned that day
2. Add one line to PROGRESS: how well you got it, and what blocked you
3. Write WEEKLY-REVIEW on the weekend
4. At the end of a section, test yourself with a milestone
```

One folder = one day. Name them `day01`, `day02`, and so on.

## Management notes

- [[PROGRESS]] — progress and grasp
- [[SUBJECTS]] — what to learn, in what order
- [[WEEKLY-REVIEW]] — weekly retro

## Where things stand

```dataview
TABLE WITHOUT ID file.folder AS "Day", file.link AS "Note",
  dateformat(file.mtime, "MM-dd") AS "Modified"
FROM "{{PATH}}"
WHERE file.name != "README" AND file.name != "PROGRESS"
  AND file.name != "SUBJECTS" AND file.name != "WEEKLY-REVIEW"
SORT file.folder DESC
LIMIT 20
```

## Touched in the last 7 days

```dataview
LIST
FROM "{{PATH}}"
WHERE file.mtime >= date(today) - dur(7 days)
SORT file.mtime DESC
```
