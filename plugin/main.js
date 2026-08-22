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

const VIEW_TYPE = 'devtrail-command-center';

/* 아이콘. Obsidian 이 번들한 lucide 이름만 쓴다 — 아이콘 파일을 들고
 * 다니면 그것도 유지할 물건이 된다. */
function icon(el, name) {
  if (obsidian.setIcon) obsidian.setIcon(el, name);
}
const PATH_MAP_FILE = '_devtrail-paths.md';

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

/* ── 읽기 모델 ────────────────────────────────────────────────────────────
 *
 * ⚠️ 볼트에는 '노트처럼 생겼지만 노트가 아닌 것' 이 많다. 실측(QA 볼트):
 *
 *      type: project-home    6건 — 그중 2건이 템플릿
 *      status: inbox         2건 — 둘 다 템플릿
 *
 *    템플릿을 세면 빈 볼트에서도 "프로젝트 2개" 가 뜬다. 그게 지어낸
 *    데이터다. 제외 규칙은 화면 장식이 아니라 계약이다.
 *
 * ⚠️ v1 은 기존 frontmatter 만 읽는다. priority·due 같은 필드를 새로
 *    만들지 않는다 — 커버리지가 고르지 않아 빈 화면이 되고, 사용자에게
 *    노트 마이그레이션을 강요하게 된다.
 */
function isUserNote(path, paths) {
  const name = path.split('/').pop() || '';
  if (name.startsWith('_')) return false;          // _devtrail-*, _index
  if (name === '_index.md') return false;
  const tpl = paths && paths.templates;
  if (tpl && (path === tpl || path.startsWith(tpl + '/'))) return false;
  return true;
}

/* frontmatter 는 Obsidian 의 메타데이터 캐시에서 읽는다. 직접 파싱하면
 * 같은 것을 두 번 파싱하는 셈이고, Obsidian 이 이미 정확히 해준다. */
function fm(app, file) {
  const c = app.metadataCache.getFileCache(file);
  return (c && c.frontmatter) || {};
}

function collect(app, paths) {
  const files = app.vault.getMarkdownFiles().filter((f) => isUserNote(f.path, paths));

  const projects = [];
  const inbox = [];
  const overdue = [];
  const trouble = [];
  const today = new Date().toISOString().slice(0, 10);

  for (const f of files) {
    const meta = fm(app, f);
    const type = meta.type;

    if (type === 'project-home' && meta.status === 'active') {
      projects.push({
        file: f,
        name: meta.project || f.parent?.name || f.basename,
        stage: meta.stage || null,
        next: meta.next_action || null,
        mtime: f.stat.mtime,
      });
    }

    if (type === 'trouble' || type === 'troubleshooting') {
      trouble.push({ file: f, status: meta.status || null, mtime: f.stat.mtime });
    }

    if (meta.status === 'inbox') {
      inbox.push({ file: f, created: meta.created || null, mtime: f.stat.mtime });
    }

    // 다시 볼 때가 된 것. 날짜가 오늘 이전이면 지났다.
    if (meta.review_at && String(meta.review_at).slice(0, 10) <= today) {
      overdue.push({ file: f, at: String(meta.review_at).slice(0, 10) });
    }
  }

  // 이번 주(월요일 기준)에 만들어진 노트. 사용자가 "얼마나 남겼나" 를 본다.
  const weekAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;
  const thisWeek = files.filter((f) => f.stat.ctime >= weekAgo).length;

  projects.sort((a, b) => b.mtime - a.mtime);
  inbox.sort((a, b) => a.mtime - b.mtime);       // 오래된 것 먼저
  overdue.sort((a, b) => (a.at < b.at ? -1 : 1));

  // 최근 기록 — 무엇을 하고 있었는지 되짚는다.
  const recent = files
    .slice()
    .sort((a, b) => b.stat.mtime - a.stat.mtime)
    .slice(0, 10)
    .map((f) => ({ file: f, type: fm(app, f).type || null, mtime: f.stat.mtime }));

  return { projects, inbox, overdue, trouble, recent, thisWeek, total: files.length };
}

