# 아키텍처

DevTrail 은 **남의 볼트를 건드리는 도구**다. 이 문장이 아래 모든 결정의
근거다 — 되돌릴 수 있어야 하고, 덮어쓰지 않아야 하고, 무엇을 할지 먼저
보여줘야 한다.

이 문서는 기여자가 **"이걸 어디에 넣어야 하나"** 를 스스로 답할 수 있게
하는 것이 목적이다.

---

## 한 장으로 보는 구조

```
bin/devtrail          라우터. 명령을 lib/ 로 넘기기만 한다
  └─ lib/common.sh    모든 명령이 쓰는 것 (출력·설정·경로·볼트)
       └─ lib/journal.sh   변경 저널 — 되돌리기의 근거

lib/<명령>cmd.sh      명령 하나당 파일 하나
lib/merge/            Obsidian 설정 병합기 9종 — 볼트 '안'
lib/setupcmd.sh       비대화형 셋업 — init 과 '같은' 적용 경로
lib/setup/spec.sh     셋업 스펙 검증·기본값 (기본값의 단일 출처)
lib/setup/plan.sh     "적용하면 무엇이 바뀌는가" — 적용부와 같은 함수를 쓴다
lib/obsidian_app.sh   Obsidian 앱 자체 — 볼트 '밖' (설치·볼트목록·등록·실행)
lib/plugins.sh        커뮤니티 플러그인 설치 (버전은 preset/plugins.json 에 고정)
lib/commandcentercmd.sh  우리 Obsidian 플러그인 설치·활성화
plugin/               그 플러그인 소스 — 빌드 없음, 이 파일이 곧 배포물 (ADR 0002)
lib/init/             init 의 단계 5개
lib/gen/*.py          생성기 — 셸이 못 하는 것만
lib/migrations/       설정 스키마 마이그레이션

preset/               데이터. 코드가 아니다
templates/            사용자 머신에 렌더링될 것
skills/               AI 스킬 12종
app/                  macOS 메뉴바 앱 (Swift)
tests/                검사
```

---

## 계층과 의존 방향

의존은 **한 방향으로만** 흐른다.

```
bin/devtrail
    ↓                 라우터는 lib/ 를 부른다
lib/*cmd.sh           명령. 서로를 부르지 않는다(예외 아래)
    ↓
lib/merge/  lib/gen/  lib/init/    일꾼. 옆을 부르지 않는다
    ↓
lib/common.sh + lib/journal.sh     토대. 위를 모른다
    ↓
preset/  templates/                데이터. 실행되지 않는다
```

### 실제로 이런가 (측정값)

`tests/run.sh` 가 이 규칙 전부를 강제하지는 않는다. 아래는 현재 사실이다.

| 규칙 | 상태 |
|---|---|
| `preset/`·`skills/` 에 셸 스크립트 없음 | ✅ 0개 |
| 병합기 9종이 서로를 부르지 않음 | ✅ 각자 자기 진입점만 정의 |
| `lib/common.sh` 가 명령을 모름 | ✅ `journal.sh` 만 부른다 |

### 인정된 예외

문서화하지 않으면 다음 사람이 "왜 여기만 다르지" 로 시간을 쓴다.

| 예외 | 왜 |
|---|---|
| `lib/init/write.sh` → `augmentcmd.sh` · `skillcmd.sh` | init 은 '전체 셋업'이라 다른 명령을 단계로 실행한다 |
| `lib/merge/hotkeys.sh` → `pathcmd.sh` | 경로 해석의 단일 출처를 쓰기 위해 |
| `lib/augmentcmd.sh` → `pathcmd.sh` | 같은 이유 |
| `lib/dashboard.sh` → `bin/devtrail` 경로 전달 | **UI 는 로직을 갖지 않는다.** 웹 UI 는 CLI 를 호출할 뿐이다 |
| `lib/updatecmd.sh` → `bin/devtrail` chmod | 갱신 후 실행권한 복구 |

---

## 어디에 넣을 것인가

| 만들려는 것 | 위치 | 진입점 이름 |
|---|---|---|
| 새 CLI 명령 | `lib/<이름>cmd.sh` | `<이름>_cmd()` |
| Obsidian 설정을 건드리는 것 | `lib/merge/<대상>.sh` | `_ob_<대상>()` |
| init 의 새 단계 | `lib/init/<단계>.sh` | `_init_<단계>()` |
| Obsidian 플러그인 추가 | `preset/plugins.json` | — (태그 고정 필수) |
| 설정 스키마 변경 | `lib/migrations/NNN-<이름>.sh` | `_mg_NNN()` + `_mg_NNN_why` |
| 노트·JSON 을 생성하는 것 | `lib/gen/<이름>.py` | — |
| 폴더 구조·기본값 | `preset/` (JSON·Markdown) | — |
| AI 스킬 | `skills/<언어>/<이름>/SKILL.md` | — |

