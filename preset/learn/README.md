---
tags:
  - type/moc
type: moc
scope: folder
status: active
---

# 💻 학습

> 매일 조금씩, 기록하면서 배우는 곳입니다.
> **점수가 아니라 "어디서 막혔는지"** 를 남기는 게 목적입니다.

## 어떻게 쓰나

```
1. day01/ 폴더를 만들고 그날 배운 것을 적는다
2. PROGRESS 에 이해도와 막힌 것을 한 줄 남긴다
3. 주말에 WEEKLY-REVIEW 를 쓴다
4. 한 구간이 끝나면 milestone 로 스스로 시험한다
```

폴더 하나 = 하루치입니다. 이름은 `day01`, `day02` … 로 붙입니다.

## 관리 노트

- [[PROGRESS]] — 진도와 이해도
- [[SUBJECTS]] — 무엇을 어떤 순서로 배울지
- [[WEEKLY-REVIEW]] — 주간 회고

## 진행 상황

```dataview
TABLE WITHOUT ID file.folder AS "일차", file.link AS "노트",
  dateformat(file.mtime, "MM-dd") AS "수정"
FROM "{{PATH}}"
WHERE file.name != "README" AND file.name != "PROGRESS"
  AND file.name != "SUBJECTS" AND file.name != "WEEKLY-REVIEW"
SORT file.folder DESC
LIMIT 20
```

## 최근 7일에 손댄 것

```dataview
LIST
FROM "{{PATH}}"
WHERE file.mtime >= date(today) - dur(7 days)
SORT file.mtime DESC
```
