# 0004. 플러그인을 여러 파일로 나눌 수 있다 — 절대 경로로

- 상태: 채택 (조건부)
- 날짜: 2026-08-22
- 관련: [0002 Command Center](./0002-command-center.md) D3
- 근거: [`evidence/0004-loader-spike.json`](./evidence/0004-loader-spike.json) (ASCII 경로)
  · [`evidence/0004-loader-spike-hazardpath.json`](./evidence/0004-loader-spike-hazardpath.json) (물결·공백·한글·점)

## 무엇이 문제였나

`plugin/main.js` 가 1749줄이 됐다. ADR 0002 D3 의 재검토선(1500)을 넘었고,
다음 기능(칸반 쓰기)을 넣으면 2000줄을 넘는다.

나누려면 Obsidian 이 형제 파일을 읽어야 하는데, **그게 되는지 아무도 몰랐다.**
추측으로 리팩터링을 시작하면 통째로 헛일이 될 수 있었다.

## 어떻게 알아냈나

버릴 플러그인 하나(`main.js` + `probe.js`)를 실제로 설치하고 Obsidian 을
완전히 종료했다 재실행했다.

```
설치     <vault>/.obsidian/plugins/devtrail-loader-spike/
절차     ⌘Q → 재실행 → onload 에서 측정 → saveData 로 data.json 에 기록
```

⚠️ 결과를 화면 알림으로만 띄우지 않았다. 사람이 받아 적게 하면 재현이 안 되고
근거로도 못 쓴다 — **파일로 남겼고 그 파일을 이 저장소에 넣었다.**

⚠️ `'찾았다'` 와 `'실행됐다'` 를 갈랐다. 상수만 읽으면 모듈이 로드된 척할 수
있어, `sentinel(2,3)` 을 실제로 불러 `sentinel:5` 를 확인했다.

## 알아낸 것

### 상대 경로는 안 된다 — 배포 문제가 아니다

```
typeof require       function        module        object
typeof __dirname     string
__dirname            /Applications/Obsidian.app/.../electron.asar/renderer
Require stack        electron/js2c/renderer_init
probe.js 실물 존재   true
require('./probe.js')  MODULE_NOT_FOUND
```

플러그인 코드는 **Electron 의 renderer 문맥**에서 평가된다. `__dirname` 이
플러그인 폴더가 아니라 Obsidian 내부를 가리키므로, `./` 가 엉뚱한 곳을
기준으로 풀린다. 파일은 분명히 거기 있었다.

`require.resolve` 와 `require.cache` 가 **undefined** 다 — Obsidian 이 주는
`require` 는 온전한 CommonJS 가 아니라 `'obsidian'`·builtin 용 제한된
물건이다. (`window.require` 는 또 다른 물건이다.)

### 절대 경로는 된다

```
adapter.getBasePath()               /Users/…/qa-vault
require('<abs>/probe.js')           OK   probe-module-loaded
require('<abs>/probe')  확장자 없이  OK   probe-module-loaded
require('<abs>/probe.js').sentinel(2,3)  OK   sentinel:5
```

**모듈이 실제로 실행됐다.** 판정: `3b-absolute-require-works`.

## 결정

**파일을 나눌 수 있다. 빌드 도구 없이.**

```js
const base = this.app.vault.adapter.getBasePath();
const here = `${base}/${this.manifest.dir}`;
const model = require(`${here}/read-model.js`);
```

따라서:

- **ADR 0002 D3 을 유지한다.** 빌드 도구를 도입하지 않는다 — 도입할 이유가
  사라졌다
- **D2 도 유지된다.** 산출물이 없으므로 커밋할 것도 없다. `plugin/*.js` 가
  그대로 소스이자 배포물이다
- **install-time concat 은 채택하지 않는다.** 모듈 격리·의존 순서·전역 이름
  충돌·디버깅·업데이트 검증 비용을 새로 떠안는 일인데, 로더가 지원하므로
  불필요하다

## 나누기 전에 풀어야 할 것

### 1. 경로에 공백·유니코드가 있으면? — 확인함 ✓

1차 스파이크는 ASCII 경로에서 돌렸다. 실사용 경로는 다르다:

```
/Users/…/Library/Mobile Documents/com~apple~CloudDocs/Obsidian Vault
                                 ~~~~~ 물결        ^^^^^^^^^^^^^^ 공백
```

그래서 위험을 **모아 담은** 볼트를 하나 만들어 다시 물었다
([`evidence/0004-loader-spike-hazardpath.json`](./evidence/0004-loader-spike-hazardpath.json)):

```
/Users/…/devtrail-qa5/com~apple~CloudDocs/Obsidian Vault 한글 v1.0
                      ~~~~~ ~~~~~         ^^^^^^^^ ^^^^^ ^^^^ ^^^^
                      물결                공백      한글   점
```

```
with_ext   OK  probe-module-loaded
no_ext     OK  probe-module-loaded
sentinel   OK  sentinel:5
```

물결·공백·한글·점을 전부 담은 경로에서 통과했다. 이 위험은 닫혔다.

### 2. 배포 목록이 파일 이름을 안다

지금 `_cc_files()` 가 `manifest.json main.js styles.css` 를 박아 두고 있다.
파일이 늘면 설치·업데이트·undo 가 새 파일을 알아야 한다.

⚠️ 목록을 두 곳에 두지 않는다. 한 곳(예: `plugin/files.json`)에서 읽고,
설치·업데이트·테스트가 모두 그것을 본다 — 이 저장소가 `dirs.devlog` 로
네 번 겪은 병을 여기서 반복하지 않는다.

### 3. 캐시

`require.cache` 가 없다. 같은 경로를 두 번 require 할 때 다시 읽는지 캐시를
쓰는지 모른다. **업데이트 후 재시작 없이 옛 코드가 남는지** 확인해야 한다.
(플러그인은 어차피 재시작이 필요하므로 실무상 영향은 작을 것으로 본다.)

## 나눌 경계

ADR 0002 재검토 1 에서 적은 그대로 간다.

```
read-model.js    vault 를 읽어 값으로 바꾼다        (순수, DOM 없음)
commands.js      레지스트리에서 부를 것을 고른다    (순수)
view.js          값을 DOM 으로                      (Obsidian API)
main.js          플러그인 수명주기 · 위 셋을 잇는다
```

⚠️ 순수한 둘을 먼저 뗀다. 그쪽은 화면 없이 테스트할 수 있어 옮기는 동안
안전망이 그대로 붙어 있다.

## 되돌릴 조건

- Obsidian 이 이 동작을 막는다 — 그때는 concat 과 번들을 비교하는 ADR 을
  새로 쓴다
