# 0006 부록 — DMG 배포 아키텍처

> [ADR 0006](./0006-dmg-distribution.md) 의 상세 설계. **제안 상태**이며
> 구현을 시작하지 않는다.

## 1. 지금 무엇이 어디에 있나

```
사용자 Mac
├── ~/.devtrail/
│   ├── devtrail.config.json     설정 (볼트 경로·언어·GitHub 계정)
│   └── journal/<작업ID>/         되돌리기 기록
├── <저장소>/                     ← git clone 한 것
│   ├── bin/devtrail             CLI 진입점 (bash)
│   ├── lib/*.sh                 10,992줄 — jq 247회
│   ├── lib/**/*.py              1,827줄 — 설정·허브 생성, 볼트 진단
│   ├── plugin/                  Obsidian 플러그인 (2,157줄, files.json 이 정본)
│   ├── templates/               볼트 템플릿
│   └── app/                     Swift 메뉴바 앱 (1,367줄, macOS 14+)
└── <볼트>/
    ├── .obsidian/plugins/devtrail-command-center/   ← 배포 대상
    └── notes/…                                       ← 사용자 것. 건드리지 않는다
```

**저장소가 런타임 자산이다.** 사용자는 clone 한 디렉터리를 지워선 안 된다 —
`bin/devtrail` 이 거기 있고, 플러그인 원본도 거기 있다. 비개발자에게 이 사실은
설명할 수 없다.

## 2. 목표 구조

```
/Applications/DevTrail.app/
└── Contents/
    ├── MacOS/DevTrail              메뉴바 앱 + 온보딩 UI (Swift)
    ├── Resources/
    │   ├── cli/                    bin/devtrail + lib/*.sh  (그대로 이사)
    │   ├── plugin/                 files.json 이 정본 (그대로)
    │   ├── templates/              볼트 템플릿 (그대로)
    │   └── release.json            릴리즈 매니페스트 (신규)
    └── Helpers/devtrail-helper     python3 를 대체하는 Swift 바이너리 (신규)
```

사용자 데이터의 위치는 **바뀌지 않는다**: `~/.devtrail/`, 볼트, 저널 그대로.
즉 기존 CLI 사용자와 앱 사용자가 **같은 설정을 공유**한다.

## 3. `python3` 를 어떻게 걷어내는가

### 대체 대상 — 8파일 1,827줄

| 파일 | 줄 | 하는 일 | Swift 로 옮길 때 |
|---|---:|---|---|
| `lib/gen/scan.py` | 384 | 볼트 진단 (쓰기 없음) | `FileManager` 순회 + frontmatter 파싱 |
| `lib/gen/hotkeys.py` | 303 | 단축키·Templater 폴더매핑·daily-notes 설정 생성 | `JSONSerialization` |
| `lib/gen/hubs.py` | 279 | L1 대시보드 · L2 영역 허브 마크다운 생성 | 문자열 조립 |
| `lib/snapshot.py` | 203 | 볼트 상태 → JSON (메뉴바용) | **이미 `Snapshot.swift` 존재** |
| `lib/gen/i18n.py` | 197 | 문구 | `Bundle` 리소스 |
| `lib/gen/anm.py` | 184 | Auto Note Mover 규칙 생성 | `JSONSerialization` |
| `lib/gen/hub.py` | 162 | L3 폴더 허브 생성 | 문자열 조립 |
| `lib/gen/smartenv.py` | 115 | Smart Connections 제외 설정 | 텍스트 생성 |

전부 **JSON 생성 · 텍스트 생성 · 파일 순회**다. Foundation 만으로 된다.
새 의존성이 필요 없다.

⚠️ `lib/gen/i18n.py` 는 **직접 호출되지 않는다** — hotkeys·hubs·hub 가
`import` 한다. 그래서 계약 테스트는 이 파일 단독이 아니라 **소비자를 통해**
세운다.

### 여기 없는 9번째 파일 — `templates/dashboard/server.py`

| | |
|---|---|
| 줄 | 280 |
| 무엇 | `devtrail dashboard` 가 띄우는 **로컬 HTTP 서버**. 화이트리스트 명령을 토큰으로 실행 |
| 왜 다른가 | 나머지 8개는 JSON·텍스트를 만들고 끝난다. 이건 서버 + 명령 실행이다 |
| 어디로 가나 | `templates/` 이므로 **사용자 볼트로 복사된다** |

Swift 이관 난이도가 다르고, **애초에 DMG 시대에 이 기능이 필요한지**가
먼저다. 메뉴바 앱과 Command Center 가 상태·실행·설정을 이미 다루는 것으로
보인다 — 겹치는 화면을 두 벌 유지하면 둘 다 낡는다.

**M1~M3 의 범위에 넣지 않는다.** D5 가 정해질 때까지 `devtrail dashboard` 는
`python3` 를 요구하는 채로 둔다 — 그리고 그 사실을 `doctor` 가 말하게 한다.