/* 오늘 개발일지. 경로는 맵에서만 온다 — 파일명 규칙도 맵이 갖고 있다. */
function todayDevlog(app, data) {
  const dir = data.paths && data.paths.devlog;
  if (!dir) return null;
  const pat = (data.naming && data.naming.devlog_file) || '{{DATE}} devlog.md';
  const name = pat.replace('{{DATE}}', new Date().toISOString().slice(0, 10));
  const path = `${dir}/${name}`;
  return app.vault.getAbstractFileByPath(path) || null;
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
function findCommandByPluginId(app, pluginId) {
  const all = (app.commands && app.commands.commands) || {};
  const ids = Object.keys(all).filter((id) => id.startsWith(pluginId + ':'));
  if (ids.length === 0) return null;
  // 검색 플러그인의 주 명령을 고른다. 이름으로 고르는 것이라 id 가 바뀌어도
  // 견딘다. 못 고르면 첫 번째를 쓰고, 무엇을 실행할지 화면에 보여준다.
  const preferred =
    ids.find((id) => /(^|:)open/.test(id)) ||
    ids.find((id) => /search/i.test(id)) ||
    ids[0];
  return { id: preferred, name: (all[preferred] && all[preferred].name) || preferred };
}

/* ── 프로젝트 보드 ──────────────────────────────────────────────────────────
 *
 * 카드 하나 = 프로젝트 노트 하나다. 개발일지 체크박스를 카드로 만들지 않는다 —
 * 같은 일을 두 곳에 적으면 어느 쪽도 믿을 수 없게 된다. 오늘 할 일은 개발일지가,
 * 프로젝트 상태는 이 보드가 맡는다.
 *
 * ⚠️ 읽기 전용이다. 카드를 끌어 frontmatter 를 고치는 것은 다음 Phase다 —
 *    노트를 고치는 순간 이 플러그인은 '두 번째 쓰기 출처' 가 된다.
 *
 * [키, 아이콘, 상태색 이름]
 */
const BOARD_COLUMNS = [
  ['planning', 'clipboard-list', 'planning'],
  ['active',   'play-circle',    'active'],
  ['blocked',  'alert-triangle', 'blocked'],
  ['done',     'check-circle-2', 'done'],
];

/* frontmatter 의 stage 를 컬럼으로 옮긴다.
 *
 * ⚠️ 모르는 값을 임의 컬럼에 넣지 않는다. 사용자가 지정하지 않은 상태를
 *    '계획 중' 이라고 보여주면 화면이 사실이 아닌 것을 말한다. null 을 돌려주고
 *    화면은 그것을 '단계 미지정' 으로 따로 모은다 — 채우라고 말하기 위해서다. */
const STAGE_ALIASES = {
  planning: 'planning', planned: 'planning', plan: 'planning',
  'in-progress': 'active', in_progress: 'active', active: 'active', doing: 'active',
  blocked: 'blocked',
  done: 'done', completed: 'done', complete: 'done', archived: 'done',
};

function normalizeStage(raw) {
  if (typeof raw !== 'string') return null;
  const key = raw.trim().toLowerCase();
  if (!key) return null;
  return STAGE_ALIASES[key] || null;
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

/* 화면 문구. 한국어·영어만 있고, 그 외에는 한국어로 떨어진다 —
 * CLI 의 dt_lang 과 같은 규칙이다. */
const TEXT = {
  ko: {
    title: 'DevTrail',
    loading: '읽는 중…',
    missing: 'DevTrail 경로 맵을 찾지 못했습니다',
    missingHelp: '터미널에서 devtrail obsidian 을 한 번 실행하세요.',
    malformed: '경로 맵을 읽지 못했습니다',
    malformedHelp: '터미널에서 devtrail doctor 로 확인하세요.',
    vaultRoot: '루트',
    projects: '활성 프로젝트',
    inbox: '정리할 Inbox',
    overdue: '다시 볼 때가 된 것',
    devlog: '오늘 개발일지',
    devlogYes: '있습니다',
    devlogNo: '아직 없습니다',
    emptyAll: '아직 쌓인 것이 없습니다',
    emptyAllHelp: '노트를 만들면 여기에 모입니다.',
    emptyProjects: '아직 프로젝트가 없습니다',
    emptyProjectsHelp: '기록 탭의 [프로젝트] 로 하나 만들어 보세요.',
    col: { planning: '계획 중', active: '진행 중', blocked: '막힘', done: '완료 · 보관' },
    emptyColumn: {
      planning: '계획 중인 프로젝트가 없습니다',
      active: '진행 중인 것이 없습니다 — stage 를 in-progress 로 바꾸면 여기 옵니다',
      blocked: '막힌 것이 없습니다',
      done: '아직 완료한 것이 없습니다',
    },
    unstaged: '단계 미지정',
    unstagedHelp: '노트 앞머리의 stage 에 planning · in-progress · blocked · done 중 하나를 적어주세요.',
    noNext: '다음 행동 없음',
    emptyInbox: '정리할 것이 없습니다',
    emptyOverdue: '다시 볼 것이 없습니다',
    stage: '단계',
    next: '다음',
    open: '열기',
    navHome: '홈', navToday: '오늘', navCapture: '기록',
    navProjects: '프로젝트', navReviews: '리뷰',
    tasks: '오늘 할 일',
    noTasks: '체크박스가 없습니다',
    openDevlog: '개발일지 열기',
    makeDevlog: '개발일지 만들기',
    captureHelp: '무엇을 남기시겠습니까',
    cDevlog: '개발일지', cDevnote: '개발메모', cIdea: '아이디어',
    cWorklog: '워크로그', cReport: '회고', cProject: '프로젝트',
    notReady: '이 명령이 아직 준비되지 않았습니다',
    notReadyHelp: '터미널에서 devtrail obsidian 을 실행하고 Obsidian 을 재시작하세요.',
    weekly: '이번 주 주간리뷰',
    weeklyNo: '아직 없습니다',
    makeWeekly: '터미널에서: devtrail weekly',
    greetMorning: '좋은 아침입니다', greetAfternoon: '좋은 오후입니다',
    greetEvening: '수고하셨습니다',
    week: '주차',
    mDevlog: '오늘 일지', mProjects: '활성 프로젝트', mInbox: 'Inbox',
    mWeek: '이번 주 노트', mTrouble: '트러블슈팅', mOverdue: '다시 볼 것',
    colToday: '오늘 현황', lastEdit: '마지막 수정', colProjects: '활성 프로젝트', colRecent: '최근 기록',
    hDevlog: '오늘 개발일지가 있는지', hProjects: 'status 가 active 인 프로젝트',
    hInbox: '아직 정리하지 않은 포착물', hWeek: '최근 7일에 만든 노트',
    hTrouble: '기록해 둔 트러블슈팅', hOverdue: 'review_at 이 지난 노트',
    actionMissing: '명령이 없습니다 — 터미널에서 devtrail obsidian 을 실행하고 Obsidian 을 다시 여세요.',
    quickCapture: '빠른 기록',
    search: '검색',
    searchPlaceholder: '전체 검색',
    searchCore: 'Obsidian 검색',
    searchMissing: 'Omnisearch 가 설치되어 있지 않습니다',
    searchMissingHelp: 'Obsidian 설정 → 커뮤니티 플러그인에서 설치하면 여기에 연결됩니다. 기본 검색은 ⌘O · ⌘⇧F 입니다.',
    yes: '있음', no: '없음',
  },
  en: {
    title: 'DevTrail',
    loading: 'Reading…',
    missing: 'Could not find the DevTrail path map',
    missingHelp: 'Run devtrail obsidian once in a terminal.',
    malformed: 'Could not read the path map',
    malformedHelp: 'Check it with devtrail doctor in a terminal.',
    vaultRoot: 'Root',
    projects: 'Active projects',
    inbox: 'Inbox to sort',
    overdue: 'Due for another look',
    devlog: "Today's devlog",
    devlogYes: 'exists',
    devlogNo: 'not yet',
    emptyAll: 'Nothing here yet',
    emptyAllHelp: 'Notes you create show up here.',
    emptyProjects: 'No projects yet',
    emptyProjectsHelp: 'Create one from [Project] on the Capture tab.',
    col: { planning: 'Planning', active: 'In progress', blocked: 'Blocked', done: 'Done · Archived' },
    emptyColumn: {
      planning: 'Nothing in planning',
      active: 'Nothing in progress — set stage to in-progress to move a project here',
      blocked: 'Nothing is blocked',
      done: 'Nothing finished yet',
    },
    unstaged: 'Stage not set',
    unstagedHelp: 'Set stage in the note frontmatter to planning, in-progress, blocked or done.',
    noNext: 'No next action',
    emptyInbox: 'Nothing to sort',
    emptyOverdue: 'Nothing to revisit',
    stage: 'Stage',
    next: 'Next',
    open: 'Open',
    navHome: 'Home', navToday: 'Today', navCapture: 'Capture',
    navProjects: 'Projects', navReviews: 'Reviews',
    tasks: "Today's tasks",
    noTasks: 'No checkboxes',
    openDevlog: "Open today's devlog",
    makeDevlog: "Create today's devlog",
    captureHelp: 'What would you like to record',
    cDevlog: 'Devlog', cDevnote: 'Dev note', cIdea: 'Idea',
    cWorklog: 'Worklog', cReport: 'Retro', cProject: 'Project',
    notReady: 'That command is not ready yet',
    notReadyHelp: 'Run devtrail obsidian in a terminal, then restart Obsidian.',
    weekly: "This week's review",
    weeklyNo: 'not yet',
    makeWeekly: 'In a terminal: devtrail weekly',
    greetMorning: 'Good morning', greetAfternoon: 'Good afternoon',
    greetEvening: 'Good evening',
    week: 'Week',
    mDevlog: "Today's log", mProjects: 'Active projects', mInbox: 'Inbox',
    mWeek: 'Notes this week', mTrouble: 'Troubleshooting', mOverdue: 'To revisit',
    colToday: 'Today', lastEdit: 'Last edit', colProjects: 'Active projects', colRecent: 'Recent',
    hDevlog: 'Whether today has a devlog', hProjects: 'Projects with status active',
    hInbox: 'Captures you have not sorted yet', hWeek: 'Notes created in the last 7 days',
    hTrouble: 'Troubleshooting notes you kept', hOverdue: 'Notes past their review_at',
    actionMissing: 'No such command — run devtrail obsidian, then reopen Obsidian.',
    quickCapture: 'Quick capture',
    search: 'Search',
    searchPlaceholder: 'Search everything',
    searchCore: 'Obsidian search',
    searchMissing: 'Omnisearch is not installed',
    searchMissingHelp: 'Install it in Settings → Community plugins and it will be linked here. Built-in search is ⌘O · ⌘⇧F.',
    yes: 'yes', no: 'no',
  },
};

function textFor(lang) {
  return TEXT[lang === 'en' ? 'en' : 'ko'];
}

class CommandCenterView extends obsidian.ItemView {
  route = 'home';

  getViewType() { return VIEW_TYPE; }
  getDisplayText() { return 'DevTrail'; }
  getIcon() { return 'layout-dashboard'; }

  async onOpen() {
    await this.render();
  }

  async render() {
    const root = this.contentEl;
    root.empty();
    root.addClass('devtrail-command-center');

    const map = await readPathMap(this.app);
    const t = textFor(map.ok ? map.data.lang : 'ko');

    const head = root.createEl('div', { cls: 'devtrail-cc-header' });
    const now = new Date();
    const h = now.getHours();
    const greet = h < 12 ? t.greetMorning : h < 18 ? t.greetAfternoon : t.greetEvening;
    const left = head.createEl('div');
    left.createEl('h2', { text: greet });
    left.createEl('p', { text: t.title, cls: 'devtrail-cc-muted' });
    // ⚠️ 날짜는 사용자의 지역 형식으로. YYYY-MM-DD 를 박으면 그 형식을 쓰지
    //    않는 사람에게 낯설다.
    const right = head.createEl('div', { cls: 'devtrail-cc-header-right' });
    right.createEl('div', {
      text: now.toLocaleDateString(map.ok && map.data.lang === 'en' ? 'en-US' : 'ko-KR',
        { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' }),
    });

    if (!map.ok) {
      // ⚠️ 여기서 경로를 짐작하지 않는다. 무엇을 실행해야 하는지 말한다.
      const box = root.createEl('div', { cls: 'devtrail-cc-recovery' });
      const isMissing = map.reason === 'missing';
      box.createEl('p', { text: isMissing ? t.missing : t.malformed });
      box.createEl('p', {
        text: isMissing ? t.missingHelp : t.malformedHelp,
        cls: 'devtrail-cc-muted',
      });
      return;
    }

    this.searchBar(root, t);
    this.launchBar(root, t, map.data);
    this.nav(root, t);

    const model = collect(this.app, map.data.paths);
    const devlog = todayDevlog(this.app, map.data);
    const body = root.createEl('div', { cls: 'devtrail-cc-body' });

    // 라우트마다 한 가지 질문에 답한다. 홈은 전체를 훑는다.
    if (this.route === 'today')    return this.viewToday(body, t, map.data, devlog);
    if (this.route === 'capture')  return this.viewCapture(body, t, map.data);
    if (this.route === 'projects') return this.viewProjects(body, t, model);
    if (this.route === 'reviews')  return this.viewReviews(body, t, map.data, model);

    // ⚠️ 빈 볼트에 0 을 늘어놓지 않는다. 대시보드가 아니라 안내가 되어야 한다.
    const nothing =
      model.projects.length === 0 && model.inbox.length === 0 &&
      model.overdue.length === 0 && model.trouble.length === 0 && !devlog;
    if (nothing) {
      const e = body.createEl('div', { cls: 'devtrail-cc-empty' });
      e.createEl('p', { text: t.emptyAll });
      e.createEl('p', { text: t.emptyAllHelp, cls: 'devtrail-cc-muted' });
      return;
    }

    this.metrics(body, t, model, devlog);

    // 3열. 좁아지면 CSS 가 열을 줄인다 — 사이드 패널에서도 깨지지 않는다.
    const cols = body.createEl('div', { cls: 'devtrail-cc-columns' });

    this.card(cols, t.colToday, devlog ? 1 : 0, (list) => {
      if (!devlog) { list.createEl('p', { text: t.devlogNo, cls: 'devtrail-cc-muted' }); return; }
      this.row(list, devlog.basename, devlog, t.open);
    });

    this.card(cols, t.colProjects, model.projects.length, (list) => {
      if (model.projects.length === 0) {
        list.createEl('p', { text: t.emptyProjects, cls: 'devtrail-cc-muted' }); return;
      }
      for (const p of model.projects.slice(0, 6)) this.projectRow(list, t, p);
    });

    this.card(cols, t.colRecent, model.recent.length, (list) => {
      for (const r of model.recent.slice(0, 8)) {
        const el = list.createEl('div', { cls: 'devtrail-cc-row' });
        const a = el.createEl('a', { text: r.file.basename, cls: 'devtrail-cc-link' });
        a.setAttr('role', 'button'); a.setAttr('tabindex', '0');
        const open = () => this.app.workspace.getLeaf(false).openFile(r.file);
        a.addEventListener('click', open);
        a.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });
        if (r.type) this.badge(el, r.type, 'type');
      }
    });

  }

  /* ── 지표 ─────────────────────────────────────────────────────────────
   * ⚠️ DevTrail 개념만 센다. Meetings·Events·Focus 같은 것을 넣으면 볼트에
   *    그 개념이 없어 전부 0 이 뜬다(실측: meeting 0 · event 0 · task 0).
   *    0 만 늘어놓는 화면은 지어낸 화면이다. */
  metrics(body, t, model, devlog) {
    const strip = body.createEl('div', { cls: 'devtrail-cc-metrics' });
    // [라벨, 값, 아이콘, 보조설명, 이동할 라우트, 주의 여부]
    const items = [
      [t.mDevlog,   devlog ? t.yes : t.no, 'calendar-days', t.hDevlog,   'today',    !devlog],
      [t.mProjects, model.projects.length, 'folder-git-2', t.hProjects, 'projects', false],
      [t.mInbox,    model.inbox.length,    'inbox',        t.hInbox,    'home',     model.inbox.length > 0],
      [t.mWeek,     model.thisWeek,        'file-text',    t.hWeek,     'home',     false],
      [t.mTrouble,  model.trouble.length,  'wrench',       t.hTrouble,  'home',     false],
      [t.mOverdue,  model.overdue.length,  'alarm-clock',  t.hOverdue,  'reviews',  model.overdue.length > 0],
    ];
    for (const [label, value, ic, help, route, warn] of items) {
      // ⚠️ 지표는 '눌러서 갈 곳' 이 있어야 숫자가 행동으로 이어진다.
      const c = strip.createEl('button', { cls: 'devtrail-cc-metric' });
      c.setAttr('aria-label', `${label}: ${value} — ${help}`);
      c.setAttr('title', help);
      if (warn) c.addClass('is-attention');
      const head = c.createEl('div', { cls: 'devtrail-cc-metric-head' });
      icon(head.createEl('span', { cls: 'devtrail-cc-metric-icon' }), ic);
      head.createEl('span', { text: label, cls: 'devtrail-cc-metric-label' });
      c.createEl('div', { text: String(value), cls: 'devtrail-cc-metric-value' });
      c.createEl('div', { text: help, cls: 'devtrail-cc-metric-help' });
      c.addEventListener('click', () => this.metricRoute(route));
    }
  }

  /* 지표에서 라우트로. 숫자를 보고 바로 갈 수 있어야 한다. */
  metricRoute(route) {
    if (!route || route === this.route) return;
    this.route = route;
    this.render();
  }

  /* ── 빠른 기록 ────────────────────────────────────────────────────────
   * 기존 Templater 명령을 부른다. 여기서 노트를 만들지 않는다. */
  /* ⚠️ 빠른 기록 카드와 하단 검색 안내를 지웠다. 헤더의 검색 바와 빠른 실행
   *    바가 같은 일을 하고, 둘이 서로 다른 말을 하고 있었다 — 위는
   *    "Obsidian 검색", 아래는 "Omnisearch 가 없습니다". 한 화면에서 같은
   *    질문에 두 번 답하면 사용자는 어느 쪽을 믿을지 모른다. */

  /* 화면 맨 위의 검색 진입점.
   *
   * ⚠️ 검색기를 만들지 않는다. Obsidian 이 이미 갖고 있고, Omnisearch 가 있으면
   *    그쪽이 더 낫다. 여기 있는 것은 '통로' 뿐이다 — 결과 목록을 흉내 내면
   *    없는 기능을 있는 척하게 된다.
   * ⚠️ 명령 id 를 짐작해서 부르지 않는다. 레지스트리에 있는지 먼저 확인한다. */
  searchBar(root, t) {
    let found = null;
    for (const pid of SEARCH_PLUGINS) {
      found = findCommandByPluginId(this.app, pid);
      if (found) break;
    }
    // Omnisearch 가 없으면 Obsidian 기본 검색으로 떨어진다 — 있을 때만.
    if (!found && commandExists(this.app, CORE_SEARCH)) {
      found = { id: CORE_SEARCH, name: t.searchCore };
    }

    const bar = root.createEl('div', { cls: 'devtrail-cc-search' });
    const b = bar.createEl('button', { cls: 'devtrail-cc-search-btn' });
    icon(b.createEl('span', { cls: 'devtrail-cc-search-icon' }), 'search');
    b.createEl('span', {
      text: found ? `${t.searchPlaceholder} — ${found.name}` : t.searchMissing,
      cls: 'devtrail-cc-search-text',
    });

    if (!found) {
      b.setAttr('disabled', 'true');
      b.setAttr('title', t.searchMissingHelp);
      bar.createEl('p', { text: t.searchMissingHelp, cls: 'devtrail-cc-muted' });
      return;
    }
    b.setAttr('aria-label', `${t.search}: ${found.name}`);
    b.setAttr('title', found.id);
    b.addEventListener('click', () => this.app.commands.executeCommandById(found.id));
  }

  /* 자주 쓰는 기록으로 가는 아이콘 바. 검색 바로 아래 — 찾기 다음은 남기기다.
   *
   * ⚠️ 노트를 직접 만들지 않는다. 등록된 Templater 명령만 부른다. */
  launchBar(root, t, data) {
    const bar = root.createEl('div', { cls: 'devtrail-cc-launch' });
    bar.setAttr('aria-label', t.quickCapture);
    const labels = {
      devlog: t.cDevlog, devnote: t.cDevnote, idea: t.cIdea,
      worklog: t.cWorklog, report: t.cReport, project: t.cProject,
    };
    const icons = {
      devlog: 'calendar-days', devnote: 'pencil', idea: 'lightbulb',
      worklog: 'clock', report: 'rotate-ccw', project: 'folder-plus',
    };
    for (const c of CAPTURES) {
      const id = templaterCommandId(data.paths, captureFile(c, data.lang));
      const b = bar.createEl('button', { cls: 'devtrail-cc-launch-btn' });
      icon(b.createEl('span'), icons[c.key] || 'file-plus');
      b.createEl('span', { text: labels[c.key] || c.key });
      if (!commandExists(this.app, id)) {
        b.setAttr('disabled', 'true');
        b.setAttr('title', t.actionMissing);
        continue;
      }
      b.setAttr('title', labels[c.key] || c.key);
      b.addEventListener('click', () => this.app.commands.executeCommandById(id));
    }
  }

  /* ── 네비게이션 ─────────────────────────────────────────────────────── */
  nav(root, t) {
    const bar = root.createEl('nav', { cls: 'devtrail-cc-nav' });
    bar.setAttr('aria-label', t.title);
    const items = [
      ['home', t.navHome, 'layout-dashboard'],
      ['today', t.navToday, 'sun'],
      ['capture', t.navCapture, 'plus-circle'],
      ['projects', t.navProjects, 'folder-git-2'],
      ['reviews', t.navReviews, 'rotate-ccw'],
    ];
    for (const [key, label, ic] of items) {
      const b = bar.createEl('button', { cls: 'devtrail-cc-tab' });
      icon(b.createEl('span', { cls: 'devtrail-cc-tab-icon' }), ic);
      b.createEl('span', { text: label });
      if (this.route === key) {
        b.addClass('is-active');
        b.setAttr('aria-current', 'page');
      }
      b.addEventListener('click', () => { this.route = key; this.render(); });
    }
  }

  /* ── 오늘 ────────────────────────────────────────────────────────────
   * 오늘 개발일지의 체크박스를 보여준다. 고치지는 않는다 — v1 은 읽기 전용이고
   * 편집은 Obsidian 이 이미 잘 한다. */
  async viewToday(body, t, data, devlog) {
    if (!devlog) {
      const e = body.createEl('div', { cls: 'devtrail-cc-empty' });
      e.createEl('p', { text: t.devlogNo });
      this.action(e, t.makeDevlog, templaterCommandId(data.paths, captureFile(CAPTURES[0], data.lang)), t);
      return;
    }
    let tasks = [];
    try {
      const raw = await this.app.vault.read(devlog);
      tasks = raw.split('\n').filter((l) => /^\s*- \[[ xX]\]/.test(l));
    } catch (e) { tasks = []; }

    this.card(body, t.tasks, tasks.length, (list) => {
      if (tasks.length === 0) {
        list.createEl('p', { text: t.noTasks, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const line of tasks.slice(0, 20)) {
        const done = /\[[xX]\]/.test(line);
        const text = line.replace(/^\s*- \[[ xX]\]\s*/, '');
        const row = list.createEl('div', { cls: 'devtrail-cc-row' });
        row.createEl('span', { text: (done ? '☑ ' : '☐ ') + (text || '…') });
      }
    });
    this.card(body, t.devlog, 1, (list) => this.row(list, devlog.basename, devlog, t.openDevlog));
  }

  /* ── 기록 ────────────────────────────────────────────────────────────
   * ⚠️ 노트를 만들지 않는다. 등록된 Templater 명령을 부른다. */
  viewCapture(body, t, data) {
    body.createEl('p', { text: t.captureHelp, cls: 'devtrail-cc-muted' });
    const grid = body.createEl('div', { cls: 'devtrail-cc-grid' });
    const labels = {
      devlog: t.cDevlog, devnote: t.cDevnote, idea: t.cIdea,
      worklog: t.cWorklog, report: t.cReport, project: t.cProject,
    };
    for (const c of CAPTURES) {
      const id = templaterCommandId(data.paths, captureFile(c, data.lang));
      this.action(grid, labels[c.key] || c.key, id, t);
    }
  }

  /* ── 프로젝트 보드 ─────────────────────────────────────────────────
   *
   * 넷으로 나누고, 어디에도 못 넣은 것은 따로 모은다. 빈 컬럼에 0 을
   * 늘어놓지 않는다 — 무엇을 하면 채워지는지 말한다. */
  viewProjects(body, t, model) {
    if (model.projects.length === 0) {
      const e = body.createEl('div', { cls: 'devtrail-cc-empty' });
      e.createEl('p', { text: t.emptyProjects });
      e.createEl('p', { text: t.emptyProjectsHelp, cls: 'devtrail-cc-muted' });
      return;
    }

    // 한 번만 훑어 컬럼별로 나눈다.
    const buckets = { planning: [], active: [], blocked: [], done: [] };
    const unstaged = [];
    for (const p of model.projects) {
      const col = normalizeStage(p.stage);
      if (col) buckets[col].push(p); else unstaged.push(p);
    }

    // ⚠️ 단계 미지정은 다섯 번째 컬럼이 아니다. 상태가 아니라 '빠진 것' 이므로
    //    보드 위에 두어 먼저 눈에 띄게 한다.
    if (unstaged.length > 0) {
      const box = body.createEl('div', { cls: 'devtrail-cc-unstaged' });
      const h = box.createEl('div', { cls: 'devtrail-cc-unstaged-head' });
      icon(h.createEl('span'), 'help-circle');
      h.createEl('strong', { text: `${t.unstaged} ${unstaged.length}` });
      box.createEl('p', { text: t.unstagedHelp, cls: 'devtrail-cc-muted' });
      const list = box.createEl('div', { cls: 'devtrail-cc-unstaged-list' });
      for (const p of unstaged) this.projectCard(list, t, p, null);
    }

    const board = body.createEl('div', { cls: 'devtrail-cc-board' });
    for (const [key, ic] of BOARD_COLUMNS) {
      const items = buckets[key];
      const col = board.createEl('section', { cls: `devtrail-cc-col devtrail-cc-col--${key}` });
      col.setAttr('aria-label', `${t.col[key]} ${items.length}`);
      const head = col.createEl('header', { cls: 'devtrail-cc-col-head' });
      icon(head.createEl('span', { cls: 'devtrail-cc-col-icon' }), ic);
      head.createEl('span', { text: t.col[key], cls: 'devtrail-cc-col-name' });
      head.createEl('span', { text: String(items.length), cls: 'devtrail-cc-col-count' });

      const list = col.createEl('div', { cls: 'devtrail-cc-col-body' });
      if (items.length === 0) {
        list.createEl('p', { text: t.emptyColumn[key], cls: 'devtrail-cc-muted' });
        continue;
      }
      for (const p of items) this.projectCard(list, t, p, key);
    }
  }

  /* 카드 하나. 제목 → 다음 행동 → 보조 메타 순으로 읽히게 둔다.
   *
   * ⚠️ 카드 전체가 눌린다. 링크만 누르게 하면 표적이 너무 작다. */
  projectCard(parent, t, p, colKey) {
    const c = parent.createEl('div', { cls: 'devtrail-cc-pcard' });
    if (colKey) c.addClass(`devtrail-cc-pcard--${colKey}`);
    c.setAttr('role', 'button');
    c.setAttr('tabindex', '0');

    c.createEl('div', { text: p.name, cls: 'devtrail-cc-pcard-title' });

    // next_action 이 카드에서 가장 먼저 눈에 띄어야 한다 — 없으면 없다고 말한다.
    if (p.next) {
      const n = c.createEl('div', { cls: 'devtrail-cc-pcard-next' });
      icon(n.createEl('span'), 'arrow-right');
      n.createEl('span', { text: p.next });
    } else {
      c.createEl('div', { text: t.noNext, cls: 'devtrail-cc-pcard-next is-empty' });
    }

    const meta = c.createEl('div', { cls: 'devtrail-cc-pcard-meta' });
    if (p.stage) this.badge(meta, p.stage, colKey || 'unknown');
    // 실제 파일 메타데이터를 쓴다. '오래됨' 기준을 임의로 만들지 않는다.
    if (p.file && p.file.stat && p.file.stat.mtime) {
      meta.createEl('span', {
        text: new Date(p.file.stat.mtime).toISOString().slice(0, 10),
        cls: 'devtrail-cc-pcard-date',
      });
    }

    c.setAttr('aria-label', `${p.name} — ${p.next || t.noNext}`);
    const open = () => this.app.workspace.getLeaf(false).openFile(p.file);
    c.addEventListener('click', open);
    c.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
    });
  }

  /* ── 리뷰 ────────────────────────────────────────────────────────────
   * ⚠️ 주간리뷰 생성은 CLI 가 한다(devtrail weekly). ISO 주차 계산과 Dataview
   *    쿼리 조립이 거기 있고, 여기서 다시 만들면 두 벌이 된다. */
  viewReviews(body, t, data, model) {
    const dir = data.paths && data.paths.weekly;
    let file = null;
    if (dir) {
      const found = this.app.vault.getMarkdownFiles()
        .filter((f) => f.path.startsWith(dir + '/'))
        .sort((a, b) => b.stat.mtime - a.stat.mtime);
      file = found[0] || null;
    }
    this.card(body, t.weekly, file ? 1 : 0, (list) => {
      if (file) this.row(list, file.basename, file, t.open);
      else {
        list.createEl('p', { text: t.weeklyNo, cls: 'devtrail-cc-muted' });
        list.createEl('p', { text: t.makeWeekly, cls: 'devtrail-cc-muted' });
      }
    });
    this.card(body, t.overdue, model.overdue.length, (list) => {
      if (model.overdue.length === 0) {
        list.createEl('p', { text: t.emptyOverdue, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const o of model.overdue) this.row(list, o.file.basename, o.file, o.at);
    });
  }

  /* 명령 버튼. 명령이 없으면 무엇을 해야 하는지 말한다 —
   * 조용히 다른 노트를 만들지 않는다. */
  action(parent, label, id, t) {
    const b = parent.createEl('button', { text: label, cls: 'devtrail-cc-action' });
    if (commandExists(this.app, id)) {
      b.addEventListener('click', () => this.app.commands.executeCommandById(id));
      return;
    }
    b.addClass('is-disabled');
    b.setAttr('disabled', 'true');
    b.setAttr('title', `${t.notReady} — ${t.notReadyHelp}`);
  }

  /* 카드 하나. 제목 · 개수 · 내용. */
  card(parent, title, count, fill) {
    const box = parent.createEl('section', { cls: 'devtrail-cc-card' });
    const head = box.createEl('div', { cls: 'devtrail-cc-card-head' });
    head.createEl('h3', { text: title });
    head.createEl('span', { text: String(count), cls: 'devtrail-cc-count' });
    fill(box.createEl('div', { cls: 'devtrail-cc-list' }));
  }

  /* 프로젝트 한 줄 — 이름 · stage 배지 · 다음 행동 · 마지막 수정. */
  projectRow(list, t, p) {
    const el = list.createEl('div', { cls: 'devtrail-cc-row devtrail-cc-projectrow' });
    const left = el.createEl('div', { cls: 'devtrail-cc-row-main' });
    const a = left.createEl('a', { text: p.name, cls: 'devtrail-cc-link' });
    a.setAttr('role', 'button');
    a.setAttr('tabindex', '0');
    const open = () => this.app.workspace.getLeaf(false).openFile(p.file);
    a.addEventListener('click', open);
    a.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
    });
    if (p.stage) this.badge(left, p.stage, 'stage');
    if (p.next) el.createEl('div', { text: p.next, cls: 'devtrail-cc-muted' });
    el.createEl('div', {
      text: `${t.lastEdit} ${new Date(p.mtime).toLocaleDateString()}`,
      cls: 'devtrail-cc-muted devtrail-cc-row-meta',
    });
  }

  /* 배지. 상태를 색으로만 말하지 않는다 — 글자를 함께 둔다.
   * 색을 못 보는 사람이 있고, 흑백 인쇄도 있다. */
  badge(parent, text, kind) {
    const b = parent.createEl('span', { text, cls: 'devtrail-cc-badge' });
    if (kind) b.addClass(`is-${kind}`);
    return b;
  }

  /* 노트 한 줄. 클릭하면 연다 — 쓰기는 하지 않는다(v1 은 읽기 전용). */
  row(parent, label, file, meta) {
    const el = parent.createEl('div', { cls: 'devtrail-cc-row' });
    const a = el.createEl('a', { text: label, cls: 'devtrail-cc-link' });
    a.setAttr('role', 'button');
    a.setAttr('tabindex', '0');
    const open = () => this.app.workspace.getLeaf(false).openFile(file);
    a.addEventListener('click', open);
    // 키보드만으로도 열 수 있어야 한다.
    a.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
    });
    if (meta) el.createEl('span', { text: meta, cls: 'devtrail-cc-muted' });
  }
}

module.exports = class DevTrailCommandCenter extends obsidian.Plugin {
  async onload() {
    this.registerView(VIEW_TYPE, (leaf) => new CommandCenterView(leaf));

    this.addRibbonIcon('layout-dashboard', 'DevTrail', () => this.activate());
    this.addCommand({
      id: 'open',
      name: 'Open DevTrail Command Center',
      callback: () => this.activate(),
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
module.exports.__test = { TEXT, isUserNote, normalizeStage, BOARD_COLUMNS, templaterCommandId, captureFile, CAPTURES, isMainLeaf, findCommandByPluginId, SEARCH_PLUGINS };
