# ADR 0002 — Command Center 플러그인의 경계

- 상태: **제안**
- 날짜: 2026-08-22
- 대상 릴리스: v0.5 이후
- 관련: `docs/command-center-design.md`(로컬) · [ADR 0001](0001-project-identity.md)

---

## 문제

Obsidian 안에 DevTrail 전용 화면(Command Center)을 플러그인으로 만들자는
설계안이 나왔다. 방향에는 동의한다 — Markdown + Dataview 로는 명령 바,
캡처 흐름, 키보드 이동, 빈 상태를 제대로 만들 수 없다.

문제는 **경계**다. 이 저장소는 오늘(2026-08-22) 같은 결함을 **세 번** 고쳤다.

| 어디 | 무엇 |
|---|---|
| `templates/scripts/_lib.sh.tmpl` | `dirs.devlog` 를 직접 읽고 기본값 `"devlog"` 를 자기가 가짐 |
| `templates/dashboard/server.py` | 같음 |
| `app/Sources/DevTrailApp/Status.swift` | 같음 |

셋 다 새로 설치한 볼트에서 **파일이 있는데 "없음"** 이라고 말했다. 원인은
하나다 — *같은 것이 두 곳에 있었다*.

플러그인은 **네 번째 소비자**다. 경계를 먼저 못박지 않으면 같은 사고가
네 번째로 일어난다.

---

## 결정

### D1. 같은 질문에 두 개의 답을 두지 않는다

Markdown 대시보드(`대시보드.md`)와 Command Center 는 **병존하지 않는다.**

플러그인이 Phase 2(Home 화면)를 통과하면, 그 시점에 둘 중 하나를 정리한다.

| 안 | 언제 |
|---|---|
| Markdown 대시보드를 **온보딩 링크 모음**으로 축소 | 플러그인이 기본이 될 때 |
| 플러그인을 **opt-in 보조 화면**으로 유지 | Markdown 이 기본으로 남을 때 |

**어느 쪽이든 "오늘 무엇을 할 것인가" 에 답하는 화면은 하나다.**

> 설계안은 "keep the Markdown dashboard as a fallback until Phase 2 has passed"
> 라고 했다. fallback 은 좋지만 **기한이 없으면 병존이 된다.** Phase 2 종료를
> 기한으로 못박는다.

⚠️ 플러그인은 Dataview 를 런타임 의존성으로 쓰지 않는다(설계안 §7). 그러면
같은 노트를 세는 코드가 **두 벌**이 된다 — 플러그인의 어댑터와 Markdown 의
Dataview 쿼리. 병존 기간이 길수록 두 수치가 어긋날 확률이 올라간다.

### D2. 빌드 산출물을 저장소에 커밋하지 않는다

플러그인 번들(`main.js`)은 **GitHub Release 자산**으로 배포하고,
`devtrail command-center install` 이 내려받는다.

근거 — 설치된 플러그인 실측:

```
dataview             2321 KB
templater-obsidian    442 KB
auto-note-mover        84 KB
```

저장소에 커밋하면:

- diff 가 읽히지 않아 **리뷰가 불가능**하다
- 시크릿 스캔이 매 커밋마다 대용량 번들을 훑는다
- 소스와 산출물이 어긋나도 **아무도 모른다**

**이미 그 일을 하는 코드가 있다.** v0.4.0 의 `lib/plugins.sh` 는
GitHub 릴리스에서 플러그인을 받아 설치한다 — 버전 고정, 설치 전 동의 화면,
`manifest.json` 의 `id` 검증, 저널·`undo`, 이미 깔린 것은 건드리지 않음.

Command Center 도 **같은 경로를 쓴다.** `preset/plugins.json` 에 항목 하나를
더하는 것으로 끝난다. 새 설치 코드를 쓰지 않는다.

⚠️ 자기 플러그인이라고 예외를 두지 않는다. 남의 플러그인에 적용하는 안전
계약(동의·버전 고정·되돌리기)이 우리 것에는 필요 없다고 말할 근거가 없다.

### D3. 빌드 도구를 도입하지 않는다 — 순수 JS 한 파일로 쓴다

지금 저장소의 언어:

```
.sh     53개
.py     11개
.swift   6개
.ts      0개
.js      0개
```

CI 는 `ubuntu-latest`(bash·python·jq)와 `macos-latest`(swift) 두 종류다.
Node 를 들이면 **세 번째 툴체인**이고, CI 잡과 기여 진입장벽이 함께 는다.

그리고 이미 JS 를 쓰고 있다 — **템플릿 22개**가 Templater 안에서 JS 를
돌린다. 가장 큰 것이 118줄이다. 빌드 도구 없이.

