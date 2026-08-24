---
name: devtrail-web-capture
description: 웹 URL을 개발 자료실의 분야·용도별 Markdown 노트로 저장합니다. AI를 사용하지 않습니다.
triggers:
  - "웹 저장"
  - "이 페이지 정리"
  - "/devtrail-web-capture"
user_invocable: true
---

# 웹 → 개발 자료실

일반 웹 자료는 기존 Inbox를 건드리지 않고, 그 옆 `링크/분야/세부용도`에 저장합니다.
예: React 공식 문서는 `개발/프론트엔드/공식문서`, Lucide는 `디자인/아이콘`입니다.

## 저장 원칙

- AI·외부 API를 사용하지 않습니다.
- URL의 title·description·Open Graph 메타만 읽습니다.
- 명확한 도메인·URL·제목 규칙이 있을 때만 분류합니다.
- 확신할 수 없는 자료는 `공통/미분류`에 저장합니다. 억지로 추측하지 마세요.
- 같은 URL/canonical URL은 중복 저장하지 않습니다.

## 실행

```bash
devtrail path inbox --rel                         # 현재 볼트의 자료실 경로 확인
devtrail capture web --url "https://react.dev/"          # 미리보기
devtrail capture web --url "https://react.dev/" --apply  # 실제 저장
devtrail capture web --organize                   # 기존 미분류 링크 정리 미리보기
```

`--apply`에서만 노트와 없는 `_index.md` 허브를 생성하며, 모두
`devtrail undo`로 되돌릴 수 있습니다.

폴더 경로를 추측하거나 하드코딩하지 말고 `devtrail path inbox --rel`로 현재
볼트의 자료실 경로를 먼저 확인하세요.

## 노트 메타데이터

```yaml
type: docs | tool | inspiration | asset | article | reference
area: frontend | backend | infra | data-ai | design | common
topic: <세부 용도>
source: <도메인>
url: <원문 URL>
```

`area`와 `topic`은 폴더·자료실 `_index.md`·DevTrail 자료 탭의 필터가 함께
사용합니다. 전문을 복사하지 말고 원문 링크와 메타데이터를 보존하세요.

## 결과 보고

```
✅ React docs.md → 자료실/링크/개발/프론트엔드/공식문서/
```
