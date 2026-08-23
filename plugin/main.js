'use strict';

/*
 * DevTrail Command Center — Phase 1 골격.
 *
 * 이 플러그인은 읽기 모델이자 상호작용 계층이다. 경로·설정·쓰기의 두 번째
 * 출처가 되어서는 안 된다.
 *
 * ⚠️ 경로는 _devtrail-paths.md 하나에서만 읽는다.
 *
 *    이 저장소는 2026-08-22 에 같은 결함을 세 번 고쳤다 — 생성 스크립트,
 *    웹 대시보드, 메뉴바 앱이 각자 dirs.devlog 의 기본값을 갖고 있었다.
 *    셋 다 새로 설치한 볼트에서 "파일이 있는데 없다" 고 말했다.
 *    이 플러그인은 네 번째 소비자다. 짐작하지 않는다.
 *
 * ⚠️ devtrail.config.json 을 읽지 않는다. 경로 맵이 없거나 깨졌으면
 *    추측하는 대신 무엇을 실행해야 하는지 알려준다.
 *
 * 빌드 도구를 쓰지 않는다(ADR 0002 D3). 이 파일이 곧 배포물이다.
 */

const obsidian = require('obsidian');

const PLUGIN_ID = 'devtrail-command-center';
const VIEW_TYPE = 'devtrail-command-center';

/* 아이콘. Obsidian 이 번들한 lucide 이름만 쓴다 — 아이콘 파일을 들고
 * 다니면 그것도 유지할 물건이 된다. */
function icon(el, name) {
  if (obsidian.setIcon) obsidian.setIcon(el, name);
}
const PATH_MAP_FILE = '_devtrail-paths.md';

/* ── 모듈 로더 ──────────────────────────────────────────────────────────────
 *
 * ⚠️ Obsidian 은 형제 파일을 상대 경로로 읽지 못한다. 플러그인 코드가
 *    Electron 의 renderer 문맥에서 평가되어 __dirname 이 Obsidian 내부를
 *    가리키기 때문이다 — require('./x.js') 는 MODULE_NOT_FOUND 다.
 *
 *    절대 경로는 된다(ADR 0004 · 근거 evidence/0004-loader-spike*.json).
 *    공백·물결·한글이 든 경로에서도 확인했다.
 *
 * ⚠️ 모듈끼리 다시 상대 require 하지 않는다. 여기서만 부르고, 필요한 것은
 *    인자로 넘긴다 — 그래야 로딩 경로가 한 곳이다.
 *
 * ⚠️ 실패하면 조용히 죽지 않는다. 무엇이 왜 안 되는지 화면에 남긴다 —
 *    빈 대시보드는 사용자에게 아무것도 말해 주지 않는다.
 */
let RM = null;

function loadModules(plugin) {
  const adapter = plugin.app.vault.adapter;
  if (typeof adapter.getBasePath !== 'function') {
    throw new Error('이 플랫폼에서는 볼트 경로를 알 수 없습니다 (데스크톱 전용)');
  }
  const dir = `${adapter.getBasePath()}/${plugin.manifest.dir}`;
  const model = require(`${dir}/read-model.js`);
  const cmds = require(`${dir}/commands.js`);
  const i18n = require(`${dir}/i18n.js`);
  const makeView = require(`${dir}/view.js`);
  if (typeof makeView !== 'function') throw new Error('화면 모듈이 factory 가 아닙니다');
  // ⚠️ 로드된 척만 하는 경우를 거른다. 있어야 할 것이 실제로 있는지 본다.
  for (const k of MODEL_KEYS) {
    if (model[k] === undefined) throw new Error(`읽기 모델에 ${k} 가 없습니다`);
  }
  for (const k of COMMAND_KEYS) {
    if (cmds[k] === undefined) throw new Error(`명령 모듈에 ${k} 가 없습니다`);
  }
  // ⚠️ 문구는 키 하나만 봐도 소용없다. 두 언어가 다 있는지 본다 — 한쪽만
  //    있으면 그 언어를 쓰는 사람 화면에 undefined 가 나간다.
  if (!i18n.TEXT || !i18n.TEXT.ko || !i18n.TEXT.en || typeof i18n.textFor !== 'function') {
    throw new Error('문구 모듈이 온전하지 않습니다 (ko·en·textFor)');
  }
  return { model, cmds, i18n, makeView };
}

