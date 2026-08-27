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

### 2.5 학습 목적과 영상 장르 결정

입력에 `목적:` 또는 `얻고 싶은 것:`이 있으면 그것을 이 노트의 학습 목적으로 쓴다.
없으면 영상 제목·자막을 바탕으로 목적을 한 문장으로 **추정**하고, 노트에 `추정한 학습
목적`이라고 표시한다. 목적을 일반적인 "영상 요약"으로 축소하지 마라. 사용자가 나중에
무엇을 판단·실행·검증하려는지를 구체적으로 쓴다.

아래 중 하나로 영상 장르를 고른다. 애매하면 `general`로 둔다.

- `design-critique` — 디자인 리뷰·포트폴리오 피드백
- `tutorial` — 기술·도구 사용법·구현 강의
- `tool-review` — 도구·서비스·제품 비교/리뷰
- `career-interview` — 커리어 조언·인터뷰·경험담
- `news-trend` — 뉴스·업계 동향·시장 해설
- `strategy` — 사업·제품·마케팅 전략
- `general` — 그 밖의 정보성 영상

### 3. 자막 추출

```bash
yt-dlp --skip-download --write-sub --write-auto-sub --sub-langs "ko.*,en.*" \
       --convert-subs srt -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

수동 자막과 자동 생성 자막을 모두 시도한다. 명령의 출력과 생성된 `.srt` 파일을
확인해 다음처럼 구분해 기록하고 **다음 URL로 넘어간다.** 한 개가 실패해도 나머지는
계속한다.

| 조건 | 기록할 사유 |
|---|---|
| `Video unavailable`, `Private video`, 로그인/연령/지역 제한 오류 | 영상 접근 불가 |
| 명령은 성공했지만 `.srt` 파일이 없음 | 자막 없음 |
| 그 밖의 yt-dlp 오류 | 자막 추출 실패 — 오류 요약 |

브라우저에서는 재생되지만 접근 불가라면, 로그인 계정의 권한 또는 브라우저 세션 차이일 수
있다. 이때에만 사용자가 **일회성으로 제공한** Netscape `cookies.txt` 경로를 다음처럼
사용할 수 있다. 쿠키 파일 경로와 내용은 노트, 설정 파일, 로그에 저장하거나 출력하지
않는다.

```bash
yt-dlp --cookies "$YTDLP_COOKIES_FILE" --skip-download --write-sub --write-auto-sub \
       --sub-langs "ko.*,en.*" --convert-subs srt \
       -o "/tmp/dt-yt-%(id)s.%(ext)s" "$URL"
```

쿠키 재시도도 접근 불가이면 우회 방법을 약속하지 말고 해당 상태를 보고한다.

### 4. 분석

자막을 읽어 **의사결정에 쓰는 정보**를 먼저 추출한다. 단순한 줄거리 요약이 목적이
아니다. 영상에 없는 내용을 지어내지 마세요.

#### 모든 장르의 공통 출력

노트 최상단의 TL;DR 바로 다음에 `## 바로 쓰는 판단 기준`을 둔다. 3~7개의 판단 카드로
작성하고, 각 카드에는 아래를 짧게 담는다.

- **판단/주장** — 화자가 좋다·나쁘다·해야 한다고 말한 재사용 가능한 기준
- **적용 맥락** — 그 판단이 성립하는 상황
- **근거 또는 문제 신호** — 화자가 든 이유, 또는 눈으로 확인할 수 있는 징후
- **내 적용** — 다음 작업에서 실행하거나 확인할 한 가지
- **분류** — `원칙` / `조건부 조언` / `개인 취향` / `사실 주장`
- **근거** — 가능한 경우 짧은 인용과 타임스탬프. 타임스탬프가 없으면 없다고 밝힌다.

`64 → 48`처럼 특정 화면에서만 유효한 수치는 보편 규칙으로 일반화하지 않는다. 예를
들어 "시각 위계가 이미지보다 강해질 때 크기를 낮춘다"처럼 원칙과 개별 처방을 분리한다.
화자의 의견, 자막으로 확인된 사실, AI의 해석을 섞지 말고 AI의 해석에는 `해석` 표기를
붙인다.

#### 장르별 추가 출력

선택한 장르에 맞는 섹션만 추가한다.

| 장르 | 추가로 추출할 것 |
|---|---|
| `design-critique` | 문제 신호 · 수정 방향 · 예외/브랜드 맥락 · 재사용 체크리스트 |
| `tutorial` | 전제조건 · 단계 · 실패 포인트 · 적용 순서 |
| `tool-review` | 적합한 사용자 · 장점/제약 · 대체재 · 도입 판단 |
| `career-interview` | 화자의 경험 · 일반화 가능한 조언 · 개인 사례에 그치는 부분 |
| `news-trend` | 확인된 사실 · 화자의 해석 · 영향 대상 · 대응 필요성 |
| `strategy` | 주장 · 고객/시장 전제 · 성공 조건 · 리스크 · 검증할 실험 |

`## 인사이트 & 적용점`에는 학습 목적에 직접 연결되는 항목만 남긴다. 상세 내용,
진행 순서, 전체 자막은 근거를 다시 확인할 때만 쓰는 보조 자료이므로 그 뒤에 둔다.

- 한 줄 요약 (`tl_dr_oneline`)
- 학습 목적과 장르
- 바로 쓰는 판단 기준 3~7개
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
❌ [URL] → 사유 (영상 접근 불가 / 자막 없음 / 자막 추출 실패 / 분석 실패)
```

## 하지 말 것

- 경로 하드코딩
- frontmatter 필드 비우기
- 자막에 없는 내용 추가
- 기존 노트 덮어쓰기 (중복이면 건너뛴다)