Command Center v1 은 **읽기 전용**이고(설계안 §6), 데이터 어댑터는
`_devtrail-paths.md` 하나를 파싱한다. 이 규모에 TypeScript 의 값이 세 번째
툴체인의 비용보다 크다고 볼 근거가 없다.

**뒤집는 조건**을 명시한다. 아래 중 하나가 참이 되면 이 결정을 다시 본다.

- 플러그인 소스가 **1500줄**을 넘는다
- 기여자가 둘 이상이 되어 타입 계약이 소통 비용을 줄여준다
- 런타임 오류가 **테스트로 못 잡는** 형태로 반복된다

### D4. 배포 경로는 하나다 — 업데이트도 그 길로 간다

D2·D3 이 만나면 릴리스 다운로드가 필요 없어진다. 빌드가 없으므로
`plugin/` 이 곧 배포물이고, 저장소 자체가 이미 사용자에게 전달된다.

```
사용자 설치   curl install.sh | bash      → git clone
소스 갱신     devtrail update --apply     → git pull
볼트 반영     devtrail command-center update --apply
```

별도 GitHub Release 다운로드를 만들지 않는다. 두 경로가 **서로 다른 버전을
가져올 수 있고**, 그러면 사용자가 어느 게 진짜인지 모른다. D2 가 막으려던
것이 정확히 그것이다.

**감지와 적용을 나눈다.**

| | 누가 | 언제 |
|---|---|---|
| 감지 | `devtrail doctor` · `command-center status` | **그 명령을 실행할 때** |
| 적용 | `command-center update --apply` | **사용자 승인 후에만** |
| 화면 | Command Center | 상태 안내만. 스스로 받거나 바꾸지 않는다 |

⚠️ 실행 중인 Obsidian 아래에서 플러그인 파일을 갈아치우면 로딩 상태가
꼬인다. 적용은 되지만 반영은 재시작 뒤다 — 그 사실을 반드시 말한다.

⚠️ **Obsidian 을 켤 때 자동으로 도는 것은 없다.** 백그라운드 검사도, 주기적
확인도 없다. `devtrail doctor` 나 `command-center status` 를 **사용자가 실행할
때** 비교한다. "자동 감지" 라고 쓰면 없는 기능을 있다고 말하는 것이다.

Command Center 화면은 네트워크 요청도, 자동 다운로드도, 자동 파일 교체도
하지 않는다.

**호환성은 감지까지가 전부다.** Obsidian 이 API 를 바꾸면 코드 수정이
필요하고, 그건 자동화할 수 없다. 대신 없는 명령·없는 플러그인을 만나면
그 버튼만 끄고 안내한다(graceful degradation). 화면 전체를 죽이지 않는다.

**모르는 것은 unknown 이다.** 설치되지 않았으면 버전을 모른다. 0 이나
false 로 채우면 화면이 사실이 아닌 것을 말하게 된다.

---

## 무엇을 결정하지 않았는가

- 화면 구성·시각 언어·접근성 요구 — 설계안(`docs/command-center-design.md`)에
  있고, 그건 구현하면서 바뀐다. ADR 로 굳히지 않는다.
- Markdown 대시보드를 **어느 쪽으로** 정리할지 — Phase 2 의 실물 QA 결과로
  정한다. 지금 정하면 근거 없이 정하는 것이다.
- Claudian·AI 스킬 연동 — 에이전트에게 볼트 읽기·쓰기·명령 실행 권한을 주는
  일이라 안전 계약이 훨씬 크다. **별도 ADR** 로 다룬다.

---

## 이 결정이 지키는 것

```
devtrail.config.json          CLI 만 읽는다
_devtrail-paths.md            플러그인이 읽는 유일한 경로 출처
Markdown 노트                 사용자 데이터의 유일한 영속 형식
Templater / Shell commands    쓰기를 하는 유일한 통로
```

플러그인은 **읽기 모델과 상호작용 계층**이다. 경로를 짐작하지 않고, 노트를
옮기지 않고, 설정을 쓰지 않는다. 경로 맵이 없거나 깨졌으면 추측하는 대신
`devtrail obsidian` / `devtrail doctor` 로 안내한다.

---

## 착수 조건

이 ADR 이 머지되면 Phase 1(플러그인 골격 + 저널 설치 경로)을 시작한다.

Phase 1 종료 기준: **노트를 하나도 건드리지 않고** 켜고 끌 수 있으며,
`devtrail undo` 가 플러그인 설정을 되돌린다.

---

## 참고

- `lib/plugins.sh` — 재사용할 설치 경로 (v0.4.0)
- `lib/merge/templates.sh:61` — 허브 원본을 볼트에 까는 방식 (같은 패턴)
- `templates/scripts/_lib.sh.tmpl:40` — 경로 해석을 CLI 로 모은 자리
