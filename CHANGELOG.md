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

### 추가

- `devtrail undo` — 변경 이력과 되돌리기. 백업이 `~/.devtrail/journal/<작업ID>/`
  에 한 작업 단위로 묶인다. 인자 없이 부르면 이력, ID 를 주면 dry-run,
  `--apply` 로 실제 복원.
- `devtrail update` — DevTrail 자체 갱신. 기본 dry-run 으로 바뀔 커밋과
  버전을 먼저 보여준다. `--check` 는 조용히 확인만 한다(종료코드로 답).
- `devtrail config migrate` — 설정 스키마만 따로 올린다.
- 설정 스키마 마이그레이션 엔진 (`lib/migrate.sh` · `lib/migrations/`).
  순차 적용하고, '없는 것을 채우는' 방향만 한다. 두 번 돌려도 같다.
- 설정 스키마 v2 — `install.mode` · `install.modules` · `dirs` 를 채운다.
- 회귀 테스트 27개 (`tests/test-undo.sh`) · 마이그레이션 정합성 검사.

### 수정

- `devtrail augment` 가 init 에서 고른 모듈을 무시했다. `install.modules` 를
  저장만 하고 읽지 않아, 사용자가 거절한 폴더가 되살아났다.
- 백업이 12곳에 `<원본>.bak.<타임스탬프>` 로 흩어져 있어 어느 백업이 어느
  작업에 속하는지 알 수 없었다. 되돌리려면 타임스탬프를 눈으로 맞춰야 했다.
- `mkdir -p a/b/c` 가 만든 중간 폴더가 기록되지 않아, 되돌린 뒤 빈 껍데기가
  남았다. `jr_mkdir` 이 새로 생긴 모든 단계를 기록한다.
- 되돌릴 때 비어 있지 않은 폴더를 조용히 넘겼다. "삭제"라고 말해놓고 남겨두면
  사용자는 지워진 줄 안다. 이제 남겨둔 것을 반드시 알린다.
- `devtrail update` 가 로컬이 원격보다 **앞서** 있을 때도 뒤쳐진 것으로 보고
  `reset --hard` 대상으로 삼았다. 기여자의 미푸시 커밋이 사라진다.
  조상 관계를 확인해 앞서 있으면 갱신하지 않는다.

### 내부

- `CONTRIBUTING.md` · PR 템플릿 · 이슈 템플릿(버그·기능) · `.editorconfig`.
  버그 템플릿은 `devtrail version`·`doctor`·`scan` 과 설치 모드를 요구한다 —
  이 도구는 볼트 상태에 따라 동작이 갈려서 그게 없으면 재현이 안 된다.
  노트 손실을 체크하면 조사보다 `devtrail undo` 를 먼저 안내한다.
- `docs/ARCHITECTURE.md` — 계층과 의존 방향, 어디에 무엇을 넣는지,
  지켜야 할 규칙 10가지. 규칙은 전부 실제 사고에서 나온 것이고,
  검사가 있는 항목은 표시했다.
- 문서 정합성 검사. 문서가 가리키는 저장소 경로가 실재하는지, 적어둔
  개수가 코드와 맞는지, 안내하는 `devtrail` 명령이 실제로 있는지 본다 —
  문서가 코드와 어긋나면 없느니만 못하다.

### 수정 (검사)

- `git grep` 이 **추적되지 않은 파일을 보지 않아** 새로 만든 파일이 검사를
  통째로 빠져나갔다. bash 3.2 · 버전 하드코딩 · 문서 정합성 세 검사가
  전부 그랬다. 커밋 전에 잡으라는 검사가 커밋 후에야 보였다.
  `--untracked` 를 붙였고, 실증으로 확인했다.
- GitHub Actions CI. 잡을 '어디서 깨지는가'로 나눈다 — `lint`·`guard` 는
  ubuntu, 동작 테스트는 **macOS**. ubuntu 의 bash 5 에서는 이 프로젝트
  고유의 bash 3.2 함정이 재현되지 않는다. Swift 빌드는 태그에서만 돈다.
- `tests/run.sh` 가 그룹을 받는다 — `lint` · `guard` · `fast` · (전부).
- bash 3.2 검사가 자기 정규식을 먼저 시험한다. `[가-힣]` 범위는 로케일을
  타서, 안 맞는 환경에서는 '통과'로 보이면서 아무것도 안 본다.
- 릴리스 태그와 `VERSION` 이 다르면 앱 빌드를 차단한다.
- 저널이 `common.sh` 에서 로드되어 모든 명령이 쓸 수 있다.
- 저널을 만들지 못하면 쓰기도 하지 않는다 — 되돌릴 수 없는 변경을 조용히
  진행하는 것보다 멈추는 쪽을 택한다.

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
