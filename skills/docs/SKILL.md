---
name: devtrail-docs
description: 프로젝트 문서를 올바른 위치에 저장합니다. 문서 종류에 따라 자동 배치.
triggers:
  - "docs 정리"
  - "문서 저장"
  - "/devtrail-docs"
user_invocable: true
---

# 프로젝트 문서 배치

문서를 어디에 둘지 고민하지 않게 합니다.

## 🔑 경로

```bash
devtrail path projects
ls "$(devtrail path projects)"     # 프로젝트 목록
```

**프로젝트 목록을 하드코딩하지 마세요.** 사용자마다 다릅니다.

## 문서 골격

`⌘⇧P` 로 만든 프로젝트에는 이 골격이 있습니다. 번호는 **읽는 순서**입니다.

```
docs/
├── 00-overview       무엇을 왜 만드는가
├── 01-product        요구사항 · PRD
├── 02-domain         도메인 모델 · 용어
├── 03-architecture   구조 · 기술 선택
├── 04-data           스키마 · 마이그레이션
├── 05-infra          배포 · 환경
├── 06-compliance     보안 · 규정
└── 07-delivery       릴리스 · 운영
```

## 배치 규칙

| 문서 종류 | 위치 |
|---|---|
| PRD · 요구사항 | `01-product/` |
| 설계안 · 아키텍처 | `03-architecture/` |
| 스키마 · 데이터 | `04-data/` |
| 배포 · 인프라 | `05-infra/` |
| 의사결정(ADR) | `00-overview/` 또는 해당 영역 |
| 회의록 | `00-overview/` |

**애매하면 사용자에게 묻습니다.** 잘못 두면 나중에 못 찾습니다.

## 절차

1. **프로젝트 판별** — 작업 디렉터리 이름에서 추론, 애매하면 질문 한 번
2. **문서 종류 판별** — 내용을 보고 위 표에서 고릅니다
3. **파일명** — `YYYY-MM-DD 제목.md`
4. **frontmatter**

```yaml
tags:
  - type/doc
  - doc/<종류>
  - project/<프로젝트>
type: doc
doc_type: <종류>
status: draft
project: <프로젝트>
```

## 하지 말 것

- 골격 밖에 새 폴더 만들기 — 8개로 충분합니다
- 기존 파일 덮어쓰기 — 같은 이름이면 `-2` 를 붙입니다
- 프로젝트 폴더 직접 만들기 — Obsidian `⌘⇧P` 를 안내하세요.
  그래야 docs 골격과 허브가 함께 생깁니다

## 결과 보고

```
✅ 2026-08-20 결제 시스템 설계.md
   → 프로젝트/myapp/docs/03-architecture/
```
