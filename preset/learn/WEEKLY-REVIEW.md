---
tags:
  - type/study
type: study-weekly
status: active
---

# 🔄 WEEKLY-REVIEW — 주간 학습 회고

> 매주 한 번. 5분이면 됩니다.
> 아래 블록을 복사해서 위에 쌓아 올리세요.

```
## YYYY-Www (MM-DD ~ MM-DD)

### 이번 주에 한 것
- day__ ~ day__

### 🔴 다시 봐야 할 것
- 

### 이번 주 한 줄
> 

### 다음 주 목표 (1~2개만)
- 
```

---

## 이번 주에 손댄 학습 노트

```dataview
TABLE WITHOUT ID file.folder AS "일차", dateformat(file.mtime, "MM-dd") AS "수정"
FROM "{{PATH}}"
WHERE file.mtime >= date(today) - dur(7 days)
  AND file.name != "README" AND file.name != "PROGRESS"
  AND file.name != "SUBJECTS" AND file.name != "WEEKLY-REVIEW"
SORT file.mtime DESC
```

## 공백일 확인

> 며칠 쉬었는지는 위 목록의 날짜 간격으로 봅니다.
> **완벽하게 매일 하는 것보다 끊겼을 때 다시 시작하는 게 중요합니다.**
