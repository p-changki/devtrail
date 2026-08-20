---
name: devtrail-worklog
description: 작업 기록을 프로젝트의 worklogs 폴더에 남깁니다. 작업 하나 = 폴더 하나.
triggers:
  - "워크로그 남겨줘"
  - "워크로그 업데이트"
  - "/devtrail-worklog"
user_invocable: true
---

# 워크로그

작업 하나를 폴더 하나로 남깁니다. 날짜와 작업명이 폴더 이름에 들어가서,
나중에 목록만 훑어도 흐름이 보입니다.

## 🔑 경로

```bash
devtrail path projects       # 프로젝트 루트
```

**볼트 밖에 쓰지 마세요.** 예전에는 `~/Desktop/worklogs/` 에 따로 쌓았는데,
볼트 안 기록과 이원화돼 둘 다 반쪽이 됐습니다. 프로젝트 폴더 안에 넣습니다.

```
$(devtrail path projects)/<프로젝트>/worklogs/
└── YYYY-MM-DD_작업이름/
    └── worklog.md
```

## 절차

### 1. 프로젝트 판별

현재 작업 디렉터리 이름에서 추론합니다. 프로젝트 폴더 목록과 대조하세요.

```bash
ls "$(devtrail path projects)"
```

확실하지 않으면 **질문 한 번만** 하고 진행합니다.
프로젝트 폴더가 없으면 만들지 말고, Obsidian에서 `⌘⇧P` 로 만들라고 안내하세요
— 그래야 docs 골격과 허브가 함께 생깁니다.

### 2. 작업명

브랜치명이나 대화 맥락에서 추론합니다. 케밥케이스로 짧게.

```
2026-08-20_login-token-fix
2026-08-20_report-flow-refactor
```

### 3. 작성

`worklog.md` 에 아래를 채웁니다.

```markdown
---
tags:
  - type/doc
  - project/<프로젝트>
type: worklog
status: done
created: YYYY-MM-DD
updated: YYYY-MM-DD
project: <프로젝트>
---

# <작업명>

## 작업 배경   ← 필수

무엇이 이 작업을 촉발했는가:
1. 트리거 — 요청·버그·분석 중 무엇인가
2. 작업 전 상태 — 무엇이 문제였나
3. 선택한 접근과 이유 — 대안은 무엇이었나

## 한 것

- 

## 검증

- 무엇을 어떻게 확인했나
- 결과

## 남은 것

- [ ] 
```

> **「작업 배경」을 비우지 마세요.** 몇 달 뒤에 이 기록을 읽는 사람에게
> 필요한 건 '무엇을 했는가'가 아니라 '왜 그렇게 했는가'입니다.

### 4. 이어쓰기

`워크로그 업데이트` 면 해당 프로젝트의 **가장 최근 폴더**를 찾아 이어씁니다.
새로 만들지 않습니다.

## 결과 보고

1. 만든 경로
2. 작업 요약 3~5줄
3. 다음 액션 (있으면)