const COMMAND_KEYS = ['CAPTURES', 'SEARCH_PLUGINS', 'CORE_SEARCH', 'SEARCH_VERBS', 'SEARCH_TARGETS', 'SEARCH_EXCLUDE', 'templaterCommandId', 'captureFile', 'commandExists', 'findSearchCommand', 'searchRunner', 'hotkeyLabel', 'isSubmitKey'];

const MODEL_KEYS = ['DAY_MS', 'STALE_DAYS', 'FLOW_WEEKS', 'RECENT_PAGE', 'DOC_TYPES', 'BOARD_COLUMNS', 'STAGE_ALIASES', 'isUserNote', 'fm', 'localDate', 'dayStart', 'bearsTasks', 'openTasks', 'openTasksInVault', 'buildFlow', 'weeklyBars', 'parseDue', 'daysBetween', 'isStale', 'relativeDays', 'normalizeStage', 'todayDevlog', 'collect'];

/* 로드한 모듈을 이 파일의 이름들에 묶는다.
 *
 * ⚠️ 호출부를 RM.collect(...) 로 바꾸지 않는 이유: 호출부가 40곳이 넘고,
 *    한 곳만 놓쳐도 화면이 조용히 깨진다. 묶는 자리를 하나 두는 편이
 *    실수할 자리가 적다. */
let DAY_MS, STALE_DAYS, FLOW_WEEKS, RECENT_PAGE, DOC_TYPES, BOARD_COLUMNS, STAGE_ALIASES, isUserNote, fm, localDate, dayStart, bearsTasks, openTasks, openTasksInVault, buildFlow, weeklyBars, parseDue, daysBetween, isStale, relativeDays, normalizeStage, todayDevlog, collect;

let CAPTURES, SEARCH_PLUGINS, CORE_SEARCH, SEARCH_VERBS, SEARCH_TARGETS, SEARCH_EXCLUDE, templaterCommandId, captureFile, commandExists, findSearchCommand, searchRunner, hotkeyLabel, isSubmitKey;

let TEXT, textFor;
/* 화면 클래스는 모듈을 다 받은 뒤에야 만들어진다 — 그래서 let 이다. */
let CommandCenterView, QuickCaptureModal;

