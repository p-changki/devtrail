#!/usr/bin/env python3
"""DevTrail — L1 대시보드 · L2 영역 허브 생성기.

L3(폴더 허브)는 hub.py 가 만든다. 여기는 그 위 두 층이다.

  L1  대시보드 · 일일 체크인      볼트 전체 · 오늘
  L2  개발/_index · 자료실/_index  영역 전체 · 하위 허브로 이동

⚠️ 원본 대시보드는 obsidian://open?vault=Obsidian%20Vault&file=... 형태의
   URL 을 버튼마다 박아뒀다. 볼트 이름과 경로가 퍼센트 인코딩된 채로 들어가서
   볼트명을 바꾸거나 폴더를 옮기면 버튼이 전부 죽는다.
   여기서는 위키링크만 쓴다 — Obsidian 이 파일을 옮겨도 따라간다.

⚠️ 쿼리는 커버리지에 맞춰 고른다. hub.py 와 같은 원칙이다.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from i18n import t as T  # noqa: E402


def load(path, default=None):
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def fm(**kw):
    lines = ["---", "tags:", "  - type/moc", "type: moc"]
    for k, v in kw.items():
        lines.append(f"{k}: {v}")
    lines.append("---")
    return "\n".join(lines)


def nav(items):
    """이동 버튼. devtrail.css 의 .dt-nav / .dt-btn 을 쓴다."""
    out = ['<div class="dt-nav">']
    for label, target in items:
        out.append(f'  <a class="dt-btn internal-link" data-href="{target}" '
                   f'href="{target}">{label}</a>')
    out.append("</div>")
    return "\n".join(out)


def dv(body):
    return "```dataview\n" + body.strip() + "\n```"


def devlog_suffix(cfg):
    """개발일지 파일명에서 날짜를 뺀 나머지.

    ⚠️ 여기를 박아두면 쿼리가 조용히 0건이 된다.
       설정은 "{{DATE}} devlog.md" 인데 쿼리가 " 개발일지" 를 찾고 있었다 —
       한국어 볼트에서도 오늘 할 일이 한 번도 뜨지 않았다.
    """
    pat = ((cfg.get("naming") or {}).get("devlog_file")
           or "{{DATE}} devlog.md")
    return pat.replace("{{DATE}}", "").replace(".md", "")


def tpl_folder(P):
    """템플릿 폴더 이름. 제외 조건에 쓴다.

    ⚠️ "템플릿" 을 박으면 영어 볼트에서 제외가 조용히 실패해
       템플릿 파일이 '최근 노트' 에 섞인다.
    """
    return (P.get("templates") or "Templates").split("/")[-1]


def build_dashboard(P, date, cov, cfg):
    have = lambda k: k in P
    nav_items = [(lbl, P[k]) for lbl, k in [
        (T("nav.devlog"), "devlog"), (T("nav.devnote"), "devnote"),
        (T("nav.projects"), "projects"), (T("nav.idea"), "idea"),
        (T("nav.trouble"), "trouble"), (T("nav.library"), "library"),
        (T("nav.inbox"), "inbox"), (T("nav.zettel"), "zettel"),
    ] if have(k)]

    parts = [
        fm(scope="vault", created=date, updated=date),
        "",
        f'# 📊 {T("l1.dashboard")}',
        "",
        T("l1.entry"),
        "",
        nav([(l, f"{t}/_index") for l, t in nav_items]),
        "",
        f'## 📅 {T("l1.today")}',
        "",
        dv(f'''TASK
FROM "{P.get("devlog", "")}"
WHERE file.name = dateformat(date(today), "yyyy-MM-dd") + "{devlog_suffix(cfg)}"'''),
        "",
        f'### {T("l1.h_recent_log")}',
        "",
        dv(f'''TABLE WITHOUT ID file.link AS "{T("col.log")}", dateformat(file.mtime, "MM-dd HH:mm") AS "{T("col.modified")}"
FROM "{P.get("devlog", "")}"
WHERE file.name != "_index"
SORT file.name DESC
LIMIT 5'''),
        "",
        f'### {T("l1.h_recent_7")}',
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE file.ctime >= date(today) - dur(7 days)
  AND !contains(file.folder, "{tpl_folder(P)}")
SORT file.ctime DESC
LIMIT 10'''),
        "",
        f'## {T("l1.h_projects")}',
        "",
        dv(f'''TABLE status AS "{T("col.status")}", stage AS "{T("col.stage")}", updated AS "{T("col.modified")}"
FROM "{P.get("projects", "")}"
WHERE type = "project-home"
SORT updated DESC'''),
        "",
        f'## {T("l1.h_areas")}',
        "",
    ]

    for title, cats in [("🌐 Infra · DevOps", ["infra", "devops"]),
                        ("💻 Backend · Frontend", ["backend", "frontend"]),
                        ("🧪 Testing · General", ["testing", "general"])]:
        cond = " OR ".join(f'category = "{c}"' for c in cats)
        parts += [f"### {title}", "",
                  dv(f'''LIST
FROM "{P.get("devnote", "")}"
WHERE {cond}
SORT file.mtime DESC
LIMIT 6'''), ""]

    # 유지보수 — 커버리지에 따라 근거가 달라진다
    parts += ["---", "", f'## {T("l1.h_maint")}', ""]
    if cov.get("status", 0) < 10:
        parts += [T("l1.approx_size", pct=cov.get("status", 0)), ""]
    parts += [
        f'### {T("l1.h_orphans")}',
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE length(file.outlinks) = 0 AND length(file.inlinks) = 0
  AND file.name != "_index" AND !contains(file.folder, "{tpl_folder(P)}")
SORT file.ctime DESC
LIMIT 15'''),
        "",
        f'### {T("l1.h_inbox_age")}',
        "",
        dv(f'''TABLE (date(today) - file.ctime).day AS "{T("col.days")}"
FROM "{P.get("inbox", "")}"
WHERE file.name != "_index"
SORT file.ctime ASC
LIMIT 15'''),
        "",
    ]
    return "\n".join(parts)


def build_checkin(P, date, cfg):
    return "\n".join([
        fm(scope="vault", created=date, updated=date),
        "",
        f'# {T("l1.h_daily")}',
        "",
        T("l1.routine_intro"),
        "",
        f'## {T("l1.h_morning")}',
        "",
        T("l1.morning_1"),
        T("l1.evening_2"),
        "",
        f'## {T("l1.h_working")}',
        "",
        f'| {T("l1.tbl_what")} | {T("l1.tbl_key")} |',
        "|---|---|",
        f'| {T("l1.row_note")} | `⌘⇧M` |',
        f'| {T("l1.row_stuck")} | {T("l1.row_stuck_v")} |',
        f'| {T("l1.row_idea")} | `⌘⇧I` |',
        f'| {T("l1.row_save")} | `⌘⇧N` |',
        "",
        f'## {T("l1.h_evening")}',
        "",
        T("l1.evening_1"),
        T("l1.morning_2"),
        T("l1.evening_3"),
        "",
        f'## {T("l1.h_friday")}',
        "",
        T("l1.friday"),
        "",
        "---",
        "",
        f'## {T("l1.h_stale")}',
        "",
        dv(f'''TABLE (date(today) - file.ctime).day AS "{T("col.days")}"
FROM "{P.get("inbox", "")}"
WHERE file.name != "_index" AND file.ctime <= date(today) - dur(14 days)
SORT file.ctime ASC
LIMIT 10'''),
        "",
        f'## {T("l1.h_week")}',
        "",
        dv(f'''LIST
FROM "{P.get("devlog", "")}"
WHERE file.name != "_index" AND file.ctime >= date(today) - dur(7 days)
SORT file.name DESC'''),
        "",
        f'## {T("l1.h_created")}',
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE file.ctime >= date(today) AND !contains(file.folder, "{tpl_folder(P)}")
SORT file.ctime DESC'''),
        "",
    ])


def build_area(name, title, children, P, date):
    """L2 영역 허브. 하위 폴더 허브로 가는 입구."""
    items = [(lbl, f"{P[k]}/_index") for lbl, k in children if k in P]
    return "\n".join([
        fm(scope="area", created=date, updated=date),
        "",
        f"# {title}",
        "",
        nav(items) if items else "",
        "",
        f'## {T("l1.h_recent_act")}',
        "",
        dv(f'''TABLE WITHOUT ID file.link AS "{T("col.note")}", file.folder AS "{T("col.where")}",
  dateformat(file.mtime, "MM-dd") AS "{T("col.modified")}"
FROM "{P.get(name, "")}"
WHERE file.name != "_index"
SORT file.mtime DESC
LIMIT 20'''),
        "",
    ])


def main():
    paths_file, cfg_file, scan_file, outdir = sys.argv[1:5]
    P = (load(paths_file, {}) or {}).get("paths") or {}
    cfg = load(cfg_file, {}) or {}
    scan = load(scan_file, {}) or {}
    date = os.environ.get("DT_DATE", "")

    root = (cfg.get("vault") or {}).get("root") or ""
    P["_root"] = root

    cov = {k: (scan.get("fields", {}).get(k, {}) or {}).get("value_pct", 0)
           for k in ("status", "review_at")}

    os.makedirs(outdir, exist_ok=True)
    made = []

    def write(name, body):
        path = os.path.join(outdir, name)
        if os.path.exists(path):
            return
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
        made.append(name)

    write(T("l1.dashboard") + ".md", build_dashboard(P, date, cov, cfg))
    write(T("l1.checkin") + ".md", build_checkin(P, date, cfg))

    print("\n".join(made))
    print(f"L1 {len(made)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
