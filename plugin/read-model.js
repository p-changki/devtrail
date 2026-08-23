'use strict';

/* DevTrail Command Center — 읽기 모델.
 *
 * vault 를 읽어 값으로 바꾼다. **DOM 도 명령 레지스트리도 여기 없다** —
 * 그래서 화면 없이 테스트할 수 있고, 실제로 테스트가 이 파일을 직접 부른다.
 *
 * ⚠️ Obsidian 은 형제 파일을 상대 경로로 읽지 못한다. main.js 가
 *    adapter.getBasePath() 로 절대 경로를 만들어 부른다 (ADR 0004).
 *
 * ⚠️ 경로는 _devtrail-paths.md 하나에서만 온다. 여기서 기본값을 갖지 않는다 —
 *    이 저장소는 dirs.devlog 의 기본값을 네 곳이 각자 가져 같은 결함을
 *    네 번 고쳤다.
 */

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

/* ⚠️ files 를 넘기면 볼트를 다시 훑지 않는다. 한 번의 렌더가 같은 목록을
 *    세 번 만들던 것을 한 번으로 줄이기 위한 통로다 — 넘기지 않으면
 *    예전처럼 스스로 훑으므로 이 함수만 따로 부르는 곳은 그대로 산다. */
/* 볼트에서 사용자 노트만. 한 곳에서만 훑는다. */
function userNotes(app, paths) {
  return app.vault.getMarkdownFiles().filter((f) => isUserNote(f.path, paths));
}

/* 폴더별 노트 수정 시각.
 *
 * ⚠️ 프로젝트 행마다 볼트를 훑던 자리를 대신한다. 예전에는 행 N개에
 *    전체 스캔 N번이었다(2026-08-23 측정: 프로젝트 200개 → 스캔 203회).
 *    여기서는 한 번 훑으며 각 파일을 자기 **상위 폴더 전부**에 넣는다 —
 *    startsWith(dir + '/') 와 정확히 같은 집합이고, 경로 깊이만큼만 든다. */
function noteTimesByDir(files) {
  const out = new Map();
  for (const f of files) {
    const parts = f.path.split('/');
    for (let i = 1; i < parts.length; i++) {
      const dir = parts.slice(0, i).join('/');
      const at = out.get(dir);
      if (at) at.push(f.stat.mtime);
      else out.set(dir, [f.stat.mtime]);
    }
  }
  return out;
}

function collect(app, paths, files) {
  files = files || userNotes(app, paths);

  const projects = [];
  const inbox = [];
  const overdue = [];
  const trouble = [];
  const today = localDate(Date.now());

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

  // ⚠️ 전체 목록을 따로 훑지 않는다. 이미 정렬한 것을 그대로 넘긴다 —
  //    '더 보기' 를 누를 때마다 볼트를 다시 읽으면 큰 볼트에서 멈춘다.
  const recentAll = files
    .slice()
    .sort((a, b) => b.stat.mtime - a.stat.mtime)
    .map((f) => ({ file: f, type: fm(app, f).type || null, mtime: f.stat.mtime }));

  return { projects, inbox, overdue, trouble, recent, recentAll,
           thisWeek, total: files.length };
}

/* YYYY-MM-DD, 로컬 기준.
 *
 * ⚠️ toISOString() 은 UTC 다. 한국(UTC+9)에서 오전 9시 이전에 만든 노트가
 *    전날 날짜로 보인다 — 사용자가 "어제 쓴 게 아닌데" 하고 의심하게 된다. */
function localDate(ms) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/* 오늘 개발일지. 경로는 맵에서만 온다 — 파일명 규칙도 맵이 갖고 있다. */
function todayDevlog(app, data) {
  const dir = data.paths && data.paths.devlog;
  if (!dir) return null;
  const pat = (data.naming && data.naming.devlog_file) || '{{DATE}} devlog.md';
  const name = pat.replace('{{DATE}}', localDate(Date.now()));
  const path = `${dir}/${name}`;
  return app.vault.getAbstractFileByPath(path) || null;
}

/* 이 노트의 체크박스를 '할 일' 로 볼 것인가.
 *
 * ⚠️ 사양의 `TASK WHERE !completed` 는 DevTrail 노트만 있는 볼트를 가정했다.
 *    실제 볼트에는 가져온 레포 문서가 섞여 있고, 그 안의 체크박스는 설계안·
 *    체크리스트의 항목이지 사용자의 할 일이 아니다.
 *
 *    2026-08-22 실측: 열린 체크박스가 있는 노트 107개 중 **DevTrail 노트는
 *    0개**였다. 106개는 type 이 없는 레포 문서, 1개는 사용법 안내였다.
 *    화면의 "미완료 작업" 다섯 줄이 전부 잡음이었다.
 *
 * ⚠️ 그래서 두 가지를 요구한다:
 *    1. type 이 있어야 한다 — 없으면 DevTrail 이 만든 노트가 아니다
 *    2. 문서를 설명하는 타입은 뺀다 — 안내문의 "해봤다" 목록은 할 일이 아니다
 */
