---
name: devtrail-pdca
description: 계획·설계·분석·보고를 하고 결과를 프로젝트 문서로 남깁니다.
triggers:
  - "PDCA로 진행"
  - "계획 세워줘"
  - "/devtrail-pdca"
user_invocable: true
---

# PDCA — 계획하고 기록한다

`plan` · `design` · `analyze` · `report` · `iterate` 중 하나로 실행합니다.
없으면 `analyze` 입니다.

## 🔑 원본과의 차이 — 결과를 볼트에 남깁니다

원본은 화면에 출력만 하고 끝났습니다. **그러면 다음 주에 아무것도 안 남습니다.**
여기서는 결과를 프로젝트 문서로 저장합니다.

```bash
devtrail path projects
ls "$(devtrail path projects)"
```

| 서브커맨드 | 저장 위치 |
|---|---|
| `plan` | `<프로젝트>/docs/01-product/` |
| `design` | `<프로젝트>/docs/03-architecture/` |
| `analyze` | `<프로젝트>/docs/00-overview/` |
| `report` | `<프로젝트>/worklogs/<날짜>_<작업>/` |
| `iterate` | 직전 문서에 이어씀 |

프로젝트를 판별할 수 없으면 **질문 한 번**만 하고, 그래도 없으면 화면 출력만 합니다.
저장할 곳이 없다고 작업을 멈추지는 마세요.

## 서브커맨드별 출력

### `plan`
- 문제 정의 — 무엇이 문제인가
- 범위 — 하는 것 / 안 하는 것
- **측정 가능한 성공 기준** — "잘 된다"가 아니라 숫자나 조건으로
- 인수 체크리스트

### `design`
- 설계 개요
- 핵심 결정과 근거
- **트레이드오프** — 무엇을 포기했는가
- 리스크와 롤백 계획

### `analyze`
- 발견사항 — **근거와 함께**. 추측은 추측이라고 밝힌다
- 가정
- 미해결 질문
- 권장 다음 단계 **하나**

### `report`
- 계획 대비 완료
- **검증 근거** — 무엇을 어떻게 확인했는가
- 갭과 근본 원인

### `iterate`
직전 결과를 읽고 무엇이 바뀌었는지만 씁니다. 전체를 다시 쓰지 마세요.

## 규칙

- **한국어**로 씁니다
- 근거 없는 단정을 하지 않습니다 — 모르면 「미해결 질문」에 넣습니다
- 성공 기준은 **검증 가능**해야 합니다. "빨라진다"는 기준이 아닙니다
- 문서를 저장하면 경로를 보고합니다

## frontmatter

```yaml
tags:
  - type/doc
  - doc/<plan|design|analyze|report>
  - project/<프로젝트>
type: doc
doc_type: <서브커맨드>
status: draft
```
