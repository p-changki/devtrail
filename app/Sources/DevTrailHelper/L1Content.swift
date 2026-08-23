import Foundation

extension L1Hubs {

    static func buildDashboard(P: JSONObject, date: String,
                               covStatus: Double, cfg: JSONObject) -> String {
        // ⚠️ 볼트에 없는 폴더는 버튼을 만들지 않는다. `k in P` — 키의 **존재**를
        //    본다. 값이 빈 문자열이어도 있는 것으로 친다(python 과 같다).
        let navSpec: [(String, String)] = [
            (I18n.t("nav.devlog"), "devlog"), (I18n.t("nav.devnote"), "devnote"),
            (I18n.t("nav.projects"), "projects"), (I18n.t("nav.idea"), "idea"),
            (I18n.t("nav.trouble"), "trouble"), (I18n.t("nav.library"), "library"),
            (I18n.t("nav.inbox"), "inbox"), (I18n.t("nav.zettel"), "zettel"),
        ]
        let navItems = navSpec.filter { P[$0.1] != nil }.map { ($0.0, p(P, $0.1)) }

        var parts: [String] = [
            fm([("scope", "vault"), ("created", date), ("updated", date)]),
            "",
            "# 📊 \(I18n.t("l1.dashboard"))",
            "",
            I18n.t("l1.entry"),
            "",
            nav(navItems.map { ($0.0, "\($0.1)/_index") }),
            "",
            "## 📅 \(I18n.t("l1.today"))",
            "",
            dv("""
            TASK
            FROM "\(p(P, "devlog"))"
            WHERE file.name = dateformat(date(today), "yyyy-MM-dd") + "\(devlogSuffix(cfg))"
            """),
            "",
            "### \(I18n.t("l1.h_recent_log"))",
            "",
            dv("""
            TABLE WITHOUT ID file.link AS "\(I18n.t("col.log"))", dateformat(file.mtime, "MM-dd HH:mm") AS "\(I18n.t("col.modified"))"
            FROM "\(p(P, "devlog"))"
            WHERE file.name != "_index"
            SORT file.name DESC
            LIMIT 5
            """),
            "",
            "### \(I18n.t("l1.h_recent_7"))",
            "",
            dv("""
            LIST
            FROM "\(p(P, "_root"))"
            WHERE file.ctime >= date(today) - dur(7 days)
              AND !contains(file.folder, "\(tplFolder(P))")
            SORT file.ctime DESC
            LIMIT 10
            """),
            "",
            "## \(I18n.t("l1.h_projects"))",
            "",
            dv("""
            TABLE status AS "\(I18n.t("col.status"))", stage AS "\(I18n.t("col.stage"))", updated AS "\(I18n.t("col.modified"))"
            FROM "\(p(P, "projects"))"
            WHERE type = "project-home"
            SORT updated DESC
            """),
            "",
            "## \(I18n.t("l1.h_areas"))",
            "",
        ]

        for (title, cats) in [("🌐 Infra · DevOps", ["infra", "devops"]),
                              ("💻 Backend · Frontend", ["backend", "frontend"]),
                              ("🧪 Testing · General", ["testing", "general"])] {
            let cond = cats.map { "category = \"\($0)\"" }.joined(separator: " OR ")
            parts += ["### \(title)", "",
                      dv("""
                      LIST
                      FROM "\(p(P, "devnote"))"
                      WHERE \(cond)
                      SORT file.mtime DESC
                      LIMIT 6
                      """), ""]
        }

        // 유지보수 — 커버리지에 따라 근거가 달라진다.
        parts += ["---", "", "## \(I18n.t("l1.h_maint"))", ""]
        if covStatus < 10 {
            parts += [I18n.t("l1.approx_size", ["pct": FolderHub.fmt(covStatus)]), ""]
        }
        parts += [
            "### \(I18n.t("l1.h_orphans"))",
            "",
            dv("""
            LIST
            FROM "\(p(P, "_root"))"
            WHERE length(file.outlinks) = 0 AND length(file.inlinks) = 0
              AND file.name != "_index" AND !contains(file.folder, "\(tplFolder(P))")
            SORT file.ctime DESC
            LIMIT 15
            """),
            "",
            "### \(I18n.t("l1.h_inbox_age"))",
            "",
            dv("""
            TABLE (date(today) - file.ctime).day AS "\(I18n.t("col.days"))"
            FROM "\(p(P, "inbox"))"
            WHERE file.name != "_index"
            SORT file.ctime ASC
            LIMIT 15
            """),
            "",
        ]
        return parts.joined(separator: "\n")
    }

    static func buildCheckin(P: JSONObject, date: String, cfg: JSONObject) -> String {
        [
            fm([("scope", "vault"), ("created", date), ("updated", date)]),
            "",
            "# \(I18n.t("l1.h_daily"))",
            "",
            I18n.t("l1.routine_intro"),
            "",
            "## \(I18n.t("l1.h_morning"))",
            "",
            I18n.t("l1.morning_1"),
            I18n.t("l1.evening_2"),
            "",
            "## \(I18n.t("l1.h_working"))",
            "",
            "| \(I18n.t("l1.tbl_what")) | \(I18n.t("l1.tbl_key")) |",
            "|---|---|",
            "| \(I18n.t("l1.row_note")) | `⌘⇧M` |",
            "| \(I18n.t("l1.row_stuck")) | \(I18n.t("l1.row_stuck_v")) |",
            "| \(I18n.t("l1.row_idea")) | `⌘⇧I` |",
            "| \(I18n.t("l1.row_save")) | `⌘⇧N` |",
            "",
            "## \(I18n.t("l1.h_evening"))",
            "",
            I18n.t("l1.evening_1"),
            I18n.t("l1.morning_2"),
            I18n.t("l1.evening_3"),
            "",
            "## \(I18n.t("l1.h_friday"))",
            "",
            I18n.t("l1.friday"),
            "",
            "---",
            "",
            "## \(I18n.t("l1.h_stale"))",
            "",
            dv("""
            TABLE (date(today) - file.ctime).day AS "\(I18n.t("col.days"))"
            FROM "\(p(P, "inbox"))"
            WHERE file.name != "_index" AND file.ctime <= date(today) - dur(14 days)
            SORT file.ctime ASC
            LIMIT 10
            """),
            "",
            "## \(I18n.t("l1.h_week"))",
            "",
            dv("""
            LIST
            FROM "\(p(P, "devlog"))"
            WHERE file.name != "_index" AND file.ctime >= date(today) - dur(7 days)
            SORT file.name DESC
            """),
            "",
            "## \(I18n.t("l1.h_created"))",
            "",
            dv("""
            LIST
            FROM "\(p(P, "_root"))"
            WHERE file.ctime >= date(today) AND !contains(file.folder, "\(tplFolder(P))")
            SORT file.ctime DESC
            """),
            "",
        ].joined(separator: "\n")
    }
}
