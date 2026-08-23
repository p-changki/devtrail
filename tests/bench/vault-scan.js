'use strict';
/* 홈 화면 1회 렌더가 볼트를 몇 번 훑고 얼마나 걸리는지 잰다.
 *
 * ⚠️ 고치기 전에 먼저 잰다. 재지 않고 고치면 나아졌는지 알 수 없다.
 *    이 저장소는 "테스트는 통과하는데 화면은 죽어 있던" 일을 겪었다 —
 *    숫자 없이 하는 판단을 믿지 않는다.
 */
const { render, PATHS } = require('../lib/render-view.js');

const DAY = 86400000;

/* 노트 n개짜리 합성 볼트. 프로젝트 수도 같이 정한다 —
 * 스캔 횟수가 프로젝트 수에 비례하는지 보려면 그게 변수여야 한다. */
function vault(n, projects) {
  const now = Date.now();
  const notes = [];
  for (let i = 0; i < projects; i++) {
    notes.push({
      path: `${PATHS.projects}/p${i}/README.md`,
      mtime: now - (i % 30) * DAY,
      ctime: now - 200 * DAY,
      fm: { type: 'project-home', status: 'active', stage: 'in-progress', next: `다음 ${i}` },
    });
  }
  let k = 0;
  while (notes.length < n) {
    const p = k % projects;
    notes.push({
      path: `${PATHS.projects}/p${p}/note-${k}.md`,
      mtime: now - (k % 60) * DAY,
      ctime: now - (k % 84) * DAY,
      fm: { type: 'devlog' },
      body: k % 20 === 0 ? '- [ ] 뭔가 할 일\n' : '',
    });
    k++;
  }
  return notes;
}

async function measure(route, notes) {
  // ⚠️ 첫 렌더는 JIT 워밍업이 섞인다. 한 번 버리고 세 번 재서 중앙값을 쓴다.
  await render(route, notes);
  const runs = [];
  let scans = 0;
  for (let i = 0; i < 3; i++) runs.push(await once(route, notes).then((r) => { scans = r.scans; return r.ms; }));
  runs.sort((a, b) => a - b);
  return { scans, ms: runs[1] };
}

async function once(route, notes) {
  let scans = 0;
  const t0 = process.hrtime.bigint();
  await render(route, notes, (app) => {
    const g = app.vault.getMarkdownFiles;
    app.vault.getMarkdownFiles = function () { scans++; return g.call(this); };
  });
  const ms = Number(process.hrtime.bigint() - t0) / 1e6;
  return { scans, ms };
}

async function main() {
  const cases = [
    { notes: 1000, projects: 5 },
    { notes: 1000, projects: 20 },
    { notes: 5000, projects: 20 },
    { notes: 10000, projects: 20 },
    { notes: 10000, projects: 50 },
    { notes: 10000, projects: 200 },
  ];
  const rows = [];
  for (const c of cases) {
    const notes = vault(c.notes, c.projects);
    const r = await measure('home', notes);
    rows.push({ ...c, ...r, ms: Math.round(r.ms * 10) / 10 });
  }
  const w = (s, n) => String(s).padStart(n);
  console.log('노트     프로젝트   스캔   ms');
  for (const r of rows) console.log(`${w(r.notes, 6)}${w(r.projects, 10)}${w(r.scans, 7)}${w(r.ms, 7)}`);
  if (process.env.BENCH_OUT) {
    require('fs').writeFileSync(process.env.BENCH_OUT, JSON.stringify(rows, null, 2) + '\n');
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
