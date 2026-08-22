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

    if (meta.status === 'inbox') {
      inbox.push({ file: f, created: meta.created || null, mtime: f.stat.mtime });
    }

    // 다시 볼 때가 된 것. 날짜가 오늘 이전이면 지났다.
    if (meta.review_at && String(meta.review_at).slice(0, 10) <= today) {
      overdue.push({ file: f, at: String(meta.review_at).slice(0, 10) });
    }
  }

  projects.sort((a, b) => b.mtime - a.mtime);
  inbox.sort((a, b) => a.mtime - b.mtime);       // 오래된 것 먼저
  overdue.sort((a, b) => (a.at < b.at ? -1 : 1));

  return { projects, inbox, overdue, total: files.length };
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
    emptyProjects: '등록된 프로젝트가 없습니다',
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
    emptyProjects: 'No projects registered',
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
    head.createEl('h2', { text: t.title });

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
      model.projects.length === 0 &&
      model.inbox.length === 0 &&
      model.overdue.length === 0 &&
      !devlog;
    if (nothing) {
      const e = body.createEl('div', { cls: 'devtrail-cc-empty' });
      e.createEl('p', { text: t.emptyAll });
      e.createEl('p', { text: t.emptyAllHelp, cls: 'devtrail-cc-muted' });
      return;
    }

    this.card(body, t.devlog, devlog ? 1 : 0, (list) => {
      if (devlog) this.row(list, devlog.basename, devlog, t.devlogYes);
      else list.createEl('p', { text: t.devlogNo, cls: 'devtrail-cc-muted' });
    });

    this.card(body, t.projects, model.projects.length, (list) => {
      if (model.projects.length === 0) {
        list.createEl('p', { text: t.emptyProjects, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const p of model.projects.slice(0, 8)) {
        // 있는 것만 보여준다. 없는 필드를 "-" 로 채우면 그것도 지어낸 것이다.
        const bits = [];
        if (p.stage) bits.push(`${t.stage}: ${p.stage}`);
        if (p.next) bits.push(`${t.next}: ${p.next}`);
        this.row(list, p.name, p.file, bits.join(' · '));
      }
    });

    this.card(body, t.inbox, model.inbox.length, (list) => {
      if (model.inbox.length === 0) {
        list.createEl('p', { text: t.emptyInbox, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const i of model.inbox.slice(0, 8)) {
        this.row(list, i.file.basename, i.file, i.created || '');
      }
    });

    this.card(body, t.overdue, model.overdue.length, (list) => {
      if (model.overdue.length === 0) {
        list.createEl('p', { text: t.emptyOverdue, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const o of model.overdue.slice(0, 8)) {
        this.row(list, o.file.basename, o.file, o.at);
      }
    });
  }

  /* ── 네비게이션 ─────────────────────────────────────────────────────── */
  nav(root, t) {
    const bar = root.createEl('nav', { cls: 'devtrail-cc-nav' });
    bar.setAttr('aria-label', t.title);
    const items = [
      ['home', t.navHome], ['today', t.navToday], ['capture', t.navCapture],
      ['projects', t.navProjects], ['reviews', t.navReviews],
    ];
    for (const [key, label] of items) {
      const b = bar.createEl('button', { text: label, cls: 'devtrail-cc-tab' });
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

  /* ── 프로젝트 ─────────────────────────────────────────────────────── */
  viewProjects(body, t, model) {
    this.card(body, t.projects, model.projects.length, (list) => {
      if (model.projects.length === 0) {
        list.createEl('p', { text: t.emptyProjects, cls: 'devtrail-cc-muted' });
        return;
      }
      for (const p of model.projects) {
        const bits = [];
        if (p.stage) bits.push(`${t.stage}: ${p.stage}`);
        if (p.next) bits.push(`${t.next}: ${p.next}`);
        this.row(list, p.name, p.file, bits.join(' · '));
      }
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
  }

  onunload() {
    // ⚠️ 열려 있던 뷰를 정리한다. 남겨두면 플러그인을 끈 뒤에도 빈 탭이 남는다.
    this.app.workspace.detachLeavesOfType(VIEW_TYPE);
  }

  async activate() {
    const { workspace } = this.app;
    const existing = workspace.getLeavesOfType(VIEW_TYPE);
    if (existing.length > 0) {
      workspace.revealLeaf(existing[0]);
      return;
    }
    const leaf = workspace.getRightLeaf(false);
    if (!leaf) return;
    await leaf.setViewState({ type: VIEW_TYPE, active: true });
    workspace.revealLeaf(leaf);
  }
};

/* 테스트가 부르는 순수 함수들.
 *
 * ⚠️ 화면 없이 확인할 수 있는 것은 화면 없이 확인한다. 제외 규칙이 틀리면
 *    카드가 지어낸 데이터를 보고하는데, 그건 눈으로만 보면 놓친다. */
module.exports.__test = { isUserNote, templaterCommandId, captureFile, CAPTURES };
