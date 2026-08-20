# DevTrail

[![CI](https://github.com/p-changki/devtrail/actions/workflows/ci.yml/badge.svg)](https://github.com/p-changki/devtrail/actions/workflows/ci.yml)

> 개발 기록을 **자동으로 남기는** 환경을 한 번에 셋업하는 CLI.
> GitHub 활동 → Obsidian 개발일지 → 주간리뷰까지, 손으로 쓰지 않아도 쌓입니다.

```bash
curl -fsSL https://raw.githubusercontent.com/p-changki/devtrail/main/install.sh | bash

devtrail init      # 대화형 셋업
# → Obsidian에서 볼트를 열고 플러그인 3개 설치 후 재시작
devtrail obsidian  # 셸커맨드 병합 · 노트 템플릿 설치
devtrail doctor    # 진단 — 뭐가 안 되는지 정확히 알려줍니다
```

> ⚠️ **순서가 중요합니다.** `devtrail obsidian` 은 볼트의
> `.obsidian/plugins/obsidian-shellcommands/data.json` 을 읽습니다.
> 볼트를 한 번도 열지 않았거나 플러그인이 없으면 **셸커맨드 병합을 건너뜁니다.**

---

## 무엇을 해결하나

개발 기록을 남기려는 시도는 보통 이렇게 실패합니다.

| 방식 | 실패하는 이유 |
|---|---|
| 노션에 매일 수기 작성 | 3일 하고 멈춤 |
| 프로젝트마다 `NOTES.md` | 흩어져서 나중에 못 찾음 |
| 커밋 메시지로 대체 | 나중에 읽으면 무슨 말인지 모름 |

DevTrail은 **이미 남긴 흔적**(PR·이슈·커밋)을 긁어와 노트에 자동으로 꽂아넣습니다.
쓰는 게 아니라 **쌓이는** 구조입니다.

## 무엇을 설치하나

```
devtrail init
  ├─ ~/.devtrail/devtrail.config.json   설정 (모든 값의 단일 출처)
  ├─ ~/.devtrail/scripts/*.sh           설정을 읽어 동작하는 스크립트
  ├─ ~/Library/LaunchAgents/*.plist     자동 실행 (macOS)
  └─ <볼트>/.obsidian/                  Obsidian 프리셋 (선택)
```

## 명령어

| 명령 | 하는 일 |
|---|---|
| `devtrail init` | 대화형 셋업 (저장소·볼트·GitHub·AI) |
| `devtrail doctor` | 의존성·인증·권한·자동화 상태 진단 |
| `devtrail obsidian` | Obsidian 설정 적용 (**병합** — 기존 설정 보존) |
| `devtrail app <sub>` | 메뉴바 앱 (install·start·stop·status) |
| `devtrail dashboard` | 로컬 웹 대시보드 (상태·실행·설정) |
| `devtrail install-schedule` | launchd 자동 실행 등록 |
| `devtrail activity [DATE]` | GitHub 이슈/PR을 개발일지에 삽입 |
| `devtrail summary [DATE]` | 머지된 PR을 AI로 쉬운말 요약 |
| `devtrail weekly` | 주간리뷰 초안 생성 |
| `devtrail backfill [DATE]` | 지난 날짜의 활동·요약을 채워 넣기 |
| `devtrail sync` | 레포 docs → 볼트 동기화 |
| `devtrail config [get\|set]` | 설정 조회/변경 (메뉴바 앱·대시보드가 이 명령을 씁니다) |
| `devtrail uninstall` | 자동화 제거 (**볼트 데이터는 건드리지 않음**) |

### 남의 설정을 덮어쓰지 않습니다

이 도구가 줄 수 있는 최악의 피해는 **기존 Obsidian 설정과 노트를 날리는 것**입니다. 그래서:

| 대상 | 방식 |
|---|---|
| Obsidian 셸 커맨드 | id 기준 **병합** — 기존 커맨드·다른 설정 키 그대로 |
| 노트 템플릿 | **없을 때만** 생성 |
| 단축키·Templater 폴더매핑 | 손대지 않고 **안내만** |
| 개발일지 삽입 | 마커가 정확히 한 쌍일 때만 교체. 아니면 **아무것도 바꾸지 않음** |
| 레포 docs 동기화 | 볼트에서 더 새로 고친 파일은 건너뜀 + 덮어쓸 땐 백업 |

### `doctor`가 이 도구의 핵심입니다

자동화의 가장 큰 문제는 **"도는지 안 도는지 모른다"**는 것입니다.

```
의존성
✅ jq   ✅ gh   ✅ git   ⚠️ fswatch 없음 (선택)
인증
✅ gh 인증됨 (yourname)
자동화
❌ com.devtrail.daily 로드됐으나 마지막 종료코드 1 — 로그: ~/.devtrail/logs/...
```

> **확인하지 못한 것을 "정상"이라고 말하지 않습니다.**
> 예를 들어 launchd의 iCloud 접근 권한은 대화형 셸에서 검증이 불가능합니다.
> 그럴 땐 통과 처리하지 않고 **확인 방법을 알려줍니다.**

## 요구사항

**필수** — macOS · [Obsidian](https://obsidian.md) · `gh` · `jq` · `git` · `rsync` · `python3`

```bash
brew install gh jq fswatch
gh auth login
```

**선택** — `fswatch`(실시간 감시) · AI CLI(`claude` 등, PR 요약용) · Linear API 키
· Xcode Command Line Tools(`swift` — 메뉴바 앱을 소스에서 빌드할 때만)

**Obsidian 플러그인 3개(필수)** — Shell commands · Templater · **Dataview**

| 플러그인 | 왜 필요한가 |
|---|---|
| Shell commands | Obsidian에서 DevTrail 스크립트를 실행하는 통로 |
| Templater | 개발일지를 템플릿으로 생성 — 활동 삽입의 전제 |
| Dataview | 주간리뷰 노트는 본문 전체가 Dataview 쿼리입니다 |

## 저장소 위치

`init`에서 선택합니다.

| 백엔드 | 상태 |
|---|---|
| 로컬 | ✅ 검증됨. 권한 문제 없음 |
| iCloud | ✅ 검증됨. **전체 디스크 접근 권한 필요** (아래 참고) |
| Google Drive | ⚠️ 미검증 — 스트리밍 모드면 파일이 로컬에 없을 수 있음 |

> **iCloud 주의**: launchd에서 iCloud에 접근하려면 전체 디스크 접근 권한이 필요합니다.
> 또한 `git` 바이너리는 iCloud 직접 접근이 막혀 있어, 백업은 `python3`을 경유합니다.
> 이건 우회가 아니라 **필수**입니다 — 모르면 백업이 조용히 실패합니다.

## 현재 지원 범위 (v0.1 MVP)

솔직하게 적습니다. 안 되는 걸 된다고 하지 않습니다.

| 항목 | 상태 |
|---|---|
| macOS | ✅ |
| Linux · Windows | ❌ 미지원 (launchd 의존). 어댑터 자리만 있음 |
| AI: `claude` | ✅ 검증됨 |
| AI: `codex` · `gemini` | ⚠️ 어댑터 자리만 — 미구현 |
| Obsidian 셸커맨드·템플릿 | ✅ 병합 설치 |
| 메뉴바 앱 (macOS) | ✅ |
| 웹 대시보드 | ✅ `devtrail dashboard` (127.0.0.1 전용 · 실행마다 토큰 발급) |
| Obsidian 노트 템플릿 | ⚠️ 개발일지 1종만. 주간리뷰는 `weekly` 명령이 직접 생성 |

## 기여

```bash
./tests/scan-secrets.sh    # 커밋 전 필수 — 시크릿·개인경로 검사
bash -n lib/*.sh           # 문법 검사
```

> ⚠️ 이 저장소는 특정인의 실사용 세팅에서 추출됐습니다.
> 개인 경로(`/Users/이름/`)나 API 키가 섞이기 쉬우니 **스캐너를 반드시 통과**시켜 주세요.
> macOS 기본 bash는 **3.2**입니다. `mapfile`·`declare -A` 등 bash 4 기능은 쓰지 마세요.

## 라이선스

MIT

---

## 기여하기

- [아키텍처](docs/ARCHITECTURE.md) — 계층 · 어디에 무엇을 넣는가 · 지켜야 할 규칙
- [디자인 토큰](docs/design-tokens.md) — 색 · 타이포의 단일 출처
- [변경 이력](CHANGELOG.md) — 버전 규칙과 릴리스 절차

```bash
./tests/run.sh        # 커밋 전에 이걸 돌린다
```

⚠️ macOS 기본 bash 는 **3.2** 다. `"$n개"` 는 죽는다 — `"${n}개"` 로 쓴다.