### 호출 규약 — shell 은 거의 그대로

```bash
# before
python3 "$DEVTRAIL_ROOT/lib/gen/hotkeys.py" templater --vault "$v"

# after
"$DT_HELPER" gen-hotkeys templater --vault "$v"
```

`DT_HELPER` 해석 순서:

1. `$DT_HELPER_OVERRIDE` (테스트용 — `DT_CC_SRC_OVERRIDE` 와 같은 방식)
2. `.app/Contents/Helpers/devtrail-helper`
3. 저장소의 빌드 산출물
4. **없으면 `python3` 로 폴백** ← 기존 Git 설치형 사용자가 아무것도 잃지 않는 이유

⚠️ 폴백을 조용히 하지 않는다. 어느 경로를 썼는지 `devtrail doctor` 가 말한다.

### M1 완료 — 9파일 중 8파일의 출력을 고정했다 (2026-08-23)

| 생성기 | 케이스 | 계약 모양 |
|---|---:|---|
| `smartenv` | 3 | argv → stdout |
| `anm` | 6 | argv → stdout (프로필 3종 · 병합 · LANG 없음) |
| `hotkeys` | 8 | argv → stdout (3모드 × ko/en · 병합 · LANG 없음) |
| `scan` | 2 | argv + **볼트** → stdout |
| `hub` | 2 | **환경변수** → stdout |
| `hubs` | 2 | argv + 볼트 → **디렉터리에 파일** |
| `snapshot` | 2 | argv(JSON 문자열) + 볼트 → stdout |
| `i18n` | — | 라이브러리. 위 소비자를 통해 시험된다 |
| ~~`server.py`~~ | — | **범위 밖** (D5) |

25 골든, `tests/test-gen-contract.sh` 34 단언.

#### 숨은 입력을 전부 못 박았다

`DEVTRAIL_LANG` · `LC_ALL` · `TZ` · `DT_DATE` · `DT_HUB_*` · **파일 mtime** ·
**시계**. 하나라도 새면 골든은 "이 기계에서, 오늘만" 맞는 파일이 된다.

#### 시계 이음새를 둬야 했다

`scan.py` 의 `role_candidates` 는 "최근에 손댔는가"로 점수를 곱하는데,
그 판정이 **현재 시각**에 걸린다. 실측:

```
DT_NOW=고정   → {"devlog": 0.45}
DT_NOW=먼미래 → {}                 ← 임계값 아래로 떨어져 역할이 사라진다
```

고정하지 않으면 이 골든은 **한 달 뒤 저절로 깨진다.** 그래서 `scan.py` 에
`DT_NOW`, `snapshot.py` 에 `cfg.now_ms` 를 뒀다. 둘 다 **미설정 시 예전
그대로**이고, 테스트가 그것도 단언한다 — 기본 동작을 바꿨다면 그건
이음새가 아니라 변경이다.

#### 변이 검증 9건

| 변이 | 결과 |
|---|---|
| `indent 2→4` · `ensure_ascii F→T` · 기본 언어 `ko→en` · 병합 대신 덮어쓰기 | ✗ ×4 |
| `scan`: recent 곱셈 제거 · `DT_NOW` 무시 | ✗ ×2 |
| `snapshot`: `now_ms` 무시 | ✗ |
| `hubs`: 날짜 주입 무시 | ✗ |
| `hub`: 제목 기본값 변경 | **생존 — 동등 변이** |

마지막 것은 테스트가 약해서가 아니라 **도달 불가**여서다. `hub.py` 를
부르는 곳은 `augmentcmd.sh` 하나뿐이고, 그 하나가 `DT_HUB_TITLE` 을 항상
넘긴다. 도달하지 않는 코드에 테스트를 붙이지 않는다 — 대신 근거를 테스트
파일에 적어 다음 사람이 다시 따지지 않게 했다.

### M2 시작 — smartenv 이관 완료 (2026-08-23)

첫 왕복을 증명했다. **가장 작은 생성기 하나**로 파이프라인 전체가 도는지
먼저 보고, 그다음 늘린다.

| | |
|---|---|
| 이관 | `smartenv` (115줄) → `SmartEnv.swift` |
| 결과 | 골든 3건 **바이트 동일** |
| 남음 | 22 케이스 (`anm` · `hotkeys` · `scan` · `hub` · `hubs` · `snapshot`) |

#### 가장 큰 난점은 로직이 아니라 **JSON 직렬화**였다

python 의 `dict` 는 **삽입 순서**를 지키고, 그 순서가 그대로 출력에 나온다.
실제 골든:

```json
{
  "smart_sources": { … },
  "other_key": "건드리면 안 된다",   ← 기존 파일의 순서 그대로
  "is_obsidian_vault": true          ← 나중에 붙은 것이 맨 끝
}
```

