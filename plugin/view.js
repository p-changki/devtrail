'use strict';

/* DevTrail Command Center — 화면.
 *
 * 값을 DOM 으로 바꾼다. **vault 를 직접 읽지 않고 명령을 직접 찾지도 않는다** —
 * 필요한 것은 전부 인자로 받는다.
 *
 * ⚠️ 모듈끼리 상대 require 하지 않는다 (ADR 0004). 의존성은 main.js 가
 *    절대 경로로 불러 여기에 넘긴다 — 로딩 경로가 한 곳이어야 무엇이
 *    언제 붙는지 알 수 있다.
 *
 * ⚠️ 노트를 쓰지 않는다. 이 화면은 읽기 모델이고, 만드는 일은 등록된
 *    Templater 명령이 한다 (ADR 0002).
 */
const obsidian = require('obsidian');

module.exports = function makeView(deps) {
  const {
    // 읽기 모델
    DAY_MS,
    STALE_DAYS,
    FLOW_WEEKS,
    RECENT_PAGE,
    BOARD_COLUMNS,
    isUserNote,
    localDate,
    openTasks,
    openTasksInVault,
    buildFlow,
    weeklyBars,
    parseDue,
    isStale,
    relativeDays,
    normalizeStage,
    todayDevlog,
    collect,
    // Obsidian 연동
    CAPTURES,
    CORE_SEARCH,
    templaterCommandId,
    captureFile,
    commandExists,
    findSearchCommand,
    searchRunner,
    hotkeyLabel,
    isSubmitKey,
    // 화면 공용
    icon,
    isMainLeaf,
    readPathMap,
    VIEW_TYPE,
    PLUGIN_ID,
    PATH_MAP_FILE,
    textFor,
  } = deps;

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

      // ⚠️ 모듈이 안 붙었으면 여기서 멈춘다. 없는 함수를 부르면 화면이 텅 비고
      //    사용자는 왜인지 모른다.
      const plugin = this.app.plugins && this.app.plugins.plugins
        ? this.app.plugins.plugins[PLUGIN_ID] : null;
      if (!RM) {
        const box = root.createEl('div', { cls: 'devtrail-cc-recovery' });
        box.createEl('p', { text: 'DevTrail 플러그인 파일을 불러오지 못했습니다' });
        if (plugin && plugin.loadError) {
          box.createEl('p', { text: plugin.loadError, cls: 'devtrail-cc-muted' });
        }
        box.createEl('p', {
          text: '터미널에서 devtrail command-center install --apply 를 실행한 뒤 Obsidian 을 다시 여세요.',
          cls: 'devtrail-cc-muted',
        });
        return;
      }

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

      // 상단 바 하나 — 탭 · 날짜 · 만들기 안내.
      //
      // ⚠️ 생성 버튼 6개를 여기 늘어놓지 않는다. 그게 "오늘 뭘 이어서 쓸지" 를
      //    스크롤 아래로 밀어냈다 (디자인 핸드오프 2026-08-22).
      this.nav(root, t);

      this.paths = map.data.paths;
      this.lang = map.data.lang;
      const model = collect(this.app, map.data.paths);
      const devlog = todayDevlog(this.app, map.data);
      const body = root.createEl('div', { cls: 'devtrail-cc-body' });

      // 라우트마다 한 가지 질문에 답한다. 홈은 전체를 훑는다.
      if (this.route === 'today')    return this.viewToday(body, t, map.data, devlog);
      if (this.route === 'recent')   return this.viewRecent(body, t, model);
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

      return this.viewHome(body, t, model, devlog);
    }

    /* ── 홈 ───────────────────────────────────────────────────────────────
     *
     * 디자인 핸드오프(2026-08-22)를 따른다. 화면을 네 덩어리로 줄인다:
     *
     *   1  기록 흐름(12주 히트맵 · 지표 3개 · 요일별 평균) + 오늘
     *   2  프로젝트(단계 분포 + 표, 방치만 색)
     *   3  노트 구성 + 최근 기록
     *
     * ⚠️ 생성 버튼 6개를 위에 늘어놓지 않는다. 그게 "오늘 뭘 이어서 쓸지" 를
     *    스크롤 아래로 밀어냈다. 만들기는 ⌘P 로 간다. */
    async viewHome(body, t, model, devlog) {
      const now = Date.now();
      const files = this.app.vault.getMarkdownFiles()
        .filter((f) => isUserNote(f.path, this.paths))
        .map((f) => ({ ctime: f.stat.ctime }));
      const flow = buildFlow(files, now, FLOW_WEEKS);

      const top = body.createEl('div', { cls: 'devtrail-cc-grid-2' });
      this.panelFlow(top, t, flow);
      await this.panelToday(top, t, devlog);

      this.panelProjects(body, t, model, now);

      const bottom = body.createEl('div', { cls: 'devtrail-cc-grid-3' });
      this.panelComposition(bottom, t, model);
      this.panelRecent(bottom, t, model);
    }

    /* 1a. 기록 흐름 — 무엇을 얼마나 남겼나. */
    panelFlow(parent, t, flow) {
      const card = parent.createEl('section', { cls: 'devtrail-cc-panel' });
      const head = card.createEl('div', { cls: 'devtrail-cc-panel-head' });
      head.createEl('span', { text: `${t.flowTitle} · ${t.lastWeeks(flow.weeks)}`,
                              cls: 'devtrail-cc-eyebrow' });
      const legend = head.createEl('div', { cls: 'devtrail-cc-legend' });
      legend.createEl('span', { text: t.less, cls: 'devtrail-cc-legend-label' });
      for (let l = 0; l <= 4; l++) {
        legend.createEl('span', { cls: `devtrail-cc-swatch devtrail-cc-lv${l}` });
      }
      legend.createEl('span', { text: t.more, cls: 'devtrail-cc-legend-label' });

      // 히트맵 — 7행 × N열. 왼쪽에 월/수/금 라벨.
      const map = card.createEl('div', { cls: 'devtrail-cc-heat' });
      const labels = map.createEl('div', { cls: 'devtrail-cc-heat-days' });
      for (let w = 0; w < 7; w++) {
        labels.createEl('span', { text: (w === 1 || w === 3 || w === 5) ? t.weekdayShort[w] : '' });
      }
      const grid = map.createEl('div', { cls: 'devtrail-cc-heat-grid' });
      grid.style.gridTemplateColumns = `repeat(${flow.weeks}, minmax(0, 1fr))`;
      // 열 = 주, 행 = 요일. 첫 칸의 요일만큼 앞을 비운다.
      const pad = flow.cells.length ? flow.cells[0].weekday : 0;
      for (let i = 0; i < pad; i++) grid.createEl('span', { cls: 'devtrail-cc-cell is-empty' });
      for (const c of flow.cells) {
        const el = grid.createEl('span', { cls: `devtrail-cc-cell devtrail-cc-lv${c.level}` });
        el.setAttr('title', `${localDate(c.day)} · ${c.count}`);
        el.setAttr('aria-label', `${localDate(c.day)} ${c.count}`);
      }

      // 지표 셋.
      const stats = card.createEl('div', { cls: 'devtrail-cc-stats' });
      const items = [
        [String(flow.thisWeek), t.mWeek],
        [`${flow.streak}${t.dayUnit}`, t.streak],
        [flow.weeklyAvg.toFixed(1), t.weeklyAvg],
      ];
      for (const [value, label] of items) {
        const b = stats.createEl('div', { cls: 'devtrail-cc-stat' });
        b.createEl('div', { text: value, cls: 'devtrail-cc-stat-value' });
        b.createEl('div', { text: label, cls: 'devtrail-cc-stat-label' });
      }

      // 요일별 평균.
      const week = card.createEl('div', { cls: 'devtrail-cc-weekdays' });
      week.createEl('div', { text: t.byWeekday, cls: 'devtrail-cc-eyebrow' });
      const max = Math.max(...flow.byWeekday.map((d) => d.avg), 0.0001);
      for (const d of flow.byWeekday) {
        const row = week.createEl('div', { cls: 'devtrail-cc-wd-row' });
        row.createEl('span', { text: t.weekdayShort[d.weekday], cls: 'devtrail-cc-wd-name' });
        const track = row.createEl('span', { cls: 'devtrail-cc-track' });
        const fill = track.createEl('span', { cls: 'devtrail-cc-fill' });
        fill.style.width = `${Math.round((d.avg / max) * 100)}%`;
        if (d.avg === max) fill.addClass('is-peak');
        row.createEl('span', { text: d.avg.toFixed(1), cls: 'devtrail-cc-wd-value' });
      }
    }

    /* 1b. 오늘 — 이어쓸 노트와 남은 작업. */
    async panelToday(parent, t, devlog) {
      const card = parent.createEl('section', { cls: 'devtrail-cc-panel' });
      const head = card.createEl('div', { cls: 'devtrail-cc-panel-head' });
      head.createEl('span', { text: t.colToday, cls: 'devtrail-cc-eyebrow' });
      if (devlog) this.badge(head, t.devlogWritten, 'done');

      if (devlog) {
        const row = card.createEl('div', { cls: 'devtrail-cc-today-note' });
        const a = row.createEl('a', { text: devlog.basename, cls: 'devtrail-cc-link' });
        a.setAttr('role', 'button'); a.setAttr('tabindex', '0');
        const open = () => this.app.workspace.getLeaf(false).openFile(devlog);
        a.addEventListener('click', open);
        a.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });
        row.createEl('span', {
          text: new Date(devlog.stat.mtime).toTimeString().slice(0, 5),
          cls: 'devtrail-cc-mono devtrail-cc-faint',
        });
      } else {
        card.createEl('p', { text: t.devlogNo, cls: 'devtrail-cc-muted' });
        card.createEl('p', { text: t.devlogMake, cls: 'devtrail-cc-muted' });
      }

      const sub = card.createEl('div', { cls: 'devtrail-cc-panel-sub' });
      sub.createEl('span', { text: t.tasks, cls: 'devtrail-cc-eyebrow' });
      const countEl = sub.createEl('span', { text: '…', cls: 'devtrail-cc-mono devtrail-cc-faint' });
      const list = card.createEl('div', { cls: 'devtrail-cc-tasks' });

      // ⚠️ 읽기는 비동기다. 화면을 먼저 그리고 채운다 — 목록을 기다리느라
      //    나머지 패널이 늦게 뜨면 "느린 대시보드" 가 된다.
      const tasks = await openTasksInVault(this.app, this.paths, 5);
      countEl.setText(String(tasks.length));
      if (tasks.length === 0) {
        list.createEl('p', { text: t.noTasks, cls: 'devtrail-cc-muted' });
        return;
      }
      const today = localDate(Date.now());
      for (const task of tasks) {
        const row = list.createEl('div', { cls: 'devtrail-cc-task' });
        row.createEl('span', { cls: 'devtrail-cc-checkbox' });
        const body = row.createEl('div', { cls: 'devtrail-cc-task-body' });
        body.createEl('div', { text: task.text.replace(/\s*(?:📅|\bdue::?)\s*\d{4}-\d{2}-\d{2}\s*\]?/, ''),
                               cls: 'devtrail-cc-task-text' });
        const src = body.createEl('a', { text: task.file.basename, cls: 'devtrail-cc-task-src' });
        src.setAttr('role', 'button'); src.setAttr('tabindex', '0');
        const open = () => this.app.workspace.getLeaf(false).openFile(task.file);
        src.addEventListener('click', open);
        src.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });

        // 기한 — 지났을 때만 색이 붙는다. 없으면 없다고 말한다.
        const due = parseDue(task.text);
        const label = row.createEl('span', { cls: 'devtrail-cc-due devtrail-cc-mono' });
        if (!due) label.setText(t.noDue);
        else if (due < today) { label.setText(t.overdueBy(daysBetween(due, today))); label.addClass('is-over'); }
        else if (due === today) label.setText(t.todayLabel);
        else label.setText(due.slice(5));
      }

      // 하단 — 이어쓰기 · 작업 전체.
      const foot = card.createEl('div', { cls: 'devtrail-cc-panel-foot' });
      const cont = foot.createEl('button', { text: t.continueWrite, cls: 'devtrail-cc-btn' });
      cont.disabled = !devlog;
      if (devlog) {
        cont.addEventListener('click', () => this.app.workspace.getLeaf(false).openFile(devlog));
      }
      const all = foot.createEl('button', { text: t.allTasks, cls: 'devtrail-cc-btn is-ghost' });
      all.addEventListener('click', () => { this.route = 'today'; this.render(); });
    }

    /* 2. 프로젝트 — 단계 분포와 표. 방치만 색이 붙는다. */
    panelProjects(parent, t, model, now) {
      const sec = parent.createEl('section', { cls: 'devtrail-cc-section' });
      const head = sec.createEl('div', { cls: 'devtrail-cc-section-head' });
      head.createEl('h2', { text: t.colProjects });
      const right = head.createEl('div', { cls: 'devtrail-cc-section-meta' });

      const rows = model.projects.map((p) => ({
        p, col: normalizeStage(p.stage), stale: isStale(p.mtime, now, STALE_DAYS),
      }));
      const staleN = rows.filter((r) => r.stale).length;
      if (staleN > 0) {
        right.createEl('span', { text: `● ${t.stale} ${staleN}`, cls: 'devtrail-cc-warn devtrail-cc-mono' });
      }
      right.createEl('span', { text: `${model.projects.length} active`, cls: 'devtrail-cc-mono devtrail-cc-faint' });

      if (model.projects.length === 0) {
        sec.createEl('p', { text: t.emptyProjects, cls: 'devtrail-cc-muted' });
        sec.createEl('p', { text: t.emptyProjectsHelp, cls: 'devtrail-cc-muted' });
        return;
      }

      // 단계 분포 막대 — 계획 중만 색이 붙는다.
      const counts = {};
      for (const [key] of BOARD_COLUMNS) counts[key] = 0;
      let unstaged = 0;
      for (const r of rows) { if (r.col) counts[r.col]++; else unstaged++; }
      const total = model.projects.length;
      const bar = sec.createEl('div', { cls: 'devtrail-cc-dist' });
      for (const [key] of BOARD_COLUMNS) {
        if (counts[key] === 0) continue;
        const seg = bar.createEl('span', { cls: `devtrail-cc-dist-seg devtrail-cc-stage-${key}` });
        seg.style.width = `${(counts[key] / total) * 100}%`;
        seg.setAttr('title', `${t.col[key]} ${counts[key]}`);
      }
      const leg = sec.createEl('div', { cls: 'devtrail-cc-dist-legend' });
      for (const [key] of BOARD_COLUMNS) {
        const item = leg.createEl('span', { cls: 'devtrail-cc-dist-item' });
        item.createEl('span', { cls: `devtrail-cc-dot devtrail-cc-stage-${key}` });
        item.createEl('span', { text: t.col[key] });
        item.createEl('span', { text: String(counts[key]), cls: 'devtrail-cc-mono devtrail-cc-faint' });
      }
      if (unstaged > 0) {
        const item = leg.createEl('span', { cls: 'devtrail-cc-dist-item' });
        item.createEl('span', { cls: 'devtrail-cc-dot devtrail-cc-stage-unstaged' });
        item.createEl('span', { text: t.unstaged });
        item.createEl('span', { text: String(unstaged), cls: 'devtrail-cc-mono devtrail-cc-faint' });
      }

      // 표.
      const table = sec.createEl('div', { cls: 'devtrail-cc-table' });
      const th = table.createEl('div', { cls: 'devtrail-cc-tr devtrail-cc-th' });
      for (const label of [t.thName, t.thStage, t.thSpark, t.thNext, t.thUpdated]) {
        th.createEl('span', { text: label });
      }
      for (const r of rows) {
        const tr = table.createEl('div', { cls: 'devtrail-cc-tr' });
        if (r.stale) tr.addClass('is-stale');
        tr.setAttr('role', 'button'); tr.setAttr('tabindex', '0');
        const name = tr.createEl('span', { cls: 'devtrail-cc-td-name' });
        if (r.stale) name.createEl('span', { cls: 'devtrail-cc-dot devtrail-cc-warn-dot' });
        name.createEl('span', { text: r.p.name });
        tr.createEl('span', { text: r.p.stage || '—', cls: 'devtrail-cc-mono devtrail-cc-faint' });

        // 최근 4주 기록 — 프로젝트 폴더 안 노트를 주별로 센다.
        const spark = tr.createEl('span', { cls: 'devtrail-cc-spark' });
        const bars = weeklyBars(this.projectNoteTimes(r.p), now, 4);
        const peak = Math.max(...bars, 1);
        for (const b of bars) {
          const lvl = b === 0 ? 0 : Math.min(4, 1 + Math.round((b / peak) * 3));
          spark.createEl('span', { cls: `devtrail-cc-spark-bar devtrail-cc-lv${lvl}` })
               .setAttr('title', String(b));
        }
        tr.createEl('span', { text: r.p.next || t.noNext,
                              cls: r.p.next ? '' : 'devtrail-cc-faint' });
        tr.createEl('span', {
          text: relativeDays(r.p.mtime, now, t),
          cls: `devtrail-cc-mono ${r.stale ? 'devtrail-cc-warn' : 'devtrail-cc-faint'}`,
        });
        const open = () => this.app.workspace.getLeaf(false).openFile(r.p.file);
        tr.addEventListener('click', open);
        tr.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });
      }
      sec.createEl('p', { text: t.staleNote(STALE_DAYS), cls: 'devtrail-cc-footnote' });
    }

    /* 3a. 노트 구성 — 최근 30일 무엇을 썼나. */
    panelComposition(parent, t, model) {
      const card = parent.createEl('section', { cls: 'devtrail-cc-panel' });
      card.createEl('div', { text: `${t.composition} · ${t.last30}`, cls: 'devtrail-cc-eyebrow' });

      const cutoff = Date.now() - 30 * DAY_MS;
      const byType = {};
      for (const r of model.recentAll || model.recent) {
        if (r.mtime < cutoff) continue;
        const k = r.type || t.untyped;
        byType[k] = (byType[k] || 0) + 1;
      }
      const entries = Object.keys(byType).map((k) => [k, byType[k]])
        .sort((a, b) => b[1] - a[1]).slice(0, 5);
      const sum = entries.reduce((a, e) => a + e[1], 0);

      if (sum === 0) {
        card.createEl('p', { text: t.emptyComposition, cls: 'devtrail-cc-muted' });
      } else {
        const bar = card.createEl('div', { cls: 'devtrail-cc-stack' });
        entries.forEach(([, n], i) => {
          const seg = bar.createEl('span', { cls: `devtrail-cc-stack-seg devtrail-cc-lv${4 - i}` });
          seg.style.width = `${(n / sum) * 100}%`;
        });
        const leg = card.createEl('div', { cls: 'devtrail-cc-comp-legend' });
        entries.forEach(([k, n], i) => {
          const row = leg.createEl('div', { cls: 'devtrail-cc-comp-row' });
          row.createEl('span', { cls: `devtrail-cc-dot devtrail-cc-lv${4 - i}` });
          row.createEl('span', { text: k });
          row.createEl('span', { text: String(n), cls: 'devtrail-cc-mono devtrail-cc-faint' });
        });
      }

      const sub = card.createEl('div', { cls: 'devtrail-cc-panel-sub' });
      sub.createEl('span', { text: t.pending, cls: 'devtrail-cc-eyebrow' });
      card.createEl('div', {
        text: `inbox ${model.inbox.length} · ${t.mOverdue} ${model.overdue.length} · ${t.mTrouble} ${model.trouble.length}`,
        cls: 'devtrail-cc-mono devtrail-cc-faint',
      });
    }

    /* 3b. 최근 기록 — 2열. */
    panelRecent(parent, t, model) {
      const card = parent.createEl('section', { cls: 'devtrail-cc-panel' });
      card.createEl('div', { text: t.colRecent, cls: 'devtrail-cc-eyebrow' });
      const list = card.createEl('div', { cls: 'devtrail-cc-recent' });
      for (const r of model.recent.slice(0, 10)) {
        const row = list.createEl('div', { cls: 'devtrail-cc-recent-row' });
        const a = row.createEl('a', { text: r.file.basename, cls: 'devtrail-cc-link' });
        a.setAttr('role', 'button'); a.setAttr('tabindex', '0');
        const open = () => this.app.workspace.getLeaf(false).openFile(r.file);
        a.addEventListener('click', open);
        a.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });
        if (r.type) row.createEl('span', { text: r.type, cls: 'devtrail-cc-mono devtrail-cc-faint' });
      }
      // ⚠️ 볼트를 여는 통로다 — 여기서 목록을 더 늘리지 않는다.
      // ⚠️ 노트를 열지 않는다. 목록을 기대하고 누른 사람에게 갑자기 편집기를
      //    띄우면, 무엇이 일어났는지도 되돌아갈 길도 모른다.
      const more = card.createEl('button', { text: t.seeAll, cls: 'devtrail-cc-linkbtn' });
      more.addEventListener('click', () => {
        this.route = 'recent';
        this.recentShown = RECENT_PAGE;
        this.render();
      });
    }

    /* ── 최근 기록 전체 ─────────────────────────────────────────────────
     *
     * ⚠️ 홈의 '최근 기록' 은 10개만 본다. 여기가 '전체' 다 — 10개만 보여주면
     *    이름이 거짓말이 된다. */
    viewRecent(body, t, model) {
      const back = body.createEl('button', { cls: 'devtrail-cc-back', text: t.backHome });
      back.addEventListener('click', () => { this.route = 'home'; this.render(); });

      const rows = model.recentAll || model.recent;
      const shown = Math.min(this.recentShown || RECENT_PAGE, rows.length);

      const head = body.createEl('div', { cls: 'devtrail-cc-section-head' });
      head.createEl('h2', { text: t.colRecent });
      head.createEl('span', { text: `${shown} / ${rows.length}`,
                              cls: 'devtrail-cc-mono devtrail-cc-faint' });

      const table = body.createEl('div', { cls: 'devtrail-cc-table devtrail-cc-recent-table' });
      const th = table.createEl('div', { cls: 'devtrail-cc-tr devtrail-cc-th' });
      for (const label of [t.thName, t.thType, t.thUpdated, t.thPath]) {
        th.createEl('span', { text: label });
      }

      for (const r of rows.slice(0, shown)) {
        const tr = table.createEl('div', { cls: 'devtrail-cc-tr' });
        tr.setAttr('role', 'button'); tr.setAttr('tabindex', '0');
        tr.createEl('span', { text: r.file.basename, cls: 'devtrail-cc-td-name' });
        tr.createEl('span', { text: r.type || '—', cls: 'devtrail-cc-mono devtrail-cc-faint' });
        // ⚠️ 로컬 날짜로 보여준다. toISOString 은 UTC 라 한국에서 전날로 밀린다.
        tr.createEl('span', { text: localDate(r.mtime),
                              cls: 'devtrail-cc-mono devtrail-cc-faint' });
        tr.createEl('span', { text: r.file.path, cls: 'devtrail-cc-td-path devtrail-cc-faint' });
        // 행을 눌렀을 때만 연다.
        const open = () => this.app.workspace.getLeaf(false).openFile(r.file);
        tr.addEventListener('click', open);
        tr.addEventListener('keydown', (ev) => {
          if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); open(); }
        });
      }

      if (shown < rows.length) {
        const loadMore = body.createEl('button', {
          cls: 'devtrail-cc-btn',
          text: `${t.loadMore} (${Math.min(RECENT_PAGE, rows.length - shown)})`,
        });
        // ⚠️ 볼트를 다시 훑지 않는다. 이미 모은 목록에서 더 꺼낼 뿐이다.
        loadMore.addEventListener('click', () => {
          this.recentShown = shown + RECENT_PAGE;
          this.render();
        });
      }
    }

    /* 프로젝트 폴더 안 노트들의 수정 시각.
     *
     * ⚠️ 태그가 아니라 폴더로 본다 — 이 볼트는 프로젝트를 폴더로 나눈다. */
    projectNoteTimes(p) {
      const dir = p.file.path.slice(0, p.file.path.lastIndexOf('/'));
      return this.app.vault.getMarkdownFiles()
        .filter((f) => f.path.startsWith(dir + '/'))
        .map((f) => f.stat.mtime);
    }

    /* ── 지표 ─────────────────────────────────────────────────────────────
     * ⚠️ DevTrail 개념만 센다. Meetings·Events·Focus 같은 것을 넣으면 볼트에
     *    그 개념이 없어 전부 0 이 뜬다(실측: meeting 0 · event 0 · task 0).
     *    0 만 늘어놓는 화면은 지어낸 화면이다. */

    /* 지표에서 라우트로. 숫자를 보고 바로 갈 수 있어야 한다. */

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

    /* 자주 쓰는 기록으로 가는 아이콘 바. 검색 바로 아래 — 찾기 다음은 남기기다.
     *
     * ⚠️ 노트를 직접 만들지 않는다. 등록된 Templater 명령만 부른다. */

    /* ── 네비게이션 ─────────────────────────────────────────────────────── */
    nav(root, t) {
      const bar = root.createEl('div', { cls: 'devtrail-cc-nav' });
      bar.setAttr('aria-label', t.title);

      const tabs = bar.createEl('nav', { cls: 'devtrail-cc-tabs' });
      const items = [
        ['home', t.navHome, 'layout-dashboard'],
        ['today', t.navToday, 'sun'],
        ['projects', t.navProjects, 'folder-git-2'],
        ['reviews', t.navReviews, 'history'],
      ];
      for (const [key, label] of items) {
        const b = tabs.createEl('button', { cls: 'devtrail-cc-tab', text: label });
        if (this.route === key) {
          b.addClass('is-active');
          b.setAttr('aria-current', 'page');
        }
        b.addEventListener('click', () => { this.route = key; this.render(); });
      }

      const right = bar.createEl('div', { cls: 'devtrail-cc-nav-right' });

      // 전체 검색 — 볼트를 찾는다.
      //
      // ⚠️ 화면을 거르는 필터가 아니다. 사용자는 이 자리에서 볼트 전체를 찾을
      //    거라 기대하고, 기대와 동작이 어긋나면 그 자리는 없느니만 못하다.
      // ⚠️ 검색기를 새로 만들지 않는다. Omnisearch 가 있으면 그것을, 없으면
      //    Obsidian 기본 검색을 부른다. 명령 id 는 짐작하지 않는다.
      const box = right.createEl('div', { cls: 'devtrail-cc-searchbox' });
      icon(box.createEl('span', { cls: 'devtrail-cc-searchbox-icon' }), 'search');
      const input = box.createEl('input', { cls: 'devtrail-cc-searchinput' });
      input.setAttr('type', 'text');
      input.setAttr('placeholder', t.searchPlaceholder);
      input.setAttr('aria-label', t.searchPlaceholder);

      // 검색 단축키를 입력창 안에 보여준다 — 여기서도 배정된 것을 읽는다.
      //
      // ⚠️ ⌘⇧F 를 박지 않는다. 사용자가 바꿨을 수 있고, 그러면 화면이 또
      //    거짓을 말한다. 배정이 없으면 아무것도 보여주지 않는다.
      const skey = hotkeyLabel(this.app, CORE_SEARCH);
      if (skey) box.createEl('span', { text: skey, cls: 'devtrail-cc-searchkbd devtrail-cc-mono' });

      const run = searchRunner(this.app);
      const help = right.createEl('span', { cls: 'devtrail-cc-searchhelp' });
      if (run) {
        const go = () => run(input.value.trim());
        input.addEventListener('keydown', (ev) => {
          if (!isSubmitKey(ev)) return;
          ev.preventDefault();
          go();
        });
        box.addEventListener('click', () => input.focus());
        box.querySelector('.devtrail-cc-searchbox-icon')
           .addEventListener('click', (ev) => { ev.stopPropagation(); go(); });
      } else {
        // ⚠️ 끄지 않는다. 왜 안 되는지, 무엇을 하면 되는지 말한다.
        help.setText(t.searchMissingHelp);
        input.setAttr('title', t.searchMissingHelp);
      }

      // 날짜 — 2026-08-22 SAT
      const now = new Date();
      right.createEl('span', {
        text: `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')} ${t.weekdayUpper[now.getDay()]}`,
        cls: 'devtrail-cc-date devtrail-cc-mono',
      });

      // 만들기는 명령 팔레트로 간다 — 생성 버튼을 화면 위에 늘어놓지 않는다.
      // ⚠️ 전체 명령 팔레트가 아니라 DevTrail 전용 선택창을 연다.
      const make = right.createEl('button', { cls: 'devtrail-cc-make' });
      make.createEl('span', { text: t.makeNote });
      const key = hotkeyLabel(this.app, `${PLUGIN_ID}:quick-capture`);
      if (key) make.createEl('span', { text: key, cls: 'devtrail-cc-kbd devtrail-cc-mono' });
      make.setAttr('aria-label', t.makeNote);
      make.addEventListener('click', () => this.openQuickCapture(t));
    }

    openQuickCapture(t) {
      if (!this.paths) return;
      new QuickCaptureModal(this.app, t, { paths: this.paths, lang: this.lang || 'ko' }).open();
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

    /* ⚠️ '기록' 탭을 없앴다. 화면 위 빠른 실행 바가 같은 Templater 명령 6개를
     *    **항상** 보여준다 — 같은 일을 두 곳에서 하면 한쪽만 고쳐지고, 사용자는
     *    어느 쪽이 진짜인지 모른다. */

    /* ── 프로젝트 보드 ─────────────────────────────────────────────────
     *
     * 넷으로 나누고, 어디에도 못 넣은 것은 따로 모은다. 빈 컬럼에 0 을
     * 늘어놓지 않는다 — 무엇을 하면 채워지는지 말한다. */
    viewProjects(body, t, model) {
      this.board(body, t, model);
    }

    /* ── 프로젝트 보드 ─────────────────────────────────────────────────
     *
     * 홈의 중앙과 프로젝트 탭이 **같은 함수**를 쓴다. 두 벌로 나뉘면 한쪽만
     * 고쳐지고, 그 순간 두 화면이 서로 다른 말을 한다. */
    board(parent, t, model) {
      if (model.projects.length === 0) {
        const e = parent.createEl('div', { cls: 'devtrail-cc-empty' });
        e.createEl('p', { text: t.emptyProjects });
        e.createEl('p', { text: t.emptyProjectsHelp, cls: 'devtrail-cc-muted' });
        return;
      }

      const buckets = { planning: [], active: [], blocked: [], done: [] };
      const unstaged = [];
      for (const p of model.projects) {
        const col = normalizeStage(p.stage);
        if (col) buckets[col].push(p); else unstaged.push(p);
      }

      // ⚠️ 단계 미지정은 다섯 번째 컬럼이 아니다. 상태가 아니라 '빠진 것' 이므로
      //    보드 위에 두어 먼저 눈에 띄게 한다.
      if (unstaged.length > 0) {
        const box = parent.createEl('div', { cls: 'devtrail-cc-unstaged' });
        const h = box.createEl('div', { cls: 'devtrail-cc-unstaged-head' });
        icon(h.createEl('span'), 'help-circle');
        h.createEl('strong', { text: `${t.unstaged} ${unstaged.length}` });
        box.createEl('p', { text: t.unstagedHelp, cls: 'devtrail-cc-muted' });
        const list = box.createEl('div', { cls: 'devtrail-cc-unstaged-list' });
        for (const p of unstaged) this.projectCard(list, t, p, null);
      }

      const board = parent.createEl('div', { cls: 'devtrail-cc-board' });
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
          text: localDate(p.file.stat.mtime),
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

  /* ── 빠른 기록 ────────────────────────────────────────────────────────────────
   *
   * ⚠️ Obsidian 전체 명령 팔레트를 열지 않는다. 빠른 기록을 하려는 사람에게
   *    수백 개 명령을 보여주는 것은 도움이 아니다.
   *
   * ⚠️ 노트를 여기서 만들지 않는다. 등록된 Templater 명령을 부를 뿐이다 —
   *    형식이 두 곳에서 만들어지면 반드시 어긋난다 (ADR 0002).
   *
   * ⚠️ 명령 id 를 짐작하지 않는다. 레지스트리에 있는 것만 보여주고, 없는 것은
   *    왜 없는지 말한다.
   */
  class QuickCaptureModal extends obsidian.Modal {
    constructor(app, t, data) {
      super(app);
      this.t = t;
      this.data = data;
      this.index = 0;
    }

    onOpen() {
      const t = this.t;
      const { contentEl } = this;
      contentEl.addClass('devtrail-qc');
      contentEl.createEl('div', { text: t.quickCapture, cls: 'devtrail-qc-title' });

      const icons = {
        devlog: 'calendar-days', devnote: 'pencil', idea: 'lightbulb',
        worklog: 'clock', report: 'rotate-ccw', project: 'folder-plus',
      };
      const labels = {
        devlog: t.cDevlog, devnote: t.cDevnote, idea: t.cIdea,
        worklog: t.cWorklog, report: t.cReport, project: t.cProject,
      };

      this.rows = [];
      const list = contentEl.createEl('div', { cls: 'devtrail-qc-list' });
      for (const c of CAPTURES) {
        const id = templaterCommandId(this.data.paths, captureFile(c, this.data.lang));
        const ok = commandExists(this.app, id);
        const row = list.createEl('div', { cls: 'devtrail-qc-row' });
        if (!ok) row.addClass('is-off');
        row.setAttr('role', 'button');
        row.setAttr('tabindex', ok ? '0' : '-1');
        icon(row.createEl('span', { cls: 'devtrail-qc-icon' }), icons[c.key] || 'file-plus');
        const body = row.createEl('div', { cls: 'devtrail-qc-body' });
        body.createEl('div', { text: labels[c.key] || c.key, cls: 'devtrail-qc-name' });
        body.createEl('div', {
          text: ok ? (t.captureHint[c.key] || '') : t.actionMissing,
          cls: 'devtrail-qc-hint',
        });
        if (ok) {
          this.rows.push({ el: row, id });
          row.addEventListener('click', () => this.run(id));
        }
      }

      if (this.rows.length === 0) {
        // ⚠️ 일반 팔레트로 빠지지 않는다. 무엇을 하면 되는지 말한다.
        contentEl.createEl('p', { text: t.templaterMissing, cls: 'devtrail-qc-empty' });
        return;
      }

      this.highlight();
      // ⚠️ 키보드만으로도 쓸 수 있어야 한다.
      this.scope.register([], 'ArrowDown', (ev) => {
        ev.preventDefault();
        this.index = (this.index + 1) % this.rows.length;
        this.highlight();
      });
      this.scope.register([], 'ArrowUp', (ev) => {
        ev.preventDefault();
        this.index = (this.index - 1 + this.rows.length) % this.rows.length;
        this.highlight();
      });
      this.scope.register([], 'Enter', (ev) => {
        ev.preventDefault();
        this.run(this.rows[this.index].id);
      });
      // Esc 는 Obsidian 의 Modal 이 이미 닫는다.
    }

    highlight() {
      this.rows.forEach((r, i) => {
        if (i === this.index) r.el.addClass('is-on'); else r.el.removeClass('is-on');
      });
    }

    /* 사용자가 골랐을 때만 실행한다. */
    run(id) {
      this.close();
      this.app.commands.executeCommandById(id);
    }

    onClose() { this.contentEl.empty(); }
  }

  return { CommandCenterView, QuickCaptureModal };
};
