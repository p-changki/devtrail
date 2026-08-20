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


def build_dashboard(P, date, cov):
    have = lambda k: k in P
    nav_items = [(lbl, P[k]) for lbl, k in [
        ("📝 개발일지", "devlog"), ("📂 개발메모", "devnote"),
        ("🏗️ 프로젝트", "projects"), ("💡 아이디어", "idea"),
        ("🔧 트러블슈팅", "trouble"), ("📚 라이브러리", "library"),
        ("📥 Inbox", "inbox"), ("🗂 카드노트", "zettel"),
    ] if have(k)]

    parts = [
        fm(scope="vault", created=date, updated=date),
        "",
        "# 📊 대시보드",
        "",
        "> 볼트의 진입점입니다. 왼쪽 사이드바에서 북마크해두면 편합니다.",
        "",
        nav([(l, f"{t}/_index") for l, t in nav_items]),
        "",
        "## 📅 오늘",
        "",
        dv(f'''TASK
FROM "{P.get("devlog", "")}"
WHERE file.name = dateformat(date(today), "yyyy-MM-dd") + " 개발일지"'''),
        "",
        "### 최근 개발일지",
        "",
        dv(f'''TABLE WITHOUT ID file.link AS "일지", dateformat(file.mtime, "MM-dd HH:mm") AS "수정"
FROM "{P.get("devlog", "")}"
WHERE file.name != "_index"
SORT file.name DESC
LIMIT 5'''),
        "",
        "### 최근 7일에 만든 노트",
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE file.ctime >= date(today) - dur(7 days)
  AND !contains(file.folder, "템플릿")
SORT file.ctime DESC
LIMIT 10'''),
        "",
        "## 🏗️ 진행 중인 프로젝트",
        "",
        dv(f'''TABLE status AS "상태", stage AS "단계", updated AS "수정"
FROM "{P.get("projects", "")}"
WHERE type = "project-home"
SORT updated DESC'''),
        "",
        "## 🧭 영역별 개발메모",
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
    parts += ["---", "", "## 🧹 볼트 유지보수", ""]
    if cov.get("status", 0) < 10:
        parts += [f"> ℹ️ `status` 커버리지가 {cov.get('status', 0)}% 라 "
                  "분량으로 근사합니다.", ""]
    parts += [
        "### 연결이 없는 노트",
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE length(file.outlinks) = 0 AND length(file.inlinks) = 0
  AND file.name != "_index" AND !contains(file.folder, "템플릿")
SORT file.ctime DESC
LIMIT 15'''),
        "",
        "### Inbox 적체 (오래된 순)",
        "",
        dv(f'''TABLE (date(today) - file.ctime).day AS "체류일"
FROM "{P.get("inbox", "")}"
WHERE file.name != "_index"
SORT file.ctime ASC
LIMIT 15'''),
        "",
    ]
    return "\n".join(parts)


def build_checkin(P, date):
    return "\n".join([
        fm(scope="vault", created=date, updated=date),
        "",
        "# ☀️ 일일 루틴",
        "",
        "> 하루를 여닫는 순서입니다. 5분이면 됩니다.",
        "",
        "## 🕗 아침 (2분)",
        "",
        "1. `⌘⇧D` — 개발일지를 만들고 오늘 할 것 Top 3 을 적는다",
        "2. 아래 '오래 묵은 것' 을 한 번 훑는다",
        "",
        "## 💻 작업 중 (수시)",
        "",
        "| 무엇 | 단축키 |",
        "|---|---|",
        "| 배운 것을 메모 | `⌘⇧M` |",
        "| 막힌 것을 기록 | 트러블슈팅 폴더에서 새 노트 |",
        "| 아이디어 캡처 | `⌘⇧I` |",
        "| 자료 저장 | `⌘⇧N` |",
        "",
        "## 🌇 퇴근 전 (3분)",
        "",
        "1. 개발일지의 '오늘 배운 것' 을 한 줄 채운다",
        "2. `⌘⇧G` — GitHub 활동을 일지에 넣는다",
        "3. 미완료를 내일로 옮긴다",
        "",
        "## 📅 금요일 (10분)",
        "",
        "주간리뷰를 만들고 아래 헬스체크를 본다.",
        "",
        "---",
        "",
        "## 🔴 오래 묵은 것",
        "",
        dv(f'''TABLE (date(today) - file.ctime).day AS "체류일"
FROM "{P.get("inbox", "")}"
WHERE file.name != "_index" AND file.ctime <= date(today) - dur(14 days)
SORT file.ctime ASC
LIMIT 10'''),
        "",
        "## 🟡 이번 주 개발일지 (공백일 확인)",
        "",
        dv(f'''LIST
FROM "{P.get("devlog", "")}"
WHERE file.name != "_index" AND file.ctime >= date(today) - dur(7 days)
SORT file.name DESC'''),
        "",
        "## 🟢 오늘 만든 노트",
        "",
        dv(f'''LIST
FROM "{P.get("_root", "")}"
WHERE file.ctime >= date(today) AND !contains(file.folder, "템플릿")
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
        "## 최근 활동",
        "",
        dv(f'''TABLE WITHOUT ID file.link AS "노트", file.folder AS "위치",
  dateformat(file.mtime, "MM-dd") AS "수정"
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

    write("대시보드.md", build_dashboard(P, date, cov))
    write("일일 체크인.md", build_checkin(P, date))

    print("\n".join(made))
    print(f"L1 허브 {len(made)}개 생성", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