Foundation 의 `JSONSerialization` 은 순서를 보장하지 않고, `JSONEncoder` 의
`.sortedKeys` 는 알파벳순으로 **바꿔 버린다.** 둘 다 다른 파일을 만든다 —
사용자 설정 파일에서 "키 순서만 다름" 은 다름이다.

그래서 순서를 지키는 JSON 값·파서·writer 를 직접 뒀다
(`JSON.swift` · `JSONParser.swift`). **8개 생성기 전부의 토대**이고,
여기가 틀리면 전부 틀린다. python 의 `json.dumps(ensure_ascii=False,
indent=2)` 를 정확히 재현한다 — 한글은 그대로, 들여쓰기 2칸, `": "` 구분.

#### 게이트가 조용히 건너뛰지 않게 했다

`run.sh` 의 swift 단계는 `all` 에서만 돌고 release 를 만든다 — 일상
게이트(`fast`)에서는 헬퍼 대조가 **통째로 건너뛰어진다.** 그래서 계약
테스트가 **직접 빌드**한다 (소스가 더 새로우면 재빌드, 증분 1초 안팎).

**게이트가 있는데 안 도는 것은 게이트가 없는 것보다 나쁘다** — 있다고
믿게 되기 때문이다.

그리고 **아직 이관하지 않은 케이스를 세어서 말한다.** 침묵하면 "다 됐다"
로 읽힌다.

#### 변이 6/6 빨간불

`indent 2→4` · 키를 알파벳순으로 · 비ASCII 를 `\u` 로 · `setDefault` 가
덮어씀 · 공백 트림 제거 · 두 번 도는 순회를 한 번으로 합침.

마지막 둘은 로직 이관에서 실제로 틀리기 쉬운 자리다 — python 은
`no_index` 를 전부 훑은 **뒤** `personal` 을 훑는데, 한 번에 합치면
제외 폴더의 **순서**가 달라진다.

#### 곁들여 잡은 것 — 무효 픽스처

`smartenv` 의 병합 케이스가 **텍스트 파일**을 기존 설정으로 줬다.
`json.load` 가 실패해 `{}` 로 떨어졌고, 병합 가지를 한 번도 안 탔다 —
merge 골든이 new 골든과 **글자 하나까지 같았다.** 통과하는데 아무것도
안 지키는 케이스였다. JSON 픽스처로 고치자 순서·트림·`setdefault` 보존이
전부 드러났고, 그 덕에 위 변이 셋을 시험할 수 있게 됐다.

### M2 진행 — anm 이관 (2026-08-23)

| | |
|---|---|
| 이관 | `anm` (184줄) → `AutoNoteMover.swift` |
| 결과 | 골든 **9건** 바이트 동일 (기존 6 + 새 3) |
| 누적 | 이관 12건 · 남음 16건 |

#### ⚠️ 첫 변이에서 8건 중 **5건이 살아남았다**

골든은 통과하는데 그 경로를 **지나지 않았다.** 픽스처가 얇았다:

| 살아남은 변이 | 왜 |
|---|---|
| project 구체성 `-1 → 0` | `project_groups` 가 **비어 있어** project 규칙이 한 줄도 안 생겼다 |
| 기존 규칙을 덮어씀 | 기존 픽스처의 태그가 **남의 것**(`#keep`)뿐이라 "이미 라우팅 중" 가지가 안 돌았다 |
| wildcard 키를 거르지 않음 | 같은 이유 — `acme-*` 같은 키가 없었다 |
| 부모 제외를 자식에 전파 안 함 | `preset/tree.json` 의 `no_automove` 폴더에 **태그 달린 자식이 없다** |
| 안정 정렬을 불안정하게 | 프리셋에 **중복 태그가 없다** |

`anm` 은 **순서가 곧 계약**이다 — Auto Note Mover 는 첫 매칭에서 멈추므로
순서가 뒤집히면 사용자 노트가 엉뚱한 폴더로 이동한다(2026-08-22 실제 사고).
그 계약을 지키는 테스트가 절반은 헛돌고 있었다.

#### 픽스처를 보강했다

- `CFG_PROJ` — `project_groups` 에 실제 키 + wildcard(`acme-*`) + 한글 레포
- `EXIST_ANM_OURS` — **우리 태그**(`#type/devlog`)를 이미 다른 폴더로 라우팅 중
- `tests/fixtures/tree-edge.json` — 프리셋이 못 지나는 가지를 태우는 **합성 트리**:
  `no_automove` 부모 + 태그 달린 자식, 중복 태그, 슬래시 없는 태그

마지막 항목은 두 번 고쳐야 했다. `flat` 하나로는 부족했다 — 알파벳순으로도
`project/…` 보다 앞이라 구체성 `-1` 을 `0` 으로 바꿔도 순서가 같았다.
`project` **뒤로** 정렬되는 `zflat` 을 더하고 나서야 구별됐다.

**변이 8/8 빨간불.**

#### python 과 다른 자리를 한 곳에 모았다 (`PythonCompat.swift`)

