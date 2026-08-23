#!/usr/bin/env bash
# view.js 를 **실제로 렌더해 본다**.
#
# ⚠️ 이 파일이 왜 생겼나: 화면 코드를 부르지 않는 테스트는 화면이 뜨는지
#    말해 주지 못한다. 2026-08-23 에 파일을 나누면서 세 번 연속으로 놓쳤다 —
#    전부 테스트는 녹색이었고 실물에서만 드러났다:
#
#      1. view.js 가 require('obsidian')  → 절대경로 모듈은 못 한다
#      2. view.js 가 main 의 RM 참조       → ReferenceError, 빈 화면
#      3. main 이 daysBetween 을 안 넘김   → 기한 초과 항목에서 죽음
#
# ⚠️ 진짜 DOM 이 아니다. 픽셀도 레이아웃도 검증하지 못한다. 여기서 잡는 것은
#    "부르면 죽는가" 하나다 — 그것만으로 위 셋을 다 잡는다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT

if ! command -v node >/dev/null 2>&1; then
  t_start "화면 렌더"
  dim "   node 없음 — 건너뜀 (⚠️ 화면이 죽어도 모른다)"
  t_end
  exit 0
fi

cat > "$T_TMP/run.js" <<'JSEOF'
const h = require(process.argv[2]);

const NOTES = {
  full: [
    { path: 'notes/개발/프로젝트/a/README.md',
      fm: { type: 'project-home', status: 'active', stage: 'planning', project: 'a' } },
    { path: 'notes/개발/프로젝트/b/README.md',
      fm: { type: 'project-home', status: 'active', stage: 'blocked', project: 'b' },
      mtime: Date.now() - 40 * 86400000 },
    { path: 'notes/개발/개발일지/2026-08-23 devlog.md', fm: { type: 'devlog' },
      body: '- [ ] 지난 것 📅 2020-01-01\n- [ ] 기한 없는 것\n- [x] 끝난 것\n' },
    { path: 'notes/자료실/생각.md', fm: { type: 'idea', status: 'inbox' } },
    { path: 'notes/개발/문제.md', fm: { type: 'trouble' } },
    { path: 'notes/개발/밀린것.md', fm: { type: 'note', review_at: '2020-01-01' } },
  ],
  // ⚠️ 빈 볼트에서도 죽지 않아야 한다. 0 을 다루는 가지가 따로 있다.
  empty: [],
  // ⚠️ frontmatter 가 없는 노트(가져온 문서)만 있는 볼트.
  untyped: [{ path: 'notes/레포docs/x.md', fm: {}, body: '- [ ] 남의 항목\n' }],
};

(async () => {
  const out = [];
  for (const route of ['home', 'today', 'projects', 'reviews', 'recent']) {
    for (const [name, notes] of Object.entries(NOTES)) {
      try {
        const root = await h.render(route, notes);
        const cls = h.collectClasses(root);
        // ⚠️ render 가 이제 스스로 오류를 잡아 화면에 적는다. 그래서 "예외가
        //    안 났다" 로는 부족하다 — 실패 상자가 그려졌으면 실패다.
        //    이걸 안 보면 방금 만든 안전장치가 테스트를 눈멀게 한다.
        if (cls.has('devtrail-cc-recovery')) {
          const why = h.collectText(root).slice(0, 3).join(' / ');
          out.push(`FAIL ${route}/${name} 렌더 실패 상자: ${why}`);
        } else {
          out.push(`OK ${route}/${name} ${cls.size}`);
        }
      } catch (e) {
        out.push(`FAIL ${route}/${name} ${e.message}`);
      }
    }
  }
  console.log(out.join('\n'));
})();
JSEOF

RES=$(node "$T_TMP/run.js" "$ROOT/tests/lib/render-view.js" 2>&1)

t_start "모든 라우트가 렌더된다"
t_eq "죽는 조합이 없다" "" "$(printf '%s\n' "$RES" | grep '^FAIL' | head -3 | tr '\n' ' ')"
for route in home today projects reviews recent; do
  t_contains "$route" "OK $route/full" "$RES"
done

t_start "빈 볼트에서도 죽지 않는다"
# ⚠️ 0 을 다루는 가지는 따로다. 데이터가 있을 때만 시험하면 그 가지는
#    사용자가 처음 설치한 날 처음 실행된다.
for route in home today projects reviews recent; do
  t_contains "$route" "OK $route/empty" "$RES"
done

t_start "분류 없는 노트만 있어도 죽지 않는다"
for route in home projects; do
  t_contains "$route" "OK $route/untyped" "$RES"
done

t_start "홈이 실제로 무언가를 그린다"
# ⚠️ '안 죽었다' 와 '그렸다' 는 다르다. 빈 화면도 안 죽는다.
cat > "$T_TMP/what.js" <<'JSEOF'
const h = require(process.argv[2]);
(async () => {
  const root = await h.render('home', [
    { path: 'notes/개발/프로젝트/a/README.md',
      fm: { type: 'project-home', status: 'active', stage: 'planning', project: 'a' } },
    { path: 'notes/개발/개발일지/2026-08-23 devlog.md', fm: { type: 'devlog' },
      body: '- [ ] 지난 것 📅 2020-01-01\n' },
  ]);
  const cls = h.collectClasses(root);
  const need = ['devtrail-cc-nav', 'devtrail-cc-searchbox', 'devtrail-cc-heat',
                'devtrail-cc-stats', 'devtrail-cc-table', 'devtrail-cc-recent'];
  console.log(need.filter((c) => !cls.has(c)).join(' '));
})();
JSEOF
t_eq "빠진 영역이 없다" "" "$(node "$T_TMP/what.js" "$ROOT/tests/lib/render-view.js" 2>&1 | tail -1)"

t_end
