# 변경 기록

형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/) 를 따르고,
버전은 [유의적 버전](https://semver.org/lang/ko/) 을 따른다.

DevTrail 은 **사용자의 볼트를 건드리는 도구**라서, 버전 규칙을 노트에 미치는
영향으로 읽는다.

| 자리 | 언제 올리나 |
|---|---|
| **MAJOR** | 기존 볼트에 수동 조치가 필요할 때 — 폴더 구조·태그 규약이 바뀐다 |
| **MINOR** | 기능 추가. 기존 볼트는 그대로 두고 새 것만 들어온다 |
| **PATCH** | 버그 수정. 사용자가 알아챌 동작 변화가 없다 |

## 릴리스 절차

```bash
# 1. VERSION 을 올린다 (여기가 단일 출처다)
echo "0.3.0" > VERSION

# 2. CHANGELOG 의 [Unreleased] 를 새 버전으로 바꾸고 날짜를 넣는다

# 3. 검사를 통과시킨다 — 버전 · CHANGELOG 정합성도 여기서 본다
./tests/run.sh

# 4. 커밋하고 태그를 붙인다
git commit -am "release: v0.3.0"
git tag -a v0.3.0 -m "v0.3.0"
git push origin main --tags
```

태그는 `v` 접두사를 붙인다 — `v0.3.0`. CI 의 Swift 빌드가 이 형식에만 걸린다.
평소 PR 에서는 macOS 러너를 쓰지 않는다(무료 한도를 10배 소모한다).

---

## [Unreleased]

## [0.2.0] — 2026-08-20

개인 Obsidian 볼트에서 추출한 **프리셋**을 도입했다. 이전까지는 이미 세팅된
볼트에 GitHub 활동을 꽂아주는 얇은 자동화였고, 볼트 구조 자체는 사용자가
알아서 만들어야 했다.

### 추가

**볼트 프리셋**
- 폴더 정의 35개 · 모듈 6개 (`devlog` · `review` · `project` · `pkm` · `learn` · `personal`)
- 노트 템플릿 21종 — 경로 하드코딩 없이 실행 시점에 해석
- L1 대시보드 · 일일 체크인, 폴더별 L3 허브 자동 생성
- 입문 가이드 4종 · 학습 골격 5종

**명령**
- `devtrail scan` — 볼트 진단 6축. 쓰기 없음
- `devtrail path` — 경로 해석 단일 창구
- `devtrail augment` — 없는 것만 생성(멱등). 기본 dry-run
- `devtrail skills` — AI 스킬 설치 · 동기화 · 제거

**신규·기존 사용자 양쪽 지원**
- 모드 3종 — 새로 시작 · 기존 볼트에 얹기 · 분리 설치
- 「얹기」는 기존 폴더를 `config.dirs` 에 매핑한다. **노트를 움직이지 않는다**
- 기존 볼트는 자동 이동을 `Manual` 로 시작하고, 우리가 만들지 않은 폴더를 제외한다

**Obsidian 설정 병합 9종**
- 셸커맨드 · 라우팅 · Templater 매핑 · 데일리노트 · 단축키 · 에디터 설정 ·
  CSS 스니펫 · Linter · RAG 제외
- 전부 백업 후 병합한다. 기존 설정을 덮어쓰지 않는다

**AI 스킬 12종**
- 이식·개조 6 — `youtube` · `worklog` · `docs` · `pdca` · `qa-check` · `web-capture`
- 신규 6 — `promote` · `rollup` · `vault-health` · `moc` · `refcard` · `study-log`

### 변경

- 디자인 토큰을 도입해 CLI · 웹 대시보드 · 메뉴바 앱 · 볼트의 색 이름을 통일했다
- 웹 대시보드 팔레트를 moss green 으로 바꿨다
- 버전의 단일 출처를 `VERSION` 파일로 옮겼다

### 수정

- 자동 이동과 `alwaysUpdateLinks` 를 함께 켠다. 이게 꺼져 있으면 노트를 옮길
  때마다 링크가 조용히 끊긴다
- 라우팅 규칙을 구체성 순으로 생성한다. 이전에는 `project/*` 가 앞이라
  두 태그를 가진 노트가 엉뚱한 폴더로 끌려갔다
- RAG 제외 목록을 템플릿에서 생성한다. 손으로 관리하다 자동집계 섹션 하나가
  새고 있었다
- 주간리뷰가 날짜를 리터럴로 박는다. `this.period_start` 를 참조하면 `null` 로
  읽혀 쿼리 전체가 죽는다
- `devtrail augment` 가 잘못된 모듈에 `exit 1` 을 낸다. 서브셸 안에서 `die` 를
  불러 종료코드가 0 이었다
- `devtrail scan` 이 작은 폴더를 놓치지 않는다. 규모 가중치가 노트 8개짜리
  폴더를 임계값 아래로 밀어냈다

### 내부

- `lib/obsidian.sh` 440줄 → 62줄 + `lib/merge/` 9개
- `lib/init.sh` 553줄 → 63줄 + `lib/init/` 4개
- 회귀 테스트 56개 · 프로젝트 고유 함정 검사 3종(bash 3.2 · 경로 하드코딩 · 파일 길이)

## [0.1.0] — 2026-08-20

첫 공개. CLI · 메뉴바 앱 · 웹 대시보드 · launchd 자동 실행 · Obsidian 프리셋.

[Unreleased]: https://github.com/p-changki/devtrail/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/p-changki/devtrail/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/p-changki/devtrail/releases/tag/v0.1.0