| Swift 기본 | python | 왜 문제인가 |
|---|---|---|
| `String <` (정규화 비교) | 코드포인트 순 | 태그·레포명이 사용자 설정에서 온다. 한글 레포에서 갈릴 수 있다 |
| `sort` (불안정) | `list.sort` (안정) | 키가 같은 항목의 순서가 뒤집히면 다른 출력이다 |

### M2 진행 — hotkeys 이관 (2026-08-23)

| | |
|---|---|
| 이관 | `hotkeys` (303줄) → `Hotkeys.swift` + `Templater.swift` |
| 결과 | 골든 **16건** 바이트 동일 |
| 누적 | 이관 **29건** · 남음 8건 |

#### ⚠️ 픽스처가 또 얇았다 — 이번엔 **모양이 틀렸다**

`hotkeys.py` 는 `paths_json["paths"]` 를 읽는다 (`augmentcmd.sh` 가
`jq '{paths: …}'` 로 감싸서 넘긴다). 픽스처는 래퍼 **없이** 줬다.

⇒ 모든 폴더가 빈 값이 되어 `folder_templates` 가 **0개**로 나왔다.
골든은 통과했지만 **매핑 로직을 한 줄도 안 지났다.**

고친 뒤 5개 항목이 생겼고, 그제야 "매핑 순서" 와 "기존 매핑 보존" 변이가
잡혔다.

#### 첫 변이 9건 중 4건 생존 → 픽스처 보강 후 9/9

| 살아남았던 변이 | 왜 |
|---|---|
| `combo` 의 modifiers 정렬 제거 | 스펙의 modifiers 가 **이미 정렬돼 있어** 정렬이 무의미했다 |
| `place` 의 '유지' 가지 제거 | 기존 설정에 **우리 명령 ID** 가 없었다 |
| 기존 폴더 매핑을 덮어씀 | templater 케이스가 기존 설정을 **빈 것**으로 줬다 |
| 매핑 순서를 뒤집음 | 매핑되는 폴더가 **하나뿐**이라 순서가 안 보였다 |

보강: `paths` 래퍼 + 폴더 5개 · 정렬 안 된 modifiers 로 우리 조합을
점유하는 남의 명령 · 우리 명령이 이미 배정된 기존 설정 · 기존 폴더 매핑.

**여기서도 한 번 더 헛다리를 짚었다.** 점유 대상으로 개발일지(`D`)를
골랐는데, 그건 이미 우리 것이라 `place()` 가 combo 계산 **전에** return
했다 — 정렬 변이가 그대로 살아남았다. 개발메모(`M`)로 바꾸자 fallback
재배정(`Y`)이 일어나며 잡혔다.

#### 이 생성기가 지키는 것

`hotkeys` 는 **세 번의 실물 사고**가 만든 코드다:

- 정적 `hotkeys.json` 복사 → 볼트 루트가 다르면 단축키가 전부 죽음
- `enabled_templates_hotkeys` 미등록 → 명령이 아예 없는데 키만 배정 (⌘⇧D 무반응)
- Templater 2.x 키 변경 → 예전 키만 쓰면 자동 삽입이 통째로 꺼짐

셋 다 **에러 없이 조용히** 안 되는 종류다. 이관이 이 셋을 재현하는지
골든이 지킨다.

### M2 진행 — hub 이관 (2026-08-24)

| | |
|---|---|
| 이관 | `hub` (162줄) → `FolderHub.swift` |
| 결과 | 골든 **13건** 바이트 동일 |
| 누적 | 이관 **42건** · 남음 6건 |

이번엔 **순서를 뒤집었다.** 앞선 셋에서 매번 "골든은 통과하는데 경로를 안
지난다" 를 겪었으므로, 포팅 **전에** 어떤 갈래가 있는지부터 봤다.

`hub` 는 커버리지에 따라 쿼리가 세 갈래로 갈린다(full ≥50 · mixed 10~50 ·
fallback <10). 기존 골든은 커버리지를 안 넘겨 **fallback 하나만** 지났다.
경계값(50 / 49.9 / 10 / 9.9)과 파싱 실패까지 먼저 채우고 포팅했다.

#### ⚠️ 그래도 실제 이관 버그가 하나 나왔다 — 반올림

python 의 `round(x, 1)` 을 Swift 로 `(v * 10).rounded() / 10` 이라 옮겼다.
**두 가지가 어긋난다:**

1. Swift 의 `.rounded()` 는 half-away-from-zero, python 은 **half-to-even**
   (은행가 반올림)이다 — `round(0.25, 1)` → python `0.2` · Swift `0.3`
2. `× 10` 이 부동소수 오차를 만든다 — `33.35 * 10` 은 `333.49999999999994`
   라 333 으로 내려가지만, python 은 실제 double 값(`33.3500000000000014`)을
   보고 `33.4` 를 낸다

