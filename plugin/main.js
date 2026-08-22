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
async function openTasksInVault(app, paths, limit) {
  const out = [];
  const files = app.vault.getMarkdownFiles().filter((f) => isUserNote(f.path, paths));
  // 최근에 손댄 것부터 — 지금 하려는 일이 거기 있다.
  files.sort((a, b) => b.stat.mtime - a.stat.mtime);
  for (const f of files) {
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

/* 손을 놓은 지 오래됐는가.
 *
 * ⚠️ 모르면 방치라고 하지 않는다. 수정 시각을 못 읽은 것과 오래 안 건드린
 *    것은 다른 사실이다 — 지어낸 경고는 사람을 무디게 만든다.
 * ⚠️ 경계는 '넘었을 때' 다. 딱 14일은 아직 아니다. */
/* "1일 전" · "31일 전". 오늘은 "오늘".
 *
 * ⚠️ 절대 날짜를 쓰지 않는다 — 표에서 중요한 건 '얼마나 손을 놨나' 이지
 *    '언제였나' 가 아니다. */

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
    navHome: '홈', navToday: '오늘',
    navProjects: '프로젝트', navReviews: '리뷰',
    tasks: '오늘 할 일',
    noTasks: '체크박스가 없습니다',
    openDevlog: '개발일지 열기',
    makeDevlog: '개발일지 만들기',
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
    colToday: '오늘 현황', devlogMake: '기록 탭의 [개발일지] 로 만드세요.', lastEdit: '마지막 수정', colProjects: '활성 프로젝트', colRecent: '최근 기록',
    templaterMissing: 'Templater 명령이 없습니다. 터미널에서 devtrail obsidian 을 실행하고 Obsidian 을 다시 여세요.',
    captureHint: {
      devlog: '오늘 무엇을 했는지', devnote: '지금 판단한 것',
      idea: '떠오른 것 — 정리는 나중에', worklog: '한 일과 걸린 시간',
      report: '한 주를 돌아보며', project: '새 프로젝트 폴더와 허브',
    },
    backHome: '← 홈', thType: '종류', thPath: '경로', loadMore: '더 보기',
    searchPlaceholder: '전체 검색…', makeNote: '노트 만들기',
    weekdayUpper: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'],
    noDue: '기한 없음', overdueBy: (n) => `${n}일 지남`,
    continueWrite: '이어쓰기', allTasks: '작업 전체', seeAll: '전체 보기',
    thSpark: '최근 4주 기록',
    flowTitle: '기록 흐름', lastWeeks: (n) => `최근 ${n}주`,
    less: '적음', more: '많음',
    streak: '연속 기록', weeklyAvg: '주간 평균', dayUnit: '일',
    byWeekday: '요일별 평균',
    weekdayShort: ['일', '월', '화', '수', '목', '금', '토'],
    devlogWritten: '일지 작성됨', tasks: '미완료 작업',
    todayLabel: '오늘', daysAgo: (n) => `${n}일 전`,
    stale: '방치', staleNote: (n) => `${n}일 넘게 업데이트가 없으면 방치로 표시합니다.`,
    thName: '이름', thStage: '단계', thNext: '다음 행동', thUpdated: '업데이트',
    composition: '노트 구성', last30: '최근 30일', untyped: '분류 없음',
    emptyComposition: '최근 30일에 만든 노트가 없습니다',
    pending: '처리 대기',
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
    navHome: 'Home', navToday: 'Today',
    navProjects: 'Projects', navReviews: 'Reviews',
    tasks: "Today's tasks",
    noTasks: 'No checkboxes',
    openDevlog: "Open today's devlog",
    makeDevlog: "Create today's devlog",
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
    colToday: 'Today', devlogMake: 'Create one from [Devlog] on the Capture tab.', lastEdit: 'Last edit', colProjects: 'Active projects', colRecent: 'Recent',
    templaterMissing: 'No Templater commands found. Run devtrail obsidian, then reopen Obsidian.',
    captureHint: {
      devlog: 'What you did today', devnote: 'A decision you just made',
      idea: 'Something that came up — sort it later', worklog: 'What you did and how long it took',
      report: 'Looking back on the week', project: 'A new project folder and hub',
    },
    backHome: '← Home', thType: 'Type', thPath: 'Path', loadMore: 'Load more',
    searchPlaceholder: 'Search your vault…', makeNote: 'New note',
    weekdayUpper: ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'],
    noDue: 'no due date', overdueBy: (n) => `${n}d overdue`,
    continueWrite: 'Continue', allTasks: 'All tasks', seeAll: 'See all',
    thSpark: 'Last 4 weeks',
    flowTitle: 'Writing flow', lastWeeks: (n) => `last ${n} weeks`,
    less: 'less', more: 'more',
    streak: 'Streak', weeklyAvg: 'Weekly average', dayUnit: 'd',
    byWeekday: 'By weekday',
    weekdayShort: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
    devlogWritten: 'Written', tasks: 'Open tasks',
    todayLabel: 'today', daysAgo: (n) => `${n}d ago`,
    stale: 'stale', staleNote: (n) => `Projects untouched for more than ${n} days are marked stale.`,
    thName: 'Name', thStage: 'Stage', thNext: 'Next action', thUpdated: 'Updated',
    composition: 'Note mix', last30: 'last 30 days', untyped: 'untyped',
    emptyComposition: 'No notes created in the last 30 days',
    pending: 'Pending',
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

    const found = this.resolveSearch(t);
    const help = right.createEl('span', { cls: 'devtrail-cc-searchhelp' });
    if (found) {
      input.setAttr('title', found.name);
      const go = () => this.app.commands.executeCommandById(found.id);
      input.addEventListener('keydown', (ev) => {
        if (ev.key === 'Enter') { ev.preventDefault(); go(); }
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
    make.createEl('span', { text: '⌘P', cls: 'devtrail-cc-kbd devtrail-cc-mono' });
    make.setAttr('aria-label', t.makeNote);
    make.addEventListener('click', () => this.openQuickCapture(t));
  }

  openQuickCapture(t) {
    if (!this.paths) return;
    new QuickCaptureModal(this.app, t, { paths: this.paths, lang: this.lang || 'ko' }).open();
  }

  /* 어떤 검색 명령을 부를 것인가.
   *
   * ⚠️ 확신할 수 있는 것만 고른다. 없으면 null 이고, 화면은 안내로 떨어진다 —
   *    'index' 나 'settings' 를 검색이라고 부르느니 안 부르는 게 낫다. */
  resolveSearch(t) {
    const all = (this.app.commands && this.app.commands.commands) || {};
    const pick = findSearchCommand(this.app);
    if (pick) return { id: pick, name: (all[pick] && all[pick].name) || pick };
    if (commandExists(this.app, CORE_SEARCH)) return { id: CORE_SEARCH, name: t.searchCore };
    return null;
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
module.exports.__test = { TEXT, localDate, bearsTasks, weeklyBars, parseDue, buildFlow, isStale, STALE_DAYS, FLOW_WEEKS, collect, fm, openTasks, isUserNote, normalizeStage, BOARD_COLUMNS, templaterCommandId, captureFile, CAPTURES, isMainLeaf, findSearchCommand, SEARCH_PLUGINS };