function bindModules(m) {
  // ⚠️ 대입을 **먼저** 끝낸다. 화면 factory 에 이름을 넘길 때 그 이름들이
  //    아직 undefined 면 조용히 undefined 가 건네지고, 화면은 부르는
  //    순간에야 죽는다 — 2026-08-23 에 hotkeyLabel 이 그랬다:
  //      TypeError: hotkeyLabel is not a function (nav)
  RM = m.model;
  TEXT = m.i18n.TEXT;
  textFor = m.i18n.textFor;
  CAPTURES = m.cmds.CAPTURES;
  SEARCH_PLUGINS = m.cmds.SEARCH_PLUGINS;
  CORE_SEARCH = m.cmds.CORE_SEARCH;
  SEARCH_VERBS = m.cmds.SEARCH_VERBS;
  SEARCH_TARGETS = m.cmds.SEARCH_TARGETS;
  SEARCH_EXCLUDE = m.cmds.SEARCH_EXCLUDE;
  templaterCommandId = m.cmds.templaterCommandId;
  captureFile = m.cmds.captureFile;
  commandExists = m.cmds.commandExists;
  findSearchCommand = m.cmds.findSearchCommand;
  searchRunner = m.cmds.searchRunner;
  hotkeyLabel = m.cmds.hotkeyLabel;
  isSubmitKey = m.cmds.isSubmitKey;
  DAY_MS = m.model.DAY_MS;
  STALE_DAYS = m.model.STALE_DAYS;
  FLOW_WEEKS = m.model.FLOW_WEEKS;
  RECENT_PAGE = m.model.RECENT_PAGE;
  DOC_TYPES = m.model.DOC_TYPES;
  BOARD_COLUMNS = m.model.BOARD_COLUMNS;
  STAGE_ALIASES = m.model.STAGE_ALIASES;
  isUserNote = m.model.isUserNote;
  fm = m.model.fm;
  localDate = m.model.localDate;
  dayStart = m.model.dayStart;
  bearsTasks = m.model.bearsTasks;
  openTasks = m.model.openTasks;
  openTasksInVault = m.model.openTasksInVault;
  buildFlow = m.model.buildFlow;
  weeklyBars = m.model.weeklyBars;
  parseDue = m.model.parseDue;
  daysBetween = m.model.daysBetween;
  isStale = m.model.isStale;
  relativeDays = m.model.relativeDays;
  normalizeStage = m.model.normalizeStage;
  todayDevlog = m.model.todayDevlog;
  collect = m.model.collect;

  // ⚠️ 화면에 필요한 것을 **명시적으로** 넘긴다. 전역으로 새어 들어가면
  //    무엇이 무엇에 기대는지 아무도 모르게 된다.
  const view = m.makeView({
    // ⚠️ obsidian 을 넘긴다. 절대 경로로 불러온 모듈은 그 이름을 못 푼다 —
    //    플러그인 진입점에서만 풀리는 이름이다.
    obsidian,
    DAY_MS, STALE_DAYS, FLOW_WEEKS, RECENT_PAGE, BOARD_COLUMNS,
    isUserNote, localDate, openTasks, openTasksInVault, buildFlow, weeklyBars,
    parseDue, isStale, relativeDays, daysBetween, normalizeStage, todayDevlog, collect,
    CAPTURES, CORE_SEARCH, templaterCommandId, captureFile, commandExists,
    findSearchCommand, searchRunner, hotkeyLabel, isSubmitKey,
    icon, isMainLeaf, readPathMap, VIEW_TYPE, PLUGIN_ID, PATH_MAP_FILE, textFor,
  });
  CommandCenterView = view.CommandCenterView;
  QuickCaptureModal = view.QuickCaptureModal;
}


/* ── 경로 맵 ──────────────────────────────────────────────────────────────
 *
 * DevTrail CLI 가 템플릿 폴더에 만드는 노트다. 안에 json 코드블록이 하나
 * 있고, 거기에 볼트의 모든 경로·프로젝트·언어가 들어 있다.
 * 노트 템플릿들도 같은 파일을 읽는다 — 그래서 출처가 하나다.
 */
async function readPathMap(app) {
  const file = app.vault.getFiles().find((f) => f.name === PATH_MAP_FILE);
  if (!file) return { ok: false, reason: 'missing' };
  try {
    const raw = await app.vault.read(file);
    const m = raw.match(/```json\s*([\s\S]*?)```/);
    if (!m) return { ok: false, reason: 'malformed' };
    const data = JSON.parse(m[1]);
    if (!data || typeof data.paths !== 'object') {
      return { ok: false, reason: 'malformed' };
    }
    return { ok: true, data };
  } catch (e) {
    return { ok: false, reason: 'malformed' };
  }
}






/* leaf 가 메인 워크스페이스에 있는가.
 *
 * ⚠️ Obsidian 은 메인 영역과 좌·우 사이드독을 각각 다른 루트로 관리한다.
 *    leaf.getRoot() 가 workspace.rootSplit 과 같으면 메인이다.
 *
 * ⚠️ 이게 없으면 getLeavesOfType 이 사이드에 남아 있던 옛 뷰를 찾아 그걸
 *    재사용한다. 메인 탭으로 여는 코드가 아예 실행되지 않는다 — Phase 1·2 를
 *    써본 사람은 갱신해도 화면이 옛 자리에 그대로 있었다(2026-08-22 확인).
 */
function isMainLeaf(leaf, rootSplit) {
  if (!leaf || typeof leaf.getRoot !== 'function') return false;
  return leaf.getRoot() === rootSplit;
}



















