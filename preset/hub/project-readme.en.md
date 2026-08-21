---
tags:
  - type/project
  - project/{{NAME}}
  - area/dev
type: project-home
status: active
stage: planning
created: {{TODAY}}
updated: {{TODAY}}
project: {{NAME}}
next_action:
review_at:
---

# {{NAME}}

## Goal

- 

## Where it stands

- 

## Documents

```dataview
TABLE WITHOUT ID file.link AS "Document", doc_type AS "Kind",
  dateformat(file.mtime, "MM-dd") AS "Updated"
FROM "{{FOLDER}}/docs"
WHERE file.name != "README"
SORT doc_type ASC, file.mtime DESC
```

## Work log

> One piece of work = one folder. `⌘⇧W` creates it.

```dataview
TABLE WITHOUT ID file.folder AS "Work",
  dateformat(file.mtime, "MM-dd") AS "Updated"
FROM "{{FOLDER}}/worklogs"
SORT file.mtime DESC
LIMIT 20
```

## Devlogs that touched this project

> Pick the project when you create a devlog with `⌘⇧D` and the tag is added.

```dataview
LIST
FROM #project/{{NAME}}
WHERE type = "devlog"
SORT file.day DESC
LIMIT 15
```

## Notes and troubleshooting

```dataview
TABLE WITHOUT ID file.link AS "Note", type AS "Type",
  dateformat(file.mtime, "MM-dd") AS "Updated"
FROM #project/{{NAME}}
WHERE type != "devlog" AND type != "worklog" AND type != "project-home"
SORT file.mtime DESC
LIMIT 20
```

## Repo docs

> A mirror folder filled by `devtrail sync`. Do not edit it here.
> It only shows up when the repo name matches this project key exactly.

```dataview
LIST
FROM "{{REPODOCS}}/{{NAME}}"
SORT file.mtime DESC
LIMIT 10
```

## Due for another look

```dataview
TABLE WITHOUT ID file.link AS "Note", review_at AS "Revisit"
FROM #project/{{NAME}}
WHERE review_at != null AND review_at <= date(today)
SORT review_at ASC
```

## Next actions

- [ ] 