실측: 시험한 5개 값 중 **4개가 달랐다.** `String(format: "%.1f", v)` 는
C 의 정확한 십진 변환 + half-to-even 이라 8/8 일치한다.

**이 버그는 기존 골든이 잡지 못했다.** 픽스처 값이 전부 소수 1자리라
반올림 자체가 무의미했기 때문이다. 변이(`반올림 제거`)가 살아남아서 알았고,
그제야 경계값 케이스를 넣었다.

> 갈래를 먼저 세어도 **값의 성질**은 따로 봐야 한다. "어떤 분기가 있나" 와
> "그 분기 안에서 어떤 값이 위험한가" 는 다른 질문이다.

**변이 10/10 빨간불.**

### M2 진행 — snapshot 이관 (2026-08-24)

| | |
|---|---|
| 이관 | `snapshot` (203줄) → `VaultSnapshot.swift` |
| 결과 | 골든 **7건** 바이트 동일 |
| 누적 | 이관 **49건** · 남음 4건 (`scan` 2 · `hubs` 2) |

`snapshot` 은 **플러그인의 `collect()` 와 같은 답**을 내야 한다(ADR 0003).
한쪽만 틀어지면 메뉴바 앱과 Obsidian 화면이 다른 숫자를 보여준다.

#### 픽스처가 갈래를 **거의 하나도** 안 지났다

| | 값 |
|---|---|
| `next_actions` | **0** |
| `inbox` | **0** |
| `overdue` | **0** |
| `trouble` | **0** |
| `devlog_exists` | **false** — `open_tasks` 계산을 안 지남 |

볼트를 채웠다: next_action 있는 프로젝트 · **비활성** 프로젝트(세면 안 됨) ·
`created` 있는/없는 inbox · 기한 지난/안 지난 `review_at` · `trouble` 과
`troubleshooting` 두 이름 · 따옴표·들여쓴 키·콜론 없는 줄이 섞인 frontmatter ·
`_` 접두 파일 · 템플릿 폴더 안 파일 · 실제 체크박스가 있는 개발일지.

#### ⚠️ 모든 파일의 mtime 을 같게 못 박은 것이 **정렬을 안 보이게** 했다

`find -exec touch -t` 로 전부 같은 시각을 줬더니, inbox 정렬을 뒤집는 변이가
그대로 살아남았다. **순서가 계약인데 시험되지 않은 것이다.**

몇 개에 서로 다른 시각을 줘서 고쳤다. 골든의 결정성은 그대로 유지된다 —
값을 못 박되 **서로 다르게** 못 박는 것이 요점이다.

#### 그 밖에 드러난 것

- **들여쓴 키**: `meta:` 아래 `  status: inbox` 를 두니, 건너뛰기 로직을
  없앤 변이가 잡혔다. 리스트(`- a`)만으로는 부족했다 — 콜론이 없어 어차피
  건너뛰기 때문이다.
- **`recent` 의 10개 자르기**: `limit` 이 5·1 뿐이라 보이지 않았다.
  `limit: 20` 케이스를 넣자 잡혔다.
- **동등 변이 하나**: 볼트 없음 검사에서 `isDir` 만 뒤집었는데, 없는 경로는
  `fileExists` 에서 이미 걸려 결과가 같았다. 가드 전체를 통과시키도록
  변이를 고쳐 구별했다.

#### compact JSON

`snapshot.py` 는 `json.dump(..., ensure_ascii=False)` 로 **indent 없이** 낸다.
그때 python 의 구분자는 `(', ', ': ')` — **쉼표 뒤에 공백이 하나** 붙는다.
빼면 다른 파일이 된다. `pythonJSONCompact()` 를 따로 뒀다.

**변이 12/12 빨간불.**

### M2 진행 — scan 이관 (2026-08-24)

| | |
|---|---|
| 이관 | `scan` (384줄) → `VaultScan` · `ScanCore` · `ScanFolders` · `ScanMain` |
| 결과 | 골든 **4건** 바이트 동일 |
| 누적 | 이관 **53건** · 남음 2건 (`hubs`) |

가장 큰 생성기다. 네 파일로 나눴다 — 한 파일이 400줄을 넘지 않게.

#### ⚠️ 기억으로 상수를 적었다가 틀렸다

`TRACKED_FIELDS` 를 `next_action`·`stage` 로 적었는데, 실제로는
`category`·`scope` 였다. `SKIP_DIRS` 도 `.venv`·`__pycache__` 를 넣고
`.DS_Store` 를 빠뜨렸다.

**이관에서는 짐작하지 않는다. 원본을 연다.** 골든이 즉시 잡았다.

#### 첫 변이 15건 중 8건 생존 → 픽스처 보강 후 **15/15**

비어 있던 갈래: `node_modules`(점으로 시작하지 않는 SKIP_DIRS) · 빈값
표기(`""`·`null`·`~`·`-`·`[]`) · `#` 붙은 태그 · 노이즈 폴더의 역할 점수 ·
역할 후보 **셋** 경쟁 · 0.3 임계값 아래 점수 · 반올림 경계 · 정렬 안 된
modifiers.

