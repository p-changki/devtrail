'use strict';
/* view.js 를 실제로 렌더해 본다. 죽으면 그 자리를 말한다.
 *
 * ⚠️ 이 하니스가 없어서 세 번을 놓쳤다. 화면 코드를 부르지 않는 테스트는
 *    화면이 뜨는지 말해 주지 못한다.
 */
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');
const { el, collectText, collectClasses } = require('./fake-dom.js');

const Module = require('module');
const orig = Module._load;
const obsidianStub = {
  ItemView: class { constructor(leaf) { this.leaf = leaf; this.contentEl = el('div'); } },
  Modal: class { constructor(app) { this.app = app; this.contentEl = el('div'); this.scope = { register() {} }; } },
  Notice: class {},
  setIcon() {},
};
Module._load = (r, p, m) => (r === 'obsidian' ? obsidianStub : orig(r, p, m));

const model = require(path.join(ROOT, 'plugin/read-model.js'));
const cmds = require(path.join(ROOT, 'plugin/commands.js'));
const i18n = require(path.join(ROOT, 'plugin/i18n.js'));
const makeView = require(path.join(ROOT, 'plugin/view.js'));

/* 노트 몇 개짜리 가짜 볼트. */
function fakeApp(notes) {
  const files = notes.map((n) => ({
    path: n.path,
    basename: n.path.split('/').pop().replace(/\.md$/, ''),
    parent: { name: n.path.split('/').slice(-2)[0] },
    stat: { mtime: n.mtime || Date.now(), ctime: n.ctime || Date.now() },
    __body: n.body || '',
    __fm: n.fm || {},
  }));
  return {
    vault: {
      getMarkdownFiles: () => files,
      getAbstractFileByPath: (p) => files.find((f) => f.path === p) || null,
      cachedRead: async (f) => f.__body,
      read: async (f) => f.__body,
      adapter: { getBasePath: () => ROOT, exists: async () => true, read: async () => '' },
    },
    metadataCache: {
      // ⚠️ listItems 를 비워 두면 할 일 수집이 아예 안 돌고, 기한 라벨 같은
      //    가지가 시험되지 않는다 — 본문에 열린 체크박스가 있으면 있다고 한다.
      getFileCache: (f) => ({
        frontmatter: f.__fm,
        listItems: (f.__body.match(/^\s*- \[ \]/gm) || []).map(() => ({ task: ' ' })),
      }),
    },
    commands: { commands: {}, executeCommandById() {} },
    hotkeyManager: { printHotkeyForCommand: () => '⌘⇧K' },
    internalPlugins: { getEnabledPluginById: () => ({ openGlobalSearch() {} }) },
    workspace: { getLeaf: () => ({ openFile() {} }), rootSplit: {} },
    plugins: { plugins: {} },
  };
}

/* main.js 가 makeView 에 넘기는 이름들을 소스에서 읽는다.
 *
 * ⚠️ 목록을 여기 따로 적지 않는다. 두 곳에 있으면 갈라진다 — 이 저장소가
 *    dirs.devlog 로 네 번 겪은 병이다. */
function mainInjectionList() {
  const src = require('fs').readFileSync(path.join(ROOT, 'plugin/main.js'), 'utf8');
  const m = /const view = m\.makeView\(\{([\s\S]*?)\n  \}\);/.exec(src);
  if (!m) throw new Error('main.js 에서 makeView 호출을 찾지 못했습니다');
  return m[1]
    .split('\n')
    .filter((l) => !l.trim().startsWith('//'))
    .join(' ')
    .split(',')
    .map((x) => x.trim())
    .filter((x) => /^[A-Za-z_][A-Za-z0-9_]*$/.test(x));
}

const PATHS = { templates: 'notes/템플릿', devlog: 'notes/개발/개발일지',
                weekly: 'notes/개발/주간리뷰', projects: 'notes/개발/프로젝트' };

async function render(route, notes, onApp) {
  // ⚠️ 전부 넘기지 않는다. main.js 가 **실제로 넘기는 것만** 넘긴다 —
  //    ...model 로 뭉뚱그리면 main 이 하나를 빠뜨려도 여기선 통과하고,
  //    실물에서만 죽는다. 실제로 daysBetween 이 그랬다(2026-08-23).
  const injected = mainInjectionList();
  const bag = {
    obsidian: obsidianStub,
    ...model, ...cmds,
    textFor: i18n.textFor,
    icon: () => {},
    isMainLeaf: () => true,
    readPathMap: async () => ({ ok: true, data: { lang: 'ko', paths: PATHS } }),
    VIEW_TYPE: 'devtrail-command-center',
    PLUGIN_ID: 'devtrail-command-center',
    PATH_MAP_FILE: '_devtrail-paths.md',
  };
  const deps = {};
  for (const k of injected) deps[k] = bag[k];
  const view = makeView(deps);
  const V = view.CommandCenterView;
  const v = new V({ getRoot: () => ({}) });
  v.app = fakeApp(notes);
  // 계측 훅 — 벤치가 볼트 스캔 횟수를 셀 수 있게 한다. 테스트는 넘기지 않는다.
  if (onApp) onApp(v.app);
  v.route = route;
  await v.render();
  return v.contentEl;
}

module.exports = { render, collectText, collectClasses, makeView, obsidianStub, fakeApp, PATHS, model, cmds, i18n };
