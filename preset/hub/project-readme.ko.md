---
tags:
  - type/project
  - project/{{NAME}}
  - area/dev
type: project-home
status: active
stage: {{STAGE}}
created: {{TODAY}}
updated: {{TODAY}}
project: {{NAME}}
next_action:
review_at:
---

# {{NAME}}

## 목표

- 

## 현재 상태

- 

## 문서

```dataview
TABLE WITHOUT ID file.link AS "문서", doc_type AS "종류",
  dateformat(file.mtime, "MM-dd") AS "수정"
FROM "{{FOLDER}}/docs"
WHERE file.name != "README"
SORT doc_type ASC, file.mtime DESC
```

## 작업 기록

> 작업 하나 = 폴더 하나. `⌘⇧W` 로 만든다.

```dataview
TABLE WITHOUT ID file.folder AS "작업",
  dateformat(file.mtime, "MM-dd") AS "수정"
FROM "{{FOLDER}}/worklogs"
SORT file.mtime DESC
LIMIT 20
```

## 이 프로젝트를 다룬 개발일지

> `⌘⇧D` 로 일지를 만들 때 프로젝트를 고르면 태그가 붙습니다.

```dataview
LIST
FROM #project/{{NAME}}
WHERE type = "devlog"
SORT file.day DESC
LIMIT 15
```

## 메모와 트러블슈팅

```dataview
TABLE WITHOUT ID file.link AS "노트", type AS "유형",
  dateformat(file.mtime, "MM-dd") AS "수정"
FROM #project/{{NAME}}
WHERE type != "devlog" AND type != "worklog" AND type != "project-home"
SORT file.mtime DESC
LIMIT 20
```

## 레포 문서

> `devtrail sync` 가 채우는 거울 폴더입니다. 여기서 직접 고치지 마세요.
> 레포명이 이 프로젝트 키와 정확히 같을 때만 나타납니다.

```dataview
LIST
FROM "{{REPODOCS}}/{{NAME}}"
SORT file.mtime DESC
LIMIT 10
```

## 다시 볼 때가 된 것

```dataview
TABLE WITHOUT ID file.link AS "노트", review_at AS "재방문"
FROM #project/{{NAME}}
WHERE review_at != null AND review_at <= date(today)
SORT review_at ASC
```

## 다음 액션

- [ ] 