/* 손을 놓은 지 오래됐는가.
 *
 * ⚠️ 모르면 방치라고 하지 않는다. 수정 시각을 못 읽은 것과 오래 안 건드린
 *    것은 다른 사실이다 — 지어낸 경고는 사람을 무디게 만든다.
 * ⚠️ 경계는 '넘었을 때' 다. 딱 14일은 아직 아니다. */
/* "1일 전" · "31일 전". 오늘은 "오늘".
 *
 * ⚠️ 절대 날짜를 쓰지 않는다 — 표에서 중요한 건 '얼마나 손을 놨나' 이지
 *    '언제였나' 가 아니다. */













/* 모듈을 못 불러왔을 때의 화면.
 *
 * ⚠️ 빈 화면을 띄우지 않는다. 무엇이 왜 안 되는지, 무엇을 하면 되는지 말한다. */
class LoadFailureView extends obsidian.ItemView {
  constructor(leaf, plugin) {
    super(leaf);
    this.plugin = plugin;
  }

  getViewType() { return VIEW_TYPE; }
  getDisplayText() { return 'DevTrail'; }
  getIcon() { return 'alert-triangle'; }

  async onOpen() {
    const root = this.contentEl;
    root.empty();
    root.addClass('devtrail-command-center');
    const box = root.createEl('div', { cls: 'devtrail-cc-recovery' });
    box.createEl('p', { text: 'DevTrail 플러그인 파일을 불러오지 못했습니다' });
    if (this.plugin && this.plugin.loadError) {
      box.createEl('p', { text: this.plugin.loadError, cls: 'devtrail-cc-muted' });
    }
    box.createEl('p', {
      text: '터미널에서 devtrail command-center install --apply 를 실행한 뒤 Obsidian 을 다시 여세요.',
      cls: 'devtrail-cc-muted',
    });
  }

  async onClose() { this.contentEl.empty(); }
}