#### ⚠️ 골든이 **실행마다 깨졌다** — 픽스처 순서

새로 더한 파일들을 mtime 고정 블록 **뒤에** 만들었다. 그 파일들이 현재
시각을 갖게 되어 `last_modified`·`recent` 점수가 매번 달라졌다.

고정 블록을 모든 노트 생성 뒤로 옮겨 고쳤고, **게이트를 하나 뒀다**:
`$VAULT/notes` 안에 고정 상한(2026-08-06)보다 새로운 `.md` 가 있으면 실패.

> 처음엔 "최근 1시간 안에 수정된 파일" 로 쟀는데, `.obsidian` 처럼 고정
> 대상이 아닌 파일까지 걸려 판정이 흐려졌다. **절대 상한**이 옳다.

#### 동등 변이 — 임계값이 두 곳에 있다

`0.3` 임계값은 상위 2개를 자를 때와 최종 걸러낼 때 **두 번** 쓰인다
(python 도 같다). 그래서 **한 곳만 바꾸면 다른 곳이 덮어** 결과가 같다 —
개별 변이는 동등하다.

둘을 **함께** 바꾸는 변이를 더해 임계값이 실제로 일하는지 확인했다 → 빨간불.

**변이 15/15 빨간불** (동등 변이 2건은 결합 변이로 대체 확인).

### M2 **완료** — hubs 이관 (2026-08-24)

| | |
|---|---|
| 이관 | `hubs` (279줄) → `L1Hubs.swift` + `L1Content.swift` |
| 결과 | 골든 **6건** 바이트 동일 |
| 누적 | **이관 58건 · 남음 0건** |

**8개 생성기 전부가 python 골든을 바이트로 통과한다.**

| 생성기 | 줄 | 케이스 |
|---|---:|---:|
| `smartenv` | 115 | 3 |
| `anm` | 184 | 9 |
| `hotkeys` | 303 | 16 |
| `hub` | 162 | 13 |
| `snapshot` | 203 | 7 |
| `scan` | 384 | 4 |
| `hubs` | 279 | 6 |
| `i18n` | 197 | (소비자를 통해) |
| **합계** | **1,827** | **58** |

#### ⚠️ 파일 이름이 NFD 로 분해됐다

`hubs` 는 **파일을 쓰는 유일한 생성기**다. Swift 의
`String.write(toFile:)` 은 경로를 파일시스템 표현으로 바꾸면서 한글을
**NFD(자모 분해)** 로 만든다:

```
python : 대  →  eb 8c 80              (U+B300)
Swift  : 대  →  e1 84 83 e1 85 a2     (ᄃ + ᅢ)
```

**내용은 같은데 파일 이름의 바이트가 다르다.** 사용자 볼트에서 같은 이름의
파일이 둘로 보이거나 링크가 깨지는 종류다. `Posix.swift` 로 바이트를 그대로
쓰게 고쳤다.

APFS 는 정규화에 **둔감하되 보존**한다 — 존재 확인은 어느 형태로 물어도
찾지만, 만들 때의 바이트는 우리가 정한 대로 남는다.

#### 폴백이 같아 살아남은 변이 둘

`devlogSuffix` 와 `tplFolder` 를 하드코딩하는 변이가 통과했다. 픽스처의
설정이 **기본값과 같아서** 폴백과 구별되지 않았기 때문이다.

`templates` 를 `notes/MyTemplates` 로, `naming.devlog_file` 을
`{{DATE}}-일지.md` 로 바꾼 케이스를 넣자 둘 다 잡혔다.

> 설정값이 **읽히는지** 보려면 기본값과 **다른** 값을 줘야 한다.
> 같은 값을 주면 "읽었다" 와 "박아뒀다" 가 구별되지 않는다.

#### 옮기지 않은 것

`build_area` 는 python 에도 있지만 **아무도 부르지 않는다**. 옮기지 않았다 —
도달하지 않는 코드를 옮기면 유지 비용만 늘고, 맞는지 확인할 방법도 없다.

**변이 9/9 빨간불.**

### 이관 순서 — 계약을 먼저

```
1. 파일마다 "같은 입력 → 바이트 동일 출력" 고정 테스트 (python 기준)
2. 그 테스트를 Swift 헬퍼에도 그대로 통과시킴
3. shell 의 호출을 헬퍼로 교체
4. python 파일 삭제는 **마지막에**, 폴백이 필요 없다고 확인된 뒤
```

⚠️ 순서를 바꾸면 안 된다. 테스트 없이 옮기면 생성되는 설정이 **조용히**
달라지고, 사용자 볼트의 단축키·폴더매핑이 어긋난다. 이 저장소는
`lib/snapshot.py` ↔ 플러그인 `collect()` 계약 테스트로 같은 방식을 이미 썼다.

