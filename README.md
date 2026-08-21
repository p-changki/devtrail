# DevTrail

[![CI](https://github.com/p-changki/devtrail/actions/workflows/ci.yml/badge.svg)](https://github.com/p-changki/devtrail/actions/workflows/ci.yml)

***한국어** · [English](README.en.md)*

> 개발 기록용 **Obsidian 볼트 한 벌**을 만들어 주는 CLI.
> 폴더 구조 · 노트 템플릿 · 자동 분류 · GitHub 활동 수집 · AI 스킬까지 한 번에.

손으로 쓰지 않아도 기록이 쌓이고, 쌓인 것이 주간리뷰로 굴러 올라갑니다.

> **언어**: 한국어가 기본이고 영어를 함께 지원합니다. `init` 이 가장 먼저
> 언어를 묻고, 폴더 이름과 볼트 내용이 그에 맞춰 만들어집니다.
> 영어 지원 범위는 [README.en.md](README.en.md) 를 보세요.
>
> **플랫폼**: macOS. Linux 는 아직 시험해보지 않았습니다.

---

## 30초 요약

```bash
curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash

devtrail init        # 이거 하나면 끝납니다
                     #   1) 언어 — 한국어 / English
                     #   2) 볼트 — Obsidian 이 아는 볼트 목록에서 고르거나 새로 만들기
                     #   3) 설치 방식 — 기존 볼트에 얹기 / 새로 시작 / 분리 설치
                     #   4) 루트 폴더 이름 · 모듈 · GitHub · AI
                     # → 플러그인 4개 설치 · 설정 병합 · Obsidian 실행까지 자동
devtrail doctor      # 뭐가 안 되는지 정확히 알려줍니다
```

`init` 이 Obsidian 플러그인 4개를 **버전을 고정해** 내려받아 넣고, 설정을
병합한 뒤, 볼트를 열어 줍니다. 터미널과 Obsidian 을 오갈 일이 없습니다.
설치 전에 무엇을 어디서 받는지 화면에 띄우고 동의를 받습니다.

> 사용자가 직접 해야 하는 것은 하나입니다 — Obsidian 이 "커뮤니티 플러그인을
> 신뢰하시겠습니까?" 라고 물으면 허용하는 것. 서드파티 코드에 대한 Obsidian 의
> 보안 확인이라 우회하지 않습니다.
>
> 볼트를 직접 만지고 싶으면 `devtrail init --no-bootstrap` 으로 설정만 만들고
> `devtrail obsidian` 을 나중에 실행할 수 있습니다.

이미 쓰던 볼트가 있어도 됩니다. `init` 이 먼저 진단하고 **기존 폴더를 그대로
쓰는 쪽**을 제안합니다. 이미 깔려 있는 플러그인은 건드리지 않습니다.

---

## 무엇이 생기나

`init` 에서 정한 루트(예: `창기/`) 아래에 이런 트리가 생깁니다.

```
창기/
├── 대시보드.md            오늘·이번 주가 한눈에
├── 일일 체크인.md
├── 개발/
│   ├── 개발일지/          날짜별. GitHub 활동이 자동으로 들어옵니다
│   ├── 개발메모/
│   │   ├── Frontend/  Backend/  DevOps/  Infra/  Testing/  General/
│   ├── 트러블슈팅/  아이디어/  유튜브/  라이브러리/  도구/  AI/  투두/
│   ├── 주간리뷰/  월간리뷰/  회고/    회고는 주간·월간·분기·프로젝트로 나뉩니다
│   ├── 프로젝트/          레포별 docs 골격
│   ├── 레포docs/          `devtrail sync` 가 프로젝트 문서를 끌어옵니다
│   └── 학습/
├── 자료실/
│   ├── 00_Inbox/          일단 담는 곳
│   ├── 10_원본/           첨부 · 원본 파일
│   ├── 20_카드노트/        승격된 것만. MOC 포함
│   └── 30_아카이브/
├── 템플릿/                노트 템플릿 22종
└── 가이드/                시작하기 · 폴더와 태그 · 단축키 · 늘려 쓰기
```

**폴더마다 `_index.md` 허브**가 있어서, 그 폴더의 노트만 모아 보여줍니다.

노트를 만들면 태그에 따라 **자동으로 제자리를 찾아갑니다.**
`#type/dev-note/frontend` 를 붙이면 `개발메모/Frontend/` 로 갑니다.

### 모듈 — 필요한 것만

| 모듈 | 무엇 | 기본 |
|---|---|---|
| `devlog` | 개발일지 + GitHub 활동 | **필수** |
| `review` | 주간 · 월간 리뷰 | 켬 |
| `project` | 프로젝트 구조 + docs 골격 | 켬 |
| `pkm` | 자료실 · 카드노트 · MOC | 켬 |
| `learn` | 학습 시스템 | 켬 |
| `personal` | 개인 (일기 · 책 · 스크랩) | 꺼짐 |

나중에 추가할 수 있습니다: `devtrail augment personal --apply`

---

## 이미 볼트를 쓰고 계시다면

가장 걱정되는 부분일 겁니다. **노트를 움직이지 않습니다.**

`devtrail scan` 이 먼저 진단합니다 — 쓰기는 하지 않습니다.

```
볼트
  노트   1727개 · 폴더 84개
  메타   frontmatter 41%

폴더 역할 추론
  devlog    확신 0.92   312개  Daily
  ...

제안
✅ 기존 볼트에 얹기 — 노트 1727개가 있습니다
   기존 폴더를 그대로 쓰고 설정만 매핑합니다. 노트를 움직이지 않습니다.
```

폴더 **이름**이 아니라 내용의 형태로 역할을 추론합니다. 확정은 사용자가 합니다.
`Daily/` 를 개발일지로 매핑하면, DevTrail 은 그 폴더를 씁니다 —
`개발/개발일지` 를 새로 만들어 평행 구조를 만들지 않습니다.

### 설치 모드 3가지

| | 언제 | 자동 이동 | 기존 설정 |
|---|---|---|---|
| **새로 시작** | 빈 볼트 | 켬 | — |
| **기존에 얹기** | 이미 쓰던 볼트 | **Manual** | 서식 규칙을 건드리지 않음 |
| **분리 설치** | 가장 안전 | 우리 트리 안에서만 | 건드리지 않음 |

**분리 설치**는 새 하위 트리에만 넣습니다. 마음에 안 들면 폴더째 지우면 끝입니다.

---

## 안전 계약

남의 볼트를 건드리는 도구라서, 이게 기능보다 먼저입니다.

**1. 덮어쓰지 않고 병합합니다.**
Obsidian 설정을 쓰기 전에 반드시 백업합니다. 백업이 실패하면 **원본을
건드리지 않고 멈춥니다.** 기존 단축키 · 자동 이동 규칙 · 태그는 보존됩니다.

**2. 기본이 dry-run 입니다.**
볼트를 바꾸는 명령은 무엇을 할지 먼저 보여줍니다. `--apply` 가 있어야 씁니다.

**3. 되돌릴 수 있습니다.**

```bash
devtrail undo                    # 변경 이력
devtrail undo <ID>               # 무엇을 되돌릴지 확인 (아무것도 바꾸지 않음)
devtrail undo <ID> --apply
```

폴더는 **비어 있을 때만** 지웁니다. 안에 노트를 넣으셨으면 남겨두고,
남겨뒀다고 말합니다.

**4. 다시 실행해도 안전합니다.**
`augment` 는 **없는 것만** 만듭니다. 고쳐 쓰신 노트는 그대로 둡니다.

---

## 명령

### 설치 · 진단

```bash
devtrail init              대화형 셋업
devtrail scan [경로]        볼트 진단 — 구조 · 메타 · 충돌 (쓰기 없음)
devtrail doctor            의존성 · 인증 · 권한 · 자동화 상태
devtrail obsidian          Obsidian 설정 병합
devtrail plugins <sub>     Obsidian 플러그인 (install|status)
devtrail setup <sub>       비대화형 셋업 (plan|apply|status) — 앱·CI 용
devtrail augment [모듈]     없는 폴더 · 허브만 생성
devtrail project <하위>     프로젝트 등록 (add|list)
devtrail template <하위>    노트 템플릿 (list|diff|update)
devtrail skills <하위>      AI 스킬 설치 (install|sync|list|remove)
```

### 기록

```bash
devtrail activity [날짜]    GitHub 이슈/PR 을 개발일지에 삽입
devtrail summary  [날짜]    머지된 PR 을 AI 로 쉬운말 요약
devtrail weekly            이번 주 주간리뷰 초안
devtrail backfill [날짜]    지난 날짜를 채워 넣기
devtrail sync              프로젝트 docs → 볼트
```

### 프로젝트

```bash
devtrail project add my-app              # 등록 + docs 골격 생성
devtrail project add acme-fe --section acme   # 여러 레포를 한 섹션에
devtrail project list                    # 등록된 것 보기
```

`⌘⇧P` 로 만든 프로젝트도 여기서 등록해야 개발일지·개발메모의 선택창에
나타납니다. Templater 는 셸을 부를 수 없어 자동화할 수 없습니다.

### 관리

```bash
devtrail update            DevTrail 자체를 최신으로
devtrail undo [ID]         되돌리기
devtrail config [get|set]  설정
devtrail path [키]          볼트 경로 조회
devtrail app <하위>         메뉴바 앱 (install|start|stop|status|uninstall)
devtrail dashboard         웹 대시보드
devtrail install-schedule  자동 실행 등록
devtrail uninstall         자동화 제거 (볼트는 건드리지 않음)
```

---

## AI 스킬 12종

Claude Code 같은 AI 도구에서 쓰는 스킬을 함께 설치합니다.
`devtrail skills install` 로 넣고, 스킬은 실행 시점에 `devtrail path` 를 불러
**사용자의 실제 폴더 이름**을 찾습니다.

| | |
|---|---|
| `youtube` | 자막을 뽑아 정리하고 볼트에 저장 |
| `web-capture` | 웹 페이지를 마크다운으로 Inbox 에 |
| `promote` | Inbox → 카드노트 승격 (3항목 검증) |
| `moc` | 흩어진 노트를 주제로 묶기 |
| `rollup` | 개발일지 → 주간 → 월간 |
| `worklog` | 작업 하나 = 폴더 하나 |
| `docs` | 프로젝트 문서를 올바른 위치에 |
| `pdca` | 계획·설계·분석·보고 |
| `qa-check` | 재현 가능한 QA 체크리스트 |
| `refcard` | 라이브러리 레퍼런스 카드 |
| `study-log` | 학습 진도 기록 |
| `vault-health` | Inbox 적체 · 고아 노트 · 깨진 링크 |

DevTrail 은 **AI 도구를 요구하지 않습니다.** 스킬은 선택입니다.

---

## 요구사항

| | |
|---|---|
| **필수** | macOS · `bash` · `git` · `jq` · `python3` |
| **Obsidian 플러그인 4종** | Shell commands · Templater · Dataview · Auto Note Mover |
| **권장** | Calendar · Omnisearch · Linter · Homepage |
| **GitHub 활동** | `gh` (`brew install gh && gh auth login`) |
| **AI 요약** | Claude 또는 OpenAI (선택) |

플러그인은 **직접 재구현하지 않습니다.** 설치를 안내하고, 활성화되면 설정을
병합해 드립니다. `devtrail doctor` 가 무엇이 빠졌는지 알려줍니다.

---

## `doctor` 를 먼저 보세요

무언가 안 될 때 추측하지 않아도 됩니다.

```
$ devtrail doctor

의존성
✅ jq   ✅ gh   ✅ git   ✅ rsync

Obsidian
❌ 필수 플러그인 누락: dataview
⚠️  alwaysUpdateLinks 가 꺼져 있습니다 — 노트를 옮기면 링크가 끊깁니다
```

무엇이 문제인지와 **어떻게 고치는지**를 같이 냅니다.

---

## 저장소 위치

| | |
|---|---|
| 설치본 | `~/.devtrail/src/` |
| 설정 | `~/.devtrail/devtrail.config.json` |
| 변경 저널 | `~/.devtrail/journal/` |
| 볼트 | 직접 정하신 곳 |

`devtrail uninstall` 은 자동화(launchd)만 제거합니다. **노트는 건드리지 않습니다.**
메뉴바 앱은 `devtrail app uninstall` 로 따로 지웁니다.

---

## 현재 상태 (v0.3)

**되는 것** — 볼트 구조 생성 · 기존 볼트에 얹기 · 모드 3종 · 노트 템플릿 22종
· 폴더별 허브 · 자동 분류 · GitHub 활동/PR 요약 · 주간리뷰 · AI 스킬 12종 ·
되돌리기 · 메뉴바 앱 · 웹 대시보드

**프로젝트 관계 (v0.3)** — `devtrail project add` 로 등록하면 개발일지 ·
개발메모 · 워크로그 · 트러블슈팅이 전부 `#project/<키>` 로 이어지고,
프로젝트 README 가 그것들을 볼트 전체에서 모읍니다.

**언어** — 한국어 · English 둘 다 완전 지원. 폴더 이름 · 템플릿 · 가이드 ·
CLI 출력 · AI 스킬 전부. 태그와 frontmatter 키는 양쪽이 같아서 자동 분류와
Dataview 쿼리는 언어를 타지 않습니다.

**아직인 것** — Linux · Windows · GitHub 외 다른 호스팅 ·
Obsidian 외 다른 노트 앱

**시험 중** — 실제 볼트에서의 장기 사용. 버그를 만나시면
[이슈](https://github.com/p-changki/devtrail/issues)로 알려주세요.
`devtrail doctor` 와 `devtrail scan` 출력이 있으면 훨씬 빨리 고칩니다.

---

## 기여

[CONTRIBUTING.md](CONTRIBUTING.md) · [아키텍처](docs/ARCHITECTURE.md) ·
[디자인 토큰](docs/design-tokens.md) · [변경 이력](CHANGELOG.md)

```bash
./tests/run.sh        # 커밋 전에 이걸 돌립니다
```

⚠️ macOS 기본 bash 는 **3.2** 입니다. `"$n개"` 는 죽습니다 — `"${n}개"` 로 씁니다.

---

## 라이선스

[MIT](LICENSE)