새 명령을 추가하면 `bin/devtrail` 의 `case` 와 `usage()` 두 곳을 고친다.

### 셸인가 파이썬인가

**셸이 기본이다.** 파이썬은 셸로 하면 읽기 어려워지는 것만 맡는다 —
YAML frontmatter 파싱, 볼트 전체 순회, Dataview 쿼리 생성.

`lib/gen/*.py` 는 전부 **stdin/argv 를 받아 stdout 으로 내는 필터**다.
설정 파일을 직접 읽거나 쓰지 않는다. 셸이 값을 골라 넘긴다.

---

## 지켜야 할 규칙

전부 **실제 사고에서 나온 것**이다. 검사가 있는 항목은 표시했다.

### 1. bash 3.2 에서 돌아야 한다 · `tests/run.sh guard`

macOS 기본 bash 는 3.2 다(GPLv3 때문에 Apple 이 올리지 않는다).

```bash
"$n개"     # ✗ 3.2 가 '개'의 첫 바이트를 변수명에 흡수 → unbound variable
"${n}개"   # ✓
```

`mapfile` · `declare -A` · `${var^^}` 도 쓸 수 없다.

이 함정은 **ubuntu 의 bash 5 에서 재현되지 않는다.** 그래서 CI 의 동작
테스트는 macOS 에서만 돈다.

### 2. 볼트 경로를 박지 않는다 · `tests/run.sh guard`

경로의 단일 출처는 `devtrail path` / `dt_dir()` 다. 설정의 `dirs.<key>` 가
`preset/tree.json` 기본값을 이긴다 — 이것이 **기존 볼트에 얹기**를 가능하게
하는 유일한 장치다.

- 템플릿은 Templater JS 라 셸을 못 부른다 → `_devtrail-paths.md` 를
  **파일명으로 찾아** 읽는다.
- 스킬은 실행 시점에 `devtrail path` 를 부른다.

### 3. 덮어쓰지 않는다. 병합한다

Obsidian 설정을 쓰기 전에 **반드시 `jr_backup`** 을 부른다. 백업이 실패하면
원본을 건드리지 않고 멈춘다.

`.bak` 을 파일 옆에 흩뿌리지 않는다 — 저널이 한 실행을 하나로 묶는다.

### 4. 되돌릴 수 있어야 한다

파일을 만들면 `jr_created`, 폴더를 만들면 `jr_mkdir` 를 쓴다.
`mkdir -p` 를 직접 부르면 중간 단계가 기록되지 않아 되돌린 뒤 빈 껍데기가
남는다.

`undo` 는 폴더를 `rmdir` 로만 지운다 — 사용자 노트가 하나라도 있으면
실패하고 남겨둔다. 그리고 **남겨뒀다고 반드시 말한다.**

### 5. 기본은 dry-run

볼트를 바꾸는 명령은 무엇을 할지 먼저 보여준다. `--apply` 가 있어야 쓴다.
`augment` · `undo` · `update` · `config migrate` 전부 그렇다.

### 6. UI 에 로직을 넣지 않는다

웹 대시보드와 메뉴바 앱은 **CLI 를 호출할 뿐이다.** 같은 판단이 두 곳에
있으면 반드시 갈라진다.

### 7. 기본값은 한 곳에만

`devtrail config effective` 가 '실제로 적용되는 값'의 단일 출처다.
코드 곳곳에 `${x:-기본값}` 을 흩뿌리면 무엇이 진짜인지 알 수 없다.

### 8. `jq //` 를 boolean·빈 값에 쓰지 않는다

`//` 는 `false` 와 빈 배열도 기본값으로 덮어쓴다. 키의 존재를 물으려면
`has()` 를 쓴다.

### 9. `insert_block` 마커는 정확히 한 쌍일 때만 교체한다

마커가 없거나 여러 쌍이면 손대지 않는다. 사용자가 템플릿을 복사해 두
개가 됐을 때 엉뚱한 곳을 덮어쓴다.

### 10. 파일 길이 · `tests/run.sh guard`

**400줄 경고 · 600줄 실패.** 넘으면 역할로 쪼갠다.

한 파일이 길다는 것은 대개 두 가지를 하고 있다는 뜻이다. `obsidian.sh`
(440→62) 와 `init.sh` (553→63) 가 실제로 그랬다.

