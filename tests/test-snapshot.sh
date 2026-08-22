#!/usr/bin/env bash
# devtrail command-center snapshot — Obsidian 없이 보는 상태
#
# ⚠️ 이 파일의 핵심은 마지막 「계약」 절이다. 집계 규칙이 두 벌(CLI 의
#    lib/snapshot.py, 플러그인의 collect())이므로, 같은 볼트에서 **둘을 실제로
#    돌려 비교**한다. 어긋나면 빨간불이다.
#
#    이 저장소는 dirs.devlog 의 기본값을 네 곳이 각자 가져 같은 결함을 네 번
#    고쳤다. 두 벌을 허용하는 결정(ADR 0003)은 이 테스트가 있는 동안에만
#    유효하다.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$ROOT/tests/lib/harness.sh"
DT="$ROOT/bin/devtrail"
T_TMP="$(mktemp -d)"
trap 'rm -rf "$T_TMP"' EXIT
export DEVTRAIL_OBSIDIAN_REGISTRY="$T_TMP/reg.json"

_cfg() {
  local v="$1" h="$2"; mkdir -p "$h"
  jq -n --arg v "$v" '{version:3, lang:"ko",
    vault:{backend:"local", path:$v, root:"notes"}, dirs:{},
    github:{user:"t", repos:[], project_groups:{}},
    install:{mode:"new", modules:["devlog"]}}' > "$h/devtrail.config.json"
}
note() {  # note <경로> <frontmatter 줄들…>
  local f="$1"; shift
  mkdir -p "$(dirname "$f")"
  { printf -- '---\n'; for l in "$@"; do printf '%s\n' "$l"; done; printf -- '---\n\n# 노트\n'; } > "$f"
}

# 여러 상황을 한 볼트에 담는다.
V="$T_TMP/v"; H="$T_TMP/h"; _cfg "$V" "$H"
N="$V/notes"
mkdir -p "$N/개발/개발일지" "$N/개발/프로젝트" "$N/템플릿"
note "$N/개발/프로젝트/alpha/README.md" "type: project-home" "status: active" "stage: planning" "project: alpha" "next_action: API 정리"
note "$N/개발/프로젝트/beta/README.md"  "type: project-home" "status: active" "stage: in-progress" "project: beta"
note "$N/개발/프로젝트/gone/README.md"  "type: project-home" "status: archived" "project: gone"
note "$N/자료실/생각1.md" "type: idea" "status: inbox" "created: 2026-08-01"
note "$N/자료실/생각2.md" "type: idea" "status: inbox" "created: 2026-08-10"
note "$N/개발/문제1.md"   "type: trouble" "status: open"
# ⚠️ 계약 테스트가 '어느 쪽이 규칙을 바꿔도' 잡으려면, 규칙마다 그것을
#    구분해 주는 노트가 있어야 한다. 아래는 type 은 idea 지만 Inbox 가
#    아니다 — 어느 한쪽이 "idea 도 Inbox 로 친다" 로 바뀌면 수가 갈린다.
note "$N/자료실/아이디어아님.md" "type: idea" "status: active"
# type 은 project-home 이지만 활성이 아니다 (위 gone 과 함께).
# review_at 이 미래인 것 — '지난 것' 판정이 바뀌면 갈린다.
note "$N/개발/나중에볼것.md" "type: note" "review_at: 2099-12-31"
note "$N/개발/밀린것.md"  "type: note" "review_at: 2020-01-01"
# ⚠️ 아래 셋은 세면 안 되는 것들이다.
note "$N/템플릿/유튜브 노트 템플릿.md" "type: youtube" "status: inbox"
note "$N/개발/프로젝트/_index.md" "type: moc" "status: inbox"
note "$N/개발/_숨김.md" "type: idea" "status: inbox"

TODAY=$(date +%F)
printf -- '---\ntype: devlog\n---\n\n- [ ] 진짜 할 일\n- [ ] \n- [x] 끝난 것\n' \
  > "$N/개발/개발일지/$TODAY devlog.md"

run() { DEVTRAIL_HOME="$H" DEVTRAIL_CONFIG="$H/devtrail.config.json" "$DT" "$@"; }
SNAP="$T_TMP/snap.json"
run command-center snapshot --json > "$SNAP" 2>/dev/null

t_start "유효한 JSON 을 낸다"
t_json "파싱된다" "$SNAP"
for k in configured vault today projects inbox notes command_center obsidian; do
  t_eq "필드 $k" "true" "$(jq --arg k "$k" 'has($k)' "$SNAP")"
done