const DOC_TYPES = ['guide', 'moc', 'doc', 'library-note', 'book-note', 'asset-card'];

function bearsTasks(meta) {
  const type = meta && meta.type;
  if (typeof type !== 'string' || !type) return false;
  return DOC_TYPES.indexOf(type) < 0;
}

/* 볼트 전체의 열린 체크박스.
 *
 * ⚠️ 모든 파일을 읽지 않는다. metadataCache 의 listItems 가 이미 어느 파일에
 *    열린 작업이 있는지 안다 — 그 파일만 읽는다. 볼트가 커져도 읽는 양이
 *    작업 수에 비례한다.
 * ⚠️ 빈 자리표시('- [ ]' 뒤에 아무것도 없는 것)는 작업이 아니다. */
async function openTasksInVault(app, paths, limit, files) {
  const out = [];
  // ⚠️ 넘겨받은 목록을 제자리에서 정렬하지 않는다. 부르는 쪽이 같은 배열을
  //    다른 용도로도 쓰고 있고, 여기서 순서를 바꾸면 그쪽이 조용히 달라진다.
  const list = (files || userNotes(app, paths)).slice();
  // 최근에 손댄 것부터 — 지금 하려는 일이 거기 있다.
  list.sort((a, b) => b.stat.mtime - a.stat.mtime);
  for (const f of list) {
    if (out.length >= limit) break;
    const cache = app.metadataCache.getFileCache(f);
    // ⚠️ 먼저 '이 노트가 할 일을 담는 곳인가' 를 본다. 파일을 읽기 전에
    //    거르면 볼트가 커져도 읽는 양이 늘지 않는다.
    if (!bearsTasks((cache && cache.frontmatter) || {})) continue;
    const items = (cache && cache.listItems) || [];
    if (!items.some((i) => i.task === ' ')) continue;
    let raw = '';
    try { raw = await app.vault.cachedRead(f); } catch (e) { continue; }
    for (const line of openTasks(raw)) {
      if (out.length >= limit) break;
      out.push({ text: line, file: f });
    }
  }
  return out;
}

/* ── 재설계 데이터 (디자인 핸드오프 2026-08-22) ──────────────────────────────
 *
 * 전부 기존 노트에서 계산한다 — 새 스키마도 마이그레이션도 없다.
 *
 * ⚠️ 사양이 노출하라고 한 설정은 둘뿐이다. 더 늘리면 화면이 아니라 설정을
 *    관리하게 된다. */
const STALE_DAYS = 14;

const FLOW_WEEKS = 12;

/* 전체 목록 한 번에 그리는 개수.
 *
 * ⚠️ 500개를 한 번에 그리면 화면이 멈춘다. 50개씩 늘린다. */
const RECENT_PAGE = 50;

const DAY_MS = 86400000;

/* 로컬 기준 그 날의 0시. 히트맵 칸은 '날' 이 단위다.
 *
 * ⚠️ UTC 로 자르면 한국에서 오전 9시 이전에 만든 노트가 전날 칸에 들어간다. */