## 3-1. M1 에서 찾은 것 — 언어가 python 까지 전달되지 않는다

계약 테스트에 변이를 주입하다 드러났다. `i18n.py` 의 기본 언어를 `ko` → `en`
으로 바꿔도 테스트가 통과했다. 왜냐하면 테스트가 `DEVTRAIL_LANG` 을 **항상**
지정해 기본값 경로를 한 번도 안 탔기 때문이다.

그래서 실제 운영 경로를 추적했더니:

| | |
|---|---|
| `DEVTRAIL_LANG` 을 export 하는 곳 | `lib/init.sh:58`, `lib/setup/spec.sh:139` **둘뿐** |
| `devtrail augment` 가 넘기는 환경 | `DT_DATE` 하나 |
| `hubs.py` 가 언어를 얻는 법 | `i18n.T()` → `os.environ.get("DEVTRAIL_LANG", "ko")` |
| `hubs.py` 가 설정 파일의 `lang` 을 읽는가 | **아니다** (`argv` 로 받지만 언어에 쓰지 않는다) |

⇒ **`devtrail augment` 를 `init` 과 다른 셸에서 실행하면, 영어 사용자도
한국어 허브 문구를 받는다.** 셸 쪽은 `dt_lang()` 으로 설정을 읽어 en 인데,
python 쪽은 기본값 ko 로 떨어진다.

### 고쳤다 (2026-08-23)

`lib/common.sh` 이 i18n 을 로드한 직후, 해결된 언어를 **한 번만** export 한다:

```bash
DEVTRAIL_LANG="$(dt_lang)"
export DEVTRAIL_LANG
```

호출부 12곳에 흩뿌리지 않는다 — 하나를 빠뜨리면 같은 병이 재발한다.
`dt_lang` 은 이미 `DEVTRAIL_LANG` 을 1순위로 읽으므로 멱등이고,
`DEVTRAIL_LANG=en devtrail …` 같은 일회성 지정도 그대로 존중된다.

`tests/test-lang-propagation.sh` 가 지킨다. **문자열이 아니라 실제
서브프로세스가 받는 값**을 보고, 나아가 **생성기 출력이 실제로 달라지는지**
까지 본다 — "export 하는 줄이 있다" 는 그 줄이 도는지 말해 주지 않는다.
수정을 되돌리면 4개가 빨간불이 된다.

⚠️ **골든은 바뀌지 않았다.** 계약 테스트는 python 을 직접 부르므로 CLI 의
언어 전달과 무관하다. 즉 이 수정은 생성기의 **출력 계약을 건드리지 않았다** —
M2 의 이관 목표가 흔들리지 않는다.

### 아래는 당초 판단 (참고)

M1 의 목적은 **현재 동작을 바이트로 고정하는 것**이다. 여기서 언어 전달을
고치면 골든이 바뀌고, 이관(M2)의 목표가 "같은 출력"에서 "다른 출력"으로
흔들린다. **리팩터와 동작 수정을 같은 커밋에 섞지 않는다.**

대신 `DEVTRAIL_LANG` 이 **없는** 케이스를 골든에 넣어 그 경로를 고정했다.
Swift 헬퍼도 같은 기본값을 지켜야 한다 — 고치기로 정하기 전까지는.

⚠️ 이건 **별도 결정 사항**이다 (→ ADR 0006 D6).

## 4. 설치 흐름

```
DMG 마운트
 → DevTrail.app 을 Applications 로 드래그
 → 실행
 ├─ Obsidian 이 있나?
 │   없음 → obsidian.md 안내 (설치를 대신 하지 않는다)
 ├─ 기존 DevTrail 설치가 있나?           ← §5
 ├─ 볼트를 고른다
 │   ├─ 새로 만들기 → 템플릿 배치
 │   └─ 기존 볼트 연결 → **덮어쓰기 없이** 무엇이 추가될지 먼저 보여줌
 ├─ 플러그인 설치 (files.json 계약, 이미 구현)
 ├─ core-plugins 의 global-search 만 켬 (남의 값 보존, 이미 구현)
 └─ "Obsidian 을 여세요" 안내
```

**모든 쓰기는 이미 있는 저널·undo 를 통과한다.** 새 쓰기 경로를 만들지 않는다.

## 5. 기존 Git 설치형 사용자

### 발견 (읽기만)

| 신호 | 어떻게 |
|---|---|
| 설정 | `~/.devtrail/devtrail.config.json` 존재 + `version` 필드 |
| CLI | `PATH` 의 `devtrail` → 심볼릭 링크 실체 → 저장소 경로 |
| 플러그인 | 볼트의 `manifest.json` 버전 |

### 세 경로 — 사용자가 고른다

