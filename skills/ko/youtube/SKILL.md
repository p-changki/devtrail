---
name: devtrail-youtube
description: 유튜브 URL의 자막을 뽑아 정리하고 볼트에 저장합니다. 개발일지와 허브에 자동으로 집계됩니다.
triggers:
  - "유튜브 정리"
  - "유튜브 분석"
  - "/devtrail-youtube"
user_invocable: true
---

# 유튜브 → 볼트

유튜브 영상을 분석해 볼트에 저장합니다. 여러 URL을 한 번에 처리합니다.

## 전제

- `yt-dlp` — `brew install yt-dlp`
- DevTrail 설정 — `devtrail doctor` 로 확인

## 🔑 경로는 반드시 조회해서 쓴다

**경로를 추측하거나 하드코딩하지 마세요.** 사용자마다 폴더 이름이 다릅니다.

```bash
devtrail path youtube        # 노트를 저장할 절대경로
devtrail path --rel youtube  # Dataview FROM 에 쓸 상대경로
devtrail path devlog         # 개발일지 폴더
```

경로 조회가 실패하면 **작업을 멈추고** 사용자에게 `devtrail init` 을 안내하세요.
엉뚱한 곳에 파일을 만들면 안 됩니다.

## 저장하면 3곳에 반영됩니다

| 위치 | 무엇 |
|---|---|
| `$(devtrail path youtube)/{날짜}-{슬러그}.md` | 노트 본체 |
| 같은 폴더의 `_index.md` | 허브가 자동 집계 |
| 오늘 개발일지의 「📺 오늘 본 유튜브」 | `watched_at` 이 오늘인 것 |

⚠️ 자동 집계는 frontmatter 에 의존합니다. **`type` · `watched_at` · `channel` ·
`tl_dr_oneline` 을 반드시 채우세요.** 비우면 집계에서 조용히 빠집니다.

## 절차

### 1. URL 추출

shorts · watch · youtu.be 를 모두 지원해야 합니다.

```bash
echo "$INPUT" | grep -oE 'https?://(www\.)?(youtube\.com/(watch\?v=|shorts/)|youtu\.be/)[A-Za-z0-9_-]{11}'
```

> 🔴 `youtube.com/shorts/` 를 빼먹지 마세요. 빠지면 shorts URL이 **에러 없이
> 조용히 누락**됩니다.

### 2. 중복 검사

같은 URL의 노트가 이미 있으면 건너뛰고 사유를 밝힙니다.

```bash
grep -rl "$URL" "$(devtrail path youtube)" 2>/dev/null
```

### 3. 자막 추출

```bash
yt-dlp --skip-download --write-auto-sub --sub-lang "ko,en" \
       --convert-subs srt -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

자막이 없으면 실패로 기록하고 **다음 URL로 넘어갑니다.** 한 개가 실패해도
나머지는 계속합니다.

### 4. 분석

자막을 읽고 아래를 채웁니다. 영상에 없는 내용을 지어내지 마세요.

- 한 줄 요약 (`tl_dr_oneline`)
- 핵심 포인트 5개 이하
- 타임라인
- **나에게 적용할 점** (`key_for_me`) — 이게 이 노트의 존재 이유입니다
- **분야와 세부 주제** (`category`·`area`·`topic`) — 자료실에서 다시 찾는 기준입니다

`category`와 `area`는 같은 값 하나만 사용합니다:
`frontend`, `backend`, `infra`, `data-ai`, `design`, `common`.
`topic`은 영상 내용에 맞게 `ui-components`, `api`, `database`,
`deploy-operations`, `models-tools`, `icons`, `landing-references` 등 하나를
고릅니다. 자막에 근거가 있으면 `uncategorized`로 두지 마세요.

### 5. 저장

템플릿은 `$(devtrail path templates)/유튜브 노트 템플릿.md` 를 따릅니다.
파일명은 `YYYY-MM-DD-케밥-슬러그.md` 입니다.

### 6. 결과 보고

```
✅ [제목] → 경로
❌ [URL] → 사유 (자막 없음 / 분석 실패)
```

## 하지 말 것

- 경로 하드코딩
- frontmatter 필드 비우기
- 자막에 없는 내용 추가
- 기존 노트 덮어쓰기 (중복이면 건너뛴다)
