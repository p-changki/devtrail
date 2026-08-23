#!/usr/bin/env bash
# 홈 1회 렌더가 볼트를 **몇 번** 훑는가.
#
# ⚠️ 여기서 지키는 것은 속도가 아니라 **차수**다. 스캔 횟수가 프로젝트 수에
#    따라 늘어나면 볼트가 커질수록 느려진다 — 2026-08-23 측정:
#
#      노트 10000 · 프로젝트 200 → 스캔 203회 · 130ms
#
#    ms 를 단언하지 않는다. 기계마다 다르고, 느려도 통과하는 숫자를 고르면
#    아무것도 지키지 못한다. 대신 **프로젝트 수를 10배로 늘려도 스캔 횟수가
#    그대로인가** 를 본다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

if ! command -v node >/dev/null 2>&1; then
  t_start "볼트 스캔 횟수"
  dim "   node 없음 — 건너뜀"
  t_end
  exit 0
fi

cat > "$T_TMP/scan.js" <<'JSEOF'
const h = require(process.argv[2]);
const DAY = 86400000;

function vault(n, projects) {
  const now = Date.now();
  const notes = [];
  for (let i = 0; i < projects; i++) {
    notes.push({
      path: `${h.PATHS.projects}/p${i}/README.md`,
      mtime: now - (i % 30) * DAY, ctime: now - 200 * DAY,
      fm: { type: 'project-home', status: 'active', stage: 'in-progress' },
    });
  }
  let k = 0;
  while (notes.length < n) {
    const p = k % projects;
    notes.push({
      path: `${h.PATHS.projects}/p${p}/note-${k}.md`,
      mtime: now - (k % 60) * DAY, ctime: now - (k % 84) * DAY,
      fm: { type: 'devlog' },
      body: k % 20 === 0 ? '- [ ] 뭔가 할 일\n' : '',
    });
    k++;
  }
  return notes;
}

async function scans(n, projects) {
  let c = 0;
  await h.render('home', vault(n, projects), (app) => {
    const g = app.vault.getMarkdownFiles;
    app.vault.getMarkdownFiles = function () { c++; return g.call(this); };
  });
  return c;
}

(async () => {
  const few = await scans(400, 5);
  const many = await scans(400, 50);
  console.log(JSON.stringify({ few, many }));
})().catch((e) => { console.error(e); process.exit(1); });
JSEOF

OUT=$(node "$T_TMP/scan.js" "$ROOT/tests/lib/render-view.js" 2>&1) || { echo "$OUT"; exit 1; }
FEW=$(printf '%s' "$OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["few"])')
MANY=$(printf '%s' "$OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin)["many"])')

t_start "볼트 스캔 횟수가 프로젝트 수를 따라가지 않는다"
t_eq "프로젝트 5개와 50개의 스캔 횟수가 같다" "$FEW" "$MANY"
t_start "스캔은 렌더당 한 번이다"
# ⚠️ 상한을 1 로 둔다. '적당히 작다' 는 기준은 다음 사람이 하나씩 늘린다.
t_eq "홈 1회 렌더 = 스캔 1회" "1" "$FEW"
t_end