function dayStart(ms) {
  const d = new Date(ms);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/* 히트맵·연속 기록·요일별 평균을 한 번에 만든다.
 *
 * files: [{ ctime }] — 생성 시각만 있으면 된다.
 *
 * ⚠️ 강도는 개수 그대로가 아니라 5단계다. 하루 30건 쓴 날 하나가 나머지를
 *    전부 0단계로 만들면 격자가 아무것도 말하지 않는다. */
function buildFlow(files, nowMs, weeks) {
  const days = (weeks || FLOW_WEEKS) * 7;
  const today = dayStart(nowMs);
  const start = today - (days - 1) * DAY_MS;

  const counts = {};
  for (const f of files) {
    if (typeof f.ctime !== 'number') continue;
    const d = dayStart(f.ctime);
    if (d < start || d > today) continue;
    counts[d] = (counts[d] || 0) + 1;
  }

  const cells = [];
  let total = 0;
  for (let i = 0; i < days; i++) {
    const d = start + i * DAY_MS;
    const n = counts[d] || 0;
    total += n;
    cells.push({ day: d, count: n, level: 0, weekday: new Date(d).getDay() });
  }

  // 5단계. 0 은 언제나 0단계 — 쓴 날과 안 쓴 날은 눈으로 갈려야 한다.
  const nonZero = cells.filter((c) => c.count > 0).map((c) => c.count).sort((a, b) => a - b);
  if (nonZero.length > 0) {
    const q = (p) => nonZero[Math.min(nonZero.length - 1, Math.floor(nonZero.length * p))];
    const t1 = q(0.25), t2 = q(0.5), t3 = q(0.75);
    for (const c of cells) {
      if (c.count === 0) c.level = 0;
      else if (c.count <= t1) c.level = 1;
      else if (c.count <= t2) c.level = 2;
      else if (c.count <= t3) c.level = 3;
      else c.level = 4;
    }
  }

  // 연속 기록 — 오늘부터 거꾸로. 오늘 아직 안 썼으면 어제부터 센다.
  let streak = 0;
  for (let d = today; d >= start; d -= DAY_MS) {
    if ((counts[d] || 0) > 0) streak++;
    else if (d !== today) break;
    else if (streak === 0 && d === today) continue;
  }

  // 요일별 평균 — 12주치를 요일로 모은다.
  const byWeekday = [];
  for (let w = 0; w < 7; w++) {
    const of = cells.filter((c) => c.weekday === w);
    const sum = of.reduce((a, c) => a + c.count, 0);
    byWeekday.push({ weekday: w, avg: of.length ? sum / of.length : 0 });
  }

  const weekAgo = today - 6 * DAY_MS;
  const thisWeek = cells.filter((c) => c.day >= weekAgo).reduce((a, c) => a + c.count, 0);

  return { cells, total, streak, byWeekday, thisWeek, weeks: weeks || FLOW_WEEKS,
           weeklyAvg: total / (weeks || FLOW_WEEKS) };
}

/* 최근 N주, 주별 개수. 마지막 칸이 이번 주다.
 *
 * ⚠️ 주는 '오늘로부터 7일씩' 이다. 달력의 주(월~일)가 아니다 — 표에서 묻는
 *    것은 "최근에 얼마나 손댔나" 이지 "몇 주차였나" 가 아니다. */
function weeklyBars(times, nowMs, weeks) {
  const n = weeks || 4;
  const bars = new Array(n).fill(0);
  const today = dayStart(nowMs);
  for (const ms of times) {
    if (typeof ms !== 'number') continue;
    const days = Math.floor((today - dayStart(ms)) / DAY_MS);
    if (days < 0 || days >= n * 7) continue;
    bars[n - 1 - Math.floor(days / 7)]++;
  }
  return bars;
}

/* 할 일 줄에서 기한을 읽는다. 흔히 쓰는 세 표기만 본다.
 *
 * ⚠️ 없으면 null 이다. 오늘 날짜나 아무 날짜를 채워 넣지 않는다 — 지어낸
 *    기한은 사람을 잘못된 급함으로 몰아붙인다. */
function parseDue(text) {
  if (typeof text !== 'string') return null;
  const m = text.match(/(?:📅|\bdue::?\s*)\s*(\d{4})-(\d{2})-(\d{2})/);
  if (!m) return null;
  const [, y, mo, d] = m;
  const mi = Number(mo), di = Number(d);
  if (mi < 1 || mi > 12 || di < 1 || di > 31) return null;
  return `${y}-${mo}-${d}`;
}

function relativeDays(mtime, nowMs, t) {
  if (typeof mtime !== 'number') return '—';
  const d = Math.floor((dayStart(nowMs) - dayStart(mtime)) / DAY_MS);
  if (d <= 0) return t.todayLabel;
  return t.daysAgo(d);
}

function daysBetween(a, b) {
  return Math.round((Date.parse(b) - Date.parse(a)) / DAY_MS);
}

function isStale(mtime, nowMs, days) {
  if (typeof mtime !== 'number') return false;
  return (nowMs - mtime) > (days || STALE_DAYS) * DAY_MS;
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

/* 개발일지에서 **미완료이고 내용이 있는** 할 일만 고른다.
 *
 * ⚠️ 템플릿은 빈 체크박스 '- [ ]' 를 자리표시로 넣는다. 그것까지 그리면 글자
 *    없는 빈 줄이 쌓인다 — 빈 자리표시는 할 일이 아니다. 2026-08-22 QA
 *    화면에서 빈 상자 3개로 실제로 드러났다.
 *
 * ⚠️ 읽기만 한다. 체크박스를 고치는 것은 Obsidian 이 이미 잘 한다. */
function openTasks(raw) {
  if (typeof raw !== 'string') return [];
  const out = [];
  for (const line of raw.split('\n')) {
    const m = line.match(/^\s*- \[ \]\s*(.*)$/);
    if (!m) continue;
    const text = m[1].trim();
    if (text) out.push(text);
  }
  return out;
}

function normalizeStage(raw) {
  if (typeof raw !== 'string') return null;
  const key = raw.trim().toLowerCase();
  if (!key) return null;
  return STAGE_ALIASES[key] || null;
}

module.exports = {
  DAY_MS, STALE_DAYS, FLOW_WEEKS, RECENT_PAGE, DOC_TYPES,
  BOARD_COLUMNS, STAGE_ALIASES,
  isUserNote, fm, localDate, dayStart,
  bearsTasks, openTasks, openTasksInVault,
  buildFlow, weeklyBars, parseDue, daysBetween, isStale,
  relativeDays, normalizeStage, todayDevlog, collect,
  userNotes, noteTimesByDir,
};

// 이 파일은 전부 순수하다 — 테스트가 통째로 부른다.
module.exports.__test = module.exports;