t_start "세면 안 되는 것을 세지 않는다"
# ⚠️ 템플릿·_index·밑줄 파일이 섞이면 숫자가 늘 조금씩 크고, 아무도 왜인지
#    모른다. 이것이 이 프로젝트가 반복해서 밟은 자리다.
t_eq "활성 프로젝트는 둘" "2" "$(jq '.projects.active_count' "$SNAP")"
t_eq "Inbox 는 둘" "2" "$(jq '.inbox.count' "$SNAP")"
t_eq "트러블슈팅은 하나" "1" "$(jq '.notes.trouble' "$SNAP")"
t_eq "밀린 것은 하나" "1" "$(jq '.notes.overdue' "$SNAP")"
t_not_contains "템플릿이 안 보인다" "템플릿" "$(jq -r '.inbox.preview[].path' "$SNAP")"
t_not_contains "허브가 안 보인다" "_index" "$(jq -r '.inbox.preview[].path' "$SNAP")"
t_not_contains "밑줄 파일이 안 보인다" "_숨김" "$(jq -r '.inbox.preview[].path' "$SNAP")"

t_start "오늘 할 일은 내용이 있는 것만 센다"
# ⚠️ 템플릿이 넣는 빈 '- [ ]' 를 세면 아무것도 안 쓴 날에 '할 일 3개' 라고 한다.
t_eq "개발일지가 있다" "true" "$(jq '.today.devlog_exists' "$SNAP")"
t_eq "미완료는 하나" "1" "$(jq '.today.open_tasks' "$SNAP")"

t_start "다음 행동은 있는 것만 싣는다"
t_eq "하나뿐이다" "1" "$(jq '.projects.next_actions | length' "$SNAP")"
t_eq "그것이 alpha 다" "alpha" "$(jq -r '.projects.next_actions[0].project' "$SNAP")"

t_start "Inbox 는 오래된 것부터"
t_eq "생각1 이 먼저" "생각1" "$(jq -r '.inbox.preview[0].title' "$SNAP")"
t_ne "가장 오래된 날짜가 있다" "null" "$(jq -r '.inbox.oldest_at' "$SNAP")"

t_start "읽기만 한다"
sig=$(find "$N" -type f | sort | xargs stat -f '%N %m %z' 2>/dev/null | md5 -q 2>/dev/null || echo x)
run command-center snapshot --json >/dev/null 2>&1
t_eq "볼트가 그대로다" "$sig" \
  "$(find "$N" -type f | sort | xargs stat -f '%N %m %z' 2>/dev/null | md5 -q 2>/dev/null || echo x)"

t_start "볼트가 없으면 없다고 말한다"
VX="$T_TMP/novault"; HX="$T_TMP/hx"; _cfg "$VX" "$HX"
sx=$(DEVTRAIL_HOME="$HX" DEVTRAIL_CONFIG="$HX/devtrail.config.json" \
     "$DT" command-center snapshot --json 2>/dev/null)
printf '%s' "$sx" > "$T_TMP/nos.json"
t_json "그래도 유효한 JSON" "$T_TMP/nos.json"
t_eq "볼트를 못 찾았다고 한다" "false" "$(jq '.vault.available' "$T_TMP/nos.json")"
# ⚠️ 못 본 것을 0 이라고 하지 않는다. 세어 본 적이 없는 것과 세어 보니 0 인 것은
#    다른 사실이다.
t_eq "숫자를 지어내지 않는다" "null" "$(jq '.projects' "$T_TMP/nos.json")"

# ── 계약: 두 구현이 같은 답을 내는가 ────────────────────────────────────────
t_start "플러그인과 CLI 가 같은 수를 센다"
cat > "$T_TMP/contract.js" <<'JSEOF'
// 플러그인의 collect() 를 파일시스템 위에서 그대로 돌린다.
// Obsidian 의 vault/metadataCache 를 최소한으로 흉내 낸다.
const Module = require('module');
const orig = Module._load;
Module._load = function (r, p, m) {
  if (r === 'obsidian') return { Plugin: class {}, ItemView: class {} };
  return orig(r, p, m);
};
const fs = require('fs'), path = require('path');
const P = require(process.argv[2]).__test;
if (!P || typeof P.collect !== 'function') { console.log('NOHOOK'); process.exit(0); }

