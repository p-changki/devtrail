---
name: devtrail-web-capture
description: 웹 페이지를 마크다운으로 정리해 Inbox에 담습니다. 승격은 별도입니다.
triggers:
  - "웹 저장"
  - "이 페이지 정리"
  - "/devtrail-web-capture"
user_invocable: true
---

# 웹 → Inbox

읽은 것을 나중에 처리하려고 담아두는 곳입니다.

## 🔑 경로

```bash
devtrail path inbox
```

## Inbox 는 임시 보관소입니다

**여기서 완성하려 하지 마세요.** 담고, 2일 뒤에 다시 보고, 승격하거나 버립니다.
승격은 `/devtrail-promote` 가 합니다.

Inbox 가 20개를 넘으면 담는 속도가 처리 속도를 앞선 것입니다.
그때는 **담기 전에 비우라고 알려주세요.**

```bash
ls "$(devtrail path inbox)"/*.md 2>/dev/null | wc -l
```

## 절차

### 1. 가져오기

URL 이면 내용을 읽습니다. 붙여넣은 텍스트면 그대로 씁니다.

### 2. 정리

| 채울 것 | 내용 |
|---|---|
| 제목 | 원문 제목. 없으면 내용에서 뽑습니다 |
| 원문/맥락 | **왜 이걸 담았는가** — 이게 없으면 2일 뒤에 왜 담았는지 모릅니다 |
| 한 줄 캡처 | 핵심 하나 |

**전문을 옮겨 적지 마세요.** 원문 URL 이 있으면 링크로 충분합니다.
담는 목적은 보관이 아니라 **다시 볼 이유를 남기는 것**입니다.

### 3. 저장

파일명: `YYYY-MM-DD HHmm 제목.md`
템플릿: `$(devtrail path templates)/Inbox Capture 템플릿.md`

frontmatter 에 반드시:
```yaml
type: inbox-capture
status: inbox
source: <URL>
source_type: web
review_at: <2일 뒤>
```

`review_at` 이 비면 허브의 「재방문할 때가 됐다」에 안 잡힙니다.

## 하지 말 것

- 전문 복사 — 링크 + 한 줄 캡처면 됩니다
- Inbox 를 건너뛰고 카드노트로 직행 — 승격 게이트를 거쳐야 합니다
- 「왜 담았는가」 비우기

## 결과 보고

```
✅ 2026-08-20 1430 RAG 청킹 전략.md → Inbox/
   ⚠️ Inbox 가 22개입니다 — /devtrail-promote 로 비우세요
```