```
┌ 유지  앱은 상태만 보여준다. 파일을 만들지 않는다.
├ 전환  설정을 그대로 두고 앱이 관리 주체가 된다.
│       기존 `devtrail` 명령도 계속 동작한다 (같은 설정을 본다).
└ 취소  앱 종료. 파일 한 개도 만들지 않는다.
```

⚠️ **자동 전환 없음.** 버전이 다르거나 판단이 서지 않으면 앱은 무엇이
다른지만 보여주고 멈춘다. 남의 설치를 말없이 가져가는 도구는 신뢰를 잃는다 —
`install-git-hooks.sh` 에서 이미 같은 원칙을 세웠다.

## 6. 릴리즈 버전 계약

`VERSION` 하나가 정본이고, 나머지가 그것을 따른다.

```
VERSION (0.6.0)
 ├─ app/Package.swift · Info.plist   번들 버전
 ├─ plugin/manifest.json             플러그인 버전 (독립 SemVer, 매니페스트에 기록)
 ├─ templates/                       템플릿 세대
 └─ config schema version            설정 스키마 (현재 3)
```

`Resources/release.json`:

```json
{
  "schema": 1,
  "version": "0.6.0",
  "app": { "bundle_version": "0.6.0", "min_macos": "<D1 에서 확정>" },
  "plugin": { "id": "devtrail-command-center", "version": "0.14.0" },
  "config_schema": 3,
  "artifacts": [{ "name": "DevTrail-0.6.0.dmg", "sha256": "…", "size": 0 }]
}
```

**게이트가 이것을 소비한다** (M6): 태그 ↔ `VERSION` ↔ `release.json` ↔
`manifest.json` ↔ config schema 가 어긋나면 릴리스가 막힌다. 문서에 적기만
하면 곧 거짓말이 된다 — 이 저장소가 `check-ci-coverage.py` 로 배운 것이다.

## 7. 서명·공증·릴리즈

### 로컬 릴리즈 경로 (Actions 예산 정책 유지)

```
./scripts/verify-local.sh --release        전체 + swift + QA 볼트
 → 앱 빌드 (universal: arm64 + x86_64)
 → codesign --options runtime  (Developer ID Application)
 → DMG 생성
 → codesign (DMG 자체)
 → notarytool submit --wait
 → stapler staple
 → shasum -a 256 → release.json
 → GitHub Release 업로드 (태그)
```

### 보안 경계

- **API 키·GitHub 토큰·개인 정보를 번들에 넣지 않는다.** 시크릿 스캔이 이미 돈다
- **self-hosted runner 를 쓰지 않는다.** 오픈소스 PR 의 코드를 개인 Mac 에서
  실행하는 위험을 만든다
- 배포물은 **태그에서만** 만든다
- 서명 인증서와 notarytool 자격 증명은 **키체인에만** 둔다. 저장소·번들 어디에도 넣지 않는다

## 8. 업데이트

### 1차 — 수동

```
새 DMG 다운로드 → Applications 에 덮어쓰기 → 앱 실행
 → 플러그인 버전 비교 (SemVer, 다운그레이드 금지 — 이미 구현)
 → Obsidian 실행 중?
     예 → **안내만.** 강제 종료하지 않는다 (이미 구현)
     아니오 → files.json 계약대로 교체 + 저널 기록 → undo 가능
 → "Obsidian 을 다시 여세요"
```

### 자동 업데이트를 미루는 경계

| 필요한 것 | 왜 지금 못 하나 |
|---|---|
| 서명 검증 | Developer ID 가 M7 이후에 생긴다 |
| 실패 롤백 | 저널·undo 는 있으나 앱 자체 교체에는 아직 없다 |
| **교체 시점 통제** | Obsidian 실행 중 플러그인 교체 금지. `require.cache` 가 `undefined` 라 재적재 여부를 **확인하지 못했다** ([ADR 0004](./0004-plugin-file-split.md) 미결) |

Sparkle 도입 시 필요한 것: appcast (= `release.json` 확장), EdDSA 서명 키,
서명된 DMG. **별도 설계 승인 후.**

## 9. 검증 계획

새로 만들지 않고 **있는 것을 확장한다**:

| 자산 | 확장 |
|---|---|
| `scripts/verify-local.sh --release` | 앱 빌드 + DMG 생성 + 서명 확인 단계 추가 |
| `scripts/qa-vault.sh` | "앱이 설치한 경우" 시나리오 추가 (CLI 와 결과가 같은가) |
| `tests/check-ci-coverage.py` | 릴리즈 매니페스트 버전 일치 계약 |
| 사람의 눈 | **대체 불가** — DMG 열기, 드래그, 첫 실행, Gatekeeper |

⚠️ **DMG 설치 경험은 자동화로 확인할 수 없다.** Gatekeeper 대화상자,
드래그 앤 드롭, 첫 실행 권한 요청은 사람이 봐야 한다. QA 하니스가
`restart_verified` 를 다루는 방식과 같게 — 확인하지 않은 것을 확인했다고
말하지 않는다.
