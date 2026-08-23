'use strict';

/* DevTrail Command Center — Obsidian 연동.
 *
 * 명령 레지스트리에서 **부를 것을 고른다**. DOM 은 여기 없다.
 *
 * ⚠️ 명령 id 를 짐작해서 부르지 않는다. 레지스트리에 실제로 있는지 먼저
 *    확인하고, 확신할 수 없으면 아무것도 고르지 않는다 — '뭐라도 부르는'
 *    것보다 '안 부르는' 것이 낫다. 검색 버튼이 인덱스를 다시 만들면
 *    사용자는 무슨 일이 일어났는지 모른다.
 *
 * ⚠️ 노트를 여기서 만들지 않는다. 등록된 Templater 명령을 부를 뿐이다 —
 *    형식이 두 곳에서 만들어지면 반드시 어긋난다 (ADR 0002).
 */

/* ── 기존 명령에 위임 ────────────────────────────────────────────────────
 *
 * ⚠️ 노트를 여기서 만들지 않는다. Templater 명령을 부른다.
 *
 *    같은 노트를 만드는 코드가 플러그인에도 생기면, 템플릿을 고쳐도
 *    플러그인 쪽은 옛말을 한다. 2026-08-22 QA 에서 프로젝트 허브 본문이
 *    두 곳에 있어 링크가 전부 깨졌다 — 같은 유형이다.
 *
 * ⚠️ 명령 id 에는 볼트 경로가 들어간다:
 *      templater-obsidian:create-notes/템플릿/개발일지양식.md
 *    하드코딩하면 영어 볼트나 다른 루트를 쓰는 사람에게서 조용히 죽는다.
 *    경로 맵에서 조립한다.
 */
function templaterCommandId(paths, templateFile) {
  const dir = paths && paths.templates;
  if (!dir || !templateFile) return null;
  return `templater-obsidian:create-${dir}/${templateFile}`;
}

/* 어떤 캡처가 어떤 템플릿을 쓰는가.
 *
 * 파일명은 언어마다 다르다 — 경로 맵의 lang 으로 고른다. 여기 목록은
 * Templater 에 등록된 것(enabled_templates_hotkeys)과 같아야 한다. */
const CAPTURES = [
  { key: 'devlog',  ko: '개발일지양식.md',            en: 'Devlog.md' },
  { key: 'devnote', ko: '개발메모 템플릿.md',          en: 'Dev note.md' },
  { key: 'idea',    ko: '아이디어 빠른저장 템플릿.md', en: 'Quick idea.md' },
  { key: 'worklog', ko: '워크로그 템플릿.md',          en: 'Worklog.md' },
  { key: 'report',  ko: '회고 템플릿.md',              en: 'Retro.md' },
  { key: 'project', ko: '프로젝트 생성 템플릿.md',     en: 'New project.md' },
];

function captureFile(c, lang) {
  return lang === 'en' ? c.en : c.ko;
}

/* 설치된 플러그인의 명령을 레지스트리에서 찾는다.
 *
 * ⚠️ 명령 id 를 박지 않는다. 외부 플러그인의 id 는 버전에 따라 바뀌고,
 *    박아두면 바뀐 날 조용히 죽는다. 우리가 아는 것은 '플러그인 id' 뿐이고
 *    그건 사용자가 설치할 때 고르는 이름이라 안정적이다.
 *
 * ⚠️ 없으면 null 을 준다. 비슷한 명령을 대신 실행하지 않는다 — 검색을
 *    눌렀는데 다른 것이 열리는 편이 아무 일도 안 일어나는 것보다 나쁘다.
 */
/* 이 Enter 가 '실행' 인가.
 *
 * ⚠️ 한글·일본어·중국어는 입력기(IME)가 글자를 **조합**한다. 조합 중에 누르는
 *    Enter 는 "글자를 확정" 하라는 뜻이지 "실행하라" 가 아니다. 그것을 실행으로
 *    받으면 아직 완성되지 않은 값이 넘어간다 — "가나" 를 치고 Enter 를 눌렀는데
 *    엉뚱한 글자로 검색됐다(2026-08-22).
 *
 *    조합 중이면 그냥 넘긴다. 사용자는 한 번 더 누르고, 그때 실행된다 —
 *    한글 쓰는 사람이 어디서나 하는 동작이다.
 *
 * ⚠️ 영문만 쓰면 평생 못 만나는 버그다. 그래서 더 쉽게 놓친다.
 *
 * ⚠️ 행·카드의 Enter 핸들러에는 이것이 필요 없다. 그쪽은 입력창이 아니라
 *    role="button" 인 div 라 조합이 일어날 수 없다. **글자를 받는 곳에만**
 *    쓴다 — 새 입력창을 만들면 여기를 떠올려야 한다.
 */
function isSubmitKey(ev) {
  if (!ev || ev.key !== 'Enter') return false;
  if (ev.isComposing) return false;
  // 일부 입력기·구형 경로는 isComposing 대신 keyCode 229 로 온다.
  if (ev.keyCode === 229) return false;
  return true;
}

/* 이 명령에 **실제로 배정된** 단축키. 없으면 null.
 *
 * ⚠️ 키캡을 손으로 박지 않는다. ⌘P 를 적어 뒀다가 그 버튼이 우리 모달을
 *    열게 바꾼 적이 있다 — 표시는 명령 팔레트를 가리키는데 실제로는 다른 게
 *    열렸다. 화면이 거짓을 말하면 사용자는 화면을 안 믿게 된다.
 *
 * ⚠️ 안 배정됐으면 아무것도 보여주지 않는다. 있지도 않은 단축키를 적으면
 *    사용자가 눌러 보고 또 화면을 의심한다.
 */