const root = process.argv[3];
const templatesRel = process.argv[4];

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith('.')) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) walk(full, out);
    else if (e.name.endsWith('.md')) out.push(full);
  }
  return out;
}
const FM = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/;
function frontmatter(full) {
  const raw = fs.readFileSync(full, 'utf8');
  const m = FM.exec(raw);
  if (!m) return {};
  const o = {};
  for (const line of m[1].split('\n')) {
    if (/^[\s\-]/.test(line) || !line.includes(':')) continue;
    const i = line.indexOf(':');
    let v = line.slice(i + 1).trim();
    if (v.length >= 2 && v[0] === v[v.length - 1] && (v[0] === '"' || v[0] === "'")) v = v.slice(1, -1);
    o[line.slice(0, i).trim()] = v;
  }
  return o;
}
const files = walk(root, []).map((full) => {
  const rel = path.relative(root, full);
  const st = fs.statSync(full);
  return {
    path: rel,
    basename: path.basename(rel, '.md'),
    parent: { name: path.basename(path.dirname(rel)) },
    stat: { mtime: st.mtimeMs, ctime: (st.birthtimeMs || st.ctimeMs) },
    __full: full,
  };
});
const app = {
  vault: { getMarkdownFiles: () => files },
  metadataCache: { getFileCache: (f) => ({ frontmatter: frontmatter(f.__full) }) },
};
const c = P.collect(app, { templates: templatesRel });
console.log(JSON.stringify({
  projects: c.projects.length,
  inbox: c.inbox.length,
  trouble: c.trouble.length,
  overdue: c.overdue.length,
  total: c.total,
  this_week: c.thisWeek,
  first_inbox: c.inbox.length ? c.inbox[0].file.basename : null,
  first_project: c.projects.length ? c.projects[0].name : null,
  // ⚠️ CLI 의 next_actions 는 '다음 행동이 적힌 것' 만 싣는다. 전체 첫 항목과
  //    비교하면 서로 다른 것을 견주게 된다 — 같은 기준으로 뽑아 비교한다.
  first_with_next: (c.projects.find((p) => p.next) || {}).name || "",
}));
JSEOF
if command -v node >/dev/null 2>&1; then
  PLUG=$(node "$T_TMP/contract.js" "$ROOT/plugin/main.js" "$N" "템플릿" 2>&1 | tail -1)
  printf '%s' "$PLUG" > "$T_TMP/plug.json"
  t_json "플러그인 결과가 JSON" "$T_TMP/plug.json"
  # CLI 쪽 같은 수치
  jq -n --slurpfile s "$SNAP" '{
    projects: $s[0].projects.active_count,
    inbox: $s[0].inbox.count,
    trouble: $s[0].notes.trouble,
    overdue: $s[0].notes.overdue,
    total: $s[0].notes.total,
    this_week: $s[0].notes.this_week
  }' > "$T_TMP/cli.json"
  for k in projects inbox trouble overdue total this_week; do
    t_eq "계약: $k" "$(jq -r --arg k "$k" '.[$k]' "$T_TMP/plug.json")" \
                    "$(jq -r --arg k "$k" '.[$k]' "$T_TMP/cli.json")"
  done
  # 정렬 규칙도 같아야 한다 — 개수만 같고 순서가 다르면 화면이 갈린다.
  t_eq "계약: Inbox 첫 항목" "$(jq -r '.first_inbox' "$T_TMP/plug.json")" \
                              "$(jq -r '.inbox.preview[0].title' "$SNAP")"
  t_eq "계약: 다음 행동 첫 항목" "$(jq -r '.first_with_next' "$T_TMP/plug.json")" \
                                  "$(jq -r '[.projects.next_actions[].project] + [""] | .[0]' "$SNAP")"
else
  dim "   node 없음 — 계약 검사를 건너뜀 (⚠️ 두 구현이 갈려도 모른다)"
fi

t_start "개발일지 파일명의 출처가 하나다"
# ⚠️ '{{DATE}} devlog.md' 기본값이 생성 스크립트·메뉴바 앱·snapshot 세 곳에
#    각자 있었다. 이 저장소가 dirs.devlog 로 네 번 고친 것과 같은 병이다.
#    dt_devlog_name 하나만 그 값을 안다.
# ⚠️ 아직 네 곳(생성 스크립트·대시보드 서버·허브 생성기·설정 템플릿)이 각자
#    기본값을 갖고 있다. 그 넷은 이번 범위 밖이라 손대지 않았고, 보고했다.
#    여기서는 **이번에 손댄 둘**만 지킨다: 메뉴바 앱과 snapshot.
t_eq "앱이 자기 기본값을 갖지 않는다" "0" \
  "$(grep -rc '{{DATE}} devlog.md' "$ROOT/app/Sources"/*/*.swift 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
t_eq "snapshot 이 자기 기본값을 갖지 않는다" "0" \
  "$(grep -c '{{DATE}} devlog.md' "$ROOT/lib/commandcentercmd.sh" | tr -d ' ')"
t_contains "단일 출처 함수가 있다" "dt_devlog_name" "$(cat "$ROOT/lib/common.sh")"
# snapshot 이 실제 경로를 알려주므로 앱이 조립할 필요가 없다.
t_ne "snapshot 이 경로를 알려준다" "null" "$(jq -r '.today.devlog_path' "$SNAP")"
t_eq "그 경로가 실제 파일이다" "yes" \
  "$([ -f "$(jq -r '.today.devlog_path' "$SNAP")" ] && echo yes || echo no)"

t_end