module.exports = class DevTrailCommandCenter extends obsidian.Plugin {
  async onload() {
    // ⚠️ 모듈을 가장 먼저 묶는다. 실패하면 뷰를 등록하지 않고 이유를 남긴다 —
    //    빈 대시보드는 사용자에게 아무것도 말해 주지 않는다.
    try {
      bindModules(loadModules(this));
    } catch (e) {
      this.loadError = (e && e.message) ? e.message : String(e);
      console.error('[DevTrail] 읽기 모델을 불러오지 못했습니다:', e);
      new obsidian.Notice(
        `DevTrail: 플러그인 파일을 불러오지 못했습니다.\n${this.loadError}\n` +
        '터미널에서 devtrail command-center install --apply 를 실행한 뒤 Obsidian 을 다시 여세요.',
        0,
      );
    }

    // ⚠️ 실패해도 뷰를 등록한다. 등록하지 않으면 사용자가 ⌘⇧Y 를 눌러도
    //    아무 일이 안 일어나고, 무엇이 잘못됐는지 알 길이 없다.
    //
    // ⚠️ 이 안내는 여기 있어야 한다. 화면 모듈은 로딩이 성공해야 존재하므로
    //    거기서 '안 붙었으면' 을 검사하는 것은 애초에 닿지 않는다 —
    //    실제로 그렇게 만들었다가 render 가 ReferenceError 로 죽어 화면이
    //    **빈 채로** 떴다(2026-08-23). 오류가 보이는 것보다 나쁘다.
    this.registerView(VIEW_TYPE, (leaf) =>
      CommandCenterView ? new CommandCenterView(leaf) : new LoadFailureView(leaf, this));

    this.addRibbonIcon('layout-dashboard', 'DevTrail', () => this.activate());
    this.addCommand({
      id: 'open',
      name: 'Open DevTrail Command Center',
      callback: () => this.activate(),
    });

    // ⚠️ 빠른 기록에도 명령을 준다. 그래야 사용자가 설정에서 단축키를 배정할
    //    수 있고, 화면이 **실제 배정된 것**을 읽어 보여줄 수 있다.
    this.addCommand({
      id: 'quick-capture',
      name: 'DevTrail: Quick capture',
      callback: () => {
        const view = this.app.workspace.getLeavesOfType(VIEW_TYPE)
          .map((l) => l.view).filter(Boolean)[0];
        if (view && typeof view.openQuickCapture === 'function') {
          view.openQuickCapture(textFor(view.lang || 'ko'));
        }
      },
    });

    // ⚠️ Obsidian 은 시작할 때 workspace.json 의 레이아웃을 복원한다.
    //    예전 버전이 사이드독에 열어둔 뷰가 거기 저장돼 있어서, 재시작하면
    //    activate() 를 거치지 않고 사이드에 그대로 되살아난다.
    //    실측: workspace.json 의 right 에 뷰가 1개 있었다(2026-08-22).
    //    레이아웃이 준비되는 시점에 스스로 옮긴다.
    this.app.workspace.onLayoutReady(() => this.relocateIfSide());
  }

  /* 사이드독에 복원된 뷰를 메인 탭으로 옮긴다.
   *
   * ⚠️ 사용자가 일부러 사이드로 끌어다 놓았을 수도 있다. 그래서 '열려 있던
   *    것을 옮기는' 것은 한 번뿐이고(설정에 기록), 그 뒤에는 존중한다. */
  async relocateIfSide() {
    const { workspace } = this.app;
    const open = workspace.getLeavesOfType(VIEW_TYPE);
    if (open.length === 0) return;
    if (open.some((l) => isMainLeaf(l, workspace.rootSplit))) return;

    const data = (await this.loadData()) || {};
    if (data.relocated) return;              // 한 번만. 그 뒤엔 사용자 뜻이다.

    for (const l of open) l.detach();
    const leaf = workspace.getLeaf('tab');
    if (leaf) {
      await leaf.setViewState({ type: VIEW_TYPE, active: true });
      workspace.revealLeaf(leaf);
    }
    await this.saveData(Object.assign({}, data, { relocated: true }));
  }

  onunload() {
    // ⚠️ 열려 있던 뷰를 정리한다. 남겨두면 플러그인을 끈 뒤에도 빈 탭이 남는다.
    this.app.workspace.detachLeavesOfType(VIEW_TYPE);
  }

  async activate() {
    const { workspace } = this.app;
    const open = workspace.getLeavesOfType(VIEW_TYPE);

    // 메인에 이미 있으면 그걸 보여준다.
    const main = open.find((l) => isMainLeaf(l, workspace.rootSplit));
    if (main) { workspace.revealLeaf(main); return; }

    // ⚠️ 사이드에 남아 있는 것은 재사용하지 않고 닫는다. 예전 버전이 거기에
    //    열어둔 것이라, 그대로 두면 같은 화면이 둘이 된다.
    for (const l of open) l.detach();
    // ⚠️ 메인 워크스페이스 탭으로 연다. 사이드 패널(폭 300px)에는 정보
    //    밀도를 담을 수 없다.
    //    getLeaf(true) 가 아니라 getLeaf('tab') 이다 — true 는 "새 leaf 를
    //    강제" 라는 뜻이고, 우리가 원하는 건 "메인 영역의 탭" 이다.
    //    Obsidian 자신이 getLeaf("tab") · getLeaf("split") 을 쓴다.
    const leaf = workspace.getLeaf('tab');
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    workspace.revealLeaf(leaf);
  }
};

/* 테스트가 부르는 순수 함수들.
 *
 * ⚠️ 화면 없이 확인할 수 있는 것은 화면 없이 확인한다. 제외 규칙이 틀리면
 *    카드가 지어낸 데이터를 보고하는데, 그건 눈으로만 보면 놓친다. */
module.exports.__test = { TEXT, loadModules, MODEL_KEYS, COMMAND_KEYS, isSubmitKey, hotkeyLabel, searchRunner, localDate, bearsTasks, weeklyBars, parseDue, buildFlow, isStale, STALE_DAYS, FLOW_WEEKS, collect, fm, openTasks, isUserNote, normalizeStage, BOARD_COLUMNS, templaterCommandId, captureFile, CAPTURES, isMainLeaf, findSearchCommand, SEARCH_PLUGINS };