function hotkeyLabel(app, commandId) {
  const hm = app && app.hotkeyManager;
  if (!hm || typeof hm.printHotkeyForCommand !== 'function') return null;
  const s = hm.printHotkeyForCommand(commandId);
  return (typeof s === 'string' && s.length > 0) ? s : null;
}

/* 검색을 실제로 여는 함수를 만든다. 없으면 null.
 *
 * ⚠️ 명령만 부르면 사용자가 친 글자가 버려진다. "devlog" 를 치고 Enter 를
 *    눌렀는데 빈 검색창이 열리면 사용자는 검색이 고장 났다고 느낀다 —
 *    2026-08-22 에 실제로 그랬다.
 *
 * ⚠️ 검색어를 실어 나르는 경로는 Obsidian 의 내부 검색뿐이다:
 *
 *      app.internalPlugins.getEnabledPluginById('global-search')
 *         .openGlobalSearch(query)
 *
 *    Obsidian 자신이 태그 클릭·그래프에서 쓰는 관용구다(번들에서 확인).
 *    Omnisearch 의 명령은 인자를 받지 않아 글자를 못 싣는다 — 그래서 글자를
 *    지키는 쪽을 먼저 고른다.
 *
 * ⚠️ 둘 다 없으면 null 이다. 아무 명령이나 대신 부르지 않는다.
 */
function searchRunner(app) {
  const ip = app.internalPlugins;
  const core = ip && typeof ip.getEnabledPluginById === 'function'
    ? ip.getEnabledPluginById('global-search') : null;
  if (core && typeof core.openGlobalSearch === 'function') {
    return (query) => core.openGlobalSearch(query);
  }
  // 글자는 못 싣지만, 검색 화면을 여는 것이 안 여는 것보다는 낫다.
  const pick = findSearchCommand(app);
  if (pick) return () => app.commands.executeCommandById(pick);
  if (commandExists(app, CORE_SEARCH)) return () => app.commands.executeCommandById(CORE_SEARCH);
  return null;
}

/* 설치된 검색 플러그인에서 '검색 모달을 여는' 명령 하나를 고른다.
 *
 * ⚠️ id 로 시작하는 명령 중 첫 번째를 집으면 안 된다. Omnisearch 는 검색 말고도
 *    인덱스 재생성·캐시 비우기·링크 삽입 같은 명령을 갖는다 — 검색 버튼이
 *    인덱스를 다시 만들면 사용자는 무슨 일이 일어났는지 모른다.
 *
 * ⚠️ 확신할 수 없으면 null 을 돌려준다. '뭐라도 부르는' 것보다 '안 부르는' 것이
 *    낫다. 화면은 그때 기본 검색으로 떨어지거나 버튼을 끈다.
 *
 * ⚠️ 명령 id 를 하드코딩하지 않는다. 이름과 접미사를 함께 보고 판별한다 —
 *    플러그인이 id 를 바꿔도 견디고, 엉뚱한 명령은 걸러진다.
 */
const SEARCH_VERBS = /(^|[-_ ])(search|find|query)([-_ ]|$)/i;

const SEARCH_TARGETS = /(modal|palette|open|show|all[-_ ]?notes|vault|everything)/i;

/* 검색처럼 보이지만 검색이 아닌 것들. */
const SEARCH_EXCLUDE = /(index|cache|rebuild|reindex|insert|link|copy|toggle|setting|refresh)/i;

function findSearchCommand(app, pluginIds) {
  const all = (app.commands && app.commands.commands) || {};
  const ids = pluginIds || SEARCH_PLUGINS;
  for (const pid of ids) {
    const prefix = pid + ':';
    for (const id of Object.keys(all)) {
      if (!id.startsWith(prefix)) continue;
      const suffix = id.slice(prefix.length);
      const name = (all[id] && all[id].name) || '';
      // 이름과 접미사 어느 쪽에서도 제외어가 보이면 거른다.
      if (SEARCH_EXCLUDE.test(suffix) || SEARCH_EXCLUDE.test(name)) continue;
      // 검색을 뜻하는 낱말이 있고, 무엇을 여는지도 드러나야 고른다.
      const hay = suffix + ' ' + name;
      if (SEARCH_VERBS.test(hay) && SEARCH_TARGETS.test(hay)) return id;
    }
  }
  return null;
}

/* 검색은 Obsidian 이 이미 갖고 있다(⌘O · ⌘⇧F). 여기서 제공하는 것은
 * '설치된 검색 플러그인으로 가는 통로' 뿐이다 — 검색기를 새로 만들지 않는다. */
const SEARCH_PLUGINS = ['omnisearch'];

/* Obsidian 기본 검색. 부르기 전에 레지스트리에 있는지 확인한다 —
 * 짐작해서 부르면 조용히 아무 일도 일어나지 않는다. */
const CORE_SEARCH = 'global-search:open';

/* 그 명령이 실제로 있는가. 없으면 조용히 다른 노트를 만들지 않는다 —
 * 무엇을 해야 하는지 말한다. */
function commandExists(app, id) {
  if (!id) return false;
  const all = app.commands && app.commands.commands;
  return !!(all && all[id]);
}

module.exports = {
  CAPTURES, SEARCH_PLUGINS, CORE_SEARCH,
  SEARCH_VERBS, SEARCH_TARGETS, SEARCH_EXCLUDE,
  templaterCommandId, captureFile, commandExists,
  findSearchCommand, searchRunner, hotkeyLabel, isSubmitKey,
};

// 이 파일은 전부 순수하다 — 테스트가 통째로 부른다.
module.exports.__test = module.exports;
