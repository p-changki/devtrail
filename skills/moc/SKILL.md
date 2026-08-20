---
name: devtrail-moc
description: 주제 MOC를 만들고 갱신합니다. 흩어진 노트를 주제로 묶습니다.
triggers:
  - "MOC 만들어줘"
  - "주제 정리"
  - "/devtrail-moc"
user_invocable: true
---

# 주제 MOC

카드노트가 쌓이면 주제별 입구가 필요합니다. MOC(Map of Content)가 그 입구입니다.

## 🔑 경로

```bash
devtrail path moc        devtrail path zettel
```

## 먼저 기존 주제를 확인합니다

```bash
grep -rho '#주제/[^ ]*' "$(devtrail path zettel)" | sort | uniq -c | sort -rn
```

**새 주제를 남발하면 MOC 가 파편화됩니다.**
`#주제/react` 와 `#주제/reactjs` 가 따로 생기면 둘 다 반쪽이 됩니다.

## 언제 MOC 를 만드나

| 상황 | 판단 |
|---|---|
| 같은 `#주제/` 노트 3개 이상 | 만들 때가 됐다 |
| 1~2개 | 아직 이르다 — 태그만 유지 |
| 이미 MOC 가 있다 | 갱신한다, 새로 만들지 않는다 |

## 절차

### 새로 만들 때

1. 주제 슬러그를 정합니다 (기존과 겹치지 않게)
2. `$(devtrail path moc)/<주제> MOC.md` 로 만듭니다
3. 템플릿은 `MOC 템플릿.md` 를 따릅니다
4. **학습 로드맵**을 채웁니다 — 기초/중급/고급으로 무엇을 봐야 하는지

### 갱신할 때

1. 자동 집계(Dataview)는 그대로 둡니다 — 손댈 필요가 없습니다
2. **숙성도별 핵심 노트**를 손으로 정리합니다
   - Evergreen(완성된 이해) / Budding(정리 중) / Seedling(막 수집)
3. **열린 질문**을 갱신합니다 — 아직 모르는 것이 이 MOC 의 다음 방향입니다
4. 관련 MOC 를 연결합니다

## 고아 노트 연결

`#주제/` 가 없는 카드노트를 찾아 어느 MOC 에 붙을지 제안합니다.
**태그를 임의로 붙이지 말고 제안만 합니다.**

## 결과 보고

```
갱신: RAG MOC
  Evergreen 2 · Budding 5 · Seedling 3
  열린 질문 2개 추가
  ⚠️ #주제/ 없는 카드노트 4개 — 붙일 곳 제안 아래
```