---

## 데이터가 사는 곳

### 저장소 (읽기 전용)

| 경로 | 내용 |
|---|---|
| `preset/tree.json` | 폴더 정의 25개 (+ 하위 10) · 모듈 6개 |
| `preset/project-skeleton.json` | 프로젝트 폴더 **안**의 구조 — `tree.json` 과 층이 다르다 |
| `preset/profiles/*.json` | 설치 모드 3종 (`new`·`existing`·`isolated`) |
| `preset/templates/` | Obsidian 노트 템플릿 22종 + 공용 JS 헤더 |
| `preset/obsidian/` | 플러그인 설정 기본값 |
| `preset/guides/`·`learn/` | 사용자 볼트에 복사될 문서 |

### 사용자 머신 (`~/.devtrail/`)

| 경로 | 내용 |
|---|---|
| `devtrail.config.json` | 설정. 스키마 버전을 갖는다 |
| `journal/<작업ID>/` | 변경 저널 — `meta.json`·`entries.tsv`·`files/` |
| `scripts/` | 템플릿에서 렌더링된 실행 스크립트 |
| `logs/` | 자동 실행 로그 |
| `vault-backup/` | 볼트 백업 저장소 |
| `src/` | 설치된 저장소 (`install.sh` 가 git clone) |

### 사용자 볼트

DevTrail 은 **사용자가 정한 루트 아래에만** 쓴다. 루트 이름은 설정의
`vault.root` 이고, 비어 있으면 볼트 최상위다.

---

## 설치 모드 — 코드가 아니라 데이터

신규 사용자와 기존 사용자는 **같은 코드 경로**를 탄다. 빈 볼트는 기존
볼트의 특수한 경우일 뿐이다.

차이는 `preset/profiles/*.json` 에 산다:

| | `new` | `existing` | `isolated` |
|---|---|---|---|
| 폴더 범위 | 전체 | 고른 모듈만 | 전체 (새 루트 아래) |
| 자동 이동 | `Automatic` | **`Manual`** | `Automatic` |
| 남의 폴더 제외 | 아니오 | **예** | 예 |
| Linter 병합 | 예 | **아니오** | **아니오** |
| `app.json` | 전체 | **안전 키만** | **안전 키만** |
| Templater | 전체 | **충돌 없는 것만** | 전체 |
| 데일리노트 | 적용 | **확인 후** | **확인 후** |

`existing` 이 Linter 를 건드리지 않는 이유: `lintOnSave` 를 쓰는 볼트에
우리 규칙을 넣으면 **저장할 때마다 기존 노트의 서식이 바뀐다.**

분기를 코드로 쓰면 세 번째 모드를 추가할 때 아홉 곳을 고쳐야 한다.

---

## 검사

로컬과 CI 가 **같은 스크립트**를 부른다.

```bash
./tests/run.sh          전부 (swift 빌드 포함)
./tests/run.sh fast     swift 빼고
./tests/run.sh lint     문법·JSON·파이썬       (CI: ubuntu)
./tests/run.sh guard    저장소 고유의 함정      (CI: ubuntu)
```

| 그룹 | 무엇 |
|---|---|
| `lint` | 셸 문법 · 파이썬 컴파일 · JSON 유효성 |
| `guard` | bash 3.2 · 경로 하드코딩 · 파일 길이 · 버전 · 스키마 · 시크릿 · 스킬 규약 |
| 동작 | `path` 13 · `augment` 28 · `scan` 15 · `undo` 27 |

### 테스트가 존재한다 ≠ 테스트가 무언가를 지킨다

차단성 결함을 고쳤으면 **변이를 주입해 검사가 빨간불이 되는지 확인한다.**
이때 변이가 실제로 코드를 바꿨는지 먼저 봐야 한다 — 정규식이 대상을 못
찾아 아무것도 안 바꿨는데 "생존"으로 보인 사례가 있었다.

`check_bash32` 는 자기 정규식을 먼저 시험한다. `[가-힣]` 범위는 로케일을
타서, 안 맞는 환경에서는 '통과'로 보이면서 아무것도 안 본다.
**거짓 초록불이 검사 없음보다 나쁘다.**

---

## 관련 문서

- [design-tokens.md](./design-tokens.md) — 다섯 표면의 색·타이포 단일 출처
- [../CHANGELOG.md](../CHANGELOG.md) — 버전 규칙과 릴리스 절차
- [decisions/](./decisions/) — 장기 확정 결정 (ADR)
