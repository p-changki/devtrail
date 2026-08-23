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
