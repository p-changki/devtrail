import Foundation

extension Hotkeys {

    /// 폴더 → 템플릿 매핑. 새 노트를 만들면 양식이 자동으로 채워진다.
    ///
    /// ⚠️ (폴더 키, 한국어 파일명, 영어 파일명). **순서가 출력 순서다.**
    static let folderTemplateMapping: [(String, String, String)] = [
        ("devlog",  "개발일지양식.md",              "Devlog.md"),
        ("devnote", "개발메모 템플릿.md",           "Dev note.md"),
        ("inbox",   "Inbox Capture 템플릿.md",      "Inbox capture.md"),
        ("idea",    "아이디어 빠른저장 템플릿.md",  "Quick idea.md"),
        ("trouble", "트러블슈팅 템플릿.md",         "Troubleshooting.md"),
        ("youtube", "유튜브 노트 템플릿.md",        "YouTube note.md"),
        ("library", "라이브러리 등록 템플릿.md",    "Library entry.md"),
        ("zettel",  "영구 카드노트 템플릿.md",      "Zettel.md"),
        ("moc",     "MOC 템플릿.md",                "MOC.md"),
        ("report",  "회고 템플릿.md",               "Retro.md"),
        ("todo",    "투두리스트 템플릿.md",         "Todo list.md"),
        ("journal", "일기양식.md",                  "Journal.md"),
        ("book",    "책 템플릿.md",                 "Book.md"),
    ]

    static func buildTemplater(tmplRel: String, paths: JSONObject, existing: JSONObject,
                               have: Set<String>?, spec: JSONObject)
        -> (JSONObject, Int) {
        var out = existing
        var old: [JSON] = []
        if case .array(let a)? = out["folder_templates"] { old = a }

        var taken = Set<String>()
        for m in old {
            guard case .object(let o) = m else { continue }
            taken.insert(Py.str(o["folder"]))
        }

        var added = 0
        for (key, tplKO, tplEN) in folderTemplateMapping {
            let tpl = I18n.lang == "en" ? tplEN : tplKO
            let folder = Py.str(paths[key])
            // 사용자가 이미 매핑한 폴더는 건드리지 않는다.
            if folder.isEmpty || taken.contains(folder) { continue }
            // 없는 템플릿을 가리키면 새 노트가 빈 채로 만들어진다.
            if let have, !have.contains(tpl) { continue }
            old.append(.object(JSONObject([
                ("folder", .string(folder)),
                ("template", .string("\(tmplRel)/\(tpl)")),
            ])))
            added += 1
        }

        out["folder_templates"] = .array(old)
        // python: `out.get("templates_folder") or tmpl_rel` — 빈 문자열도 대체된다.
        let existingFolder = Py.str(out["templates_folder"])
        out["templates_folder"] = .string(existingFolder.isEmpty ? tmplRel : existingFolder)
        out["syntax_highlighting"] = .bool(Py.bool(out["syntax_highlighting"], true))
        setTrigger(&out)
        setTemplateHotkeys(&out, spec: spec, tmplRel: tmplRel, have: have)
        return (out, added)
    }

    /// 단축키를 걸 템플릿을 Templater 에 등록한다.
    ///
    /// ⚠️ Templater 는 이 목록에 있는 템플릿에만 명령을 만든다. 비워두면
    ///    `templater-obsidian:create-<경로>` 라는 명령이 **아예 없는데**
    ///    hotkeys.json 에는 그 ID 로 키가 배정된다 — 눌러도 아무 일도
    ///    일어나지 않는다. "단축키 13개 등록" 이라고 보고하면서 실제로는
    ///    0개였다 (2026-08-22 실물 QA 에서 ⌘⇧D 무반응으로 발견).
    static func setTemplateHotkeys(_ out: inout JSONObject, spec: JSONObject,
                                   tmplRel: String, have: Set<String>?) {
        var want: [String] = []
        if case .array(let ts)? = spec["templater"] {
            for tv in ts {
                guard case .object(let t) = tv else { continue }
                let name = tplName(t)
                if let have, !have.contains(name) { continue }
                want.append("\(tmplRel)/\(name)")
            }
        }

        // 사용자가 직접 넣은 항목은 그대로 둔다. 문자열·객체 두 형태를 모두 쓴다.
        var old: [JSON] = []
        if case .array(let a)? = out["enabled_templates_hotkeys"] { old = a }
        var known = Set<String>()
        for e in old {
            switch e {
            case .string(let s): known.insert(s)
            case .object(let o): known.insert(Py.str(o["template"]))
            default: known.insert("")
            }
        }
        for w in want where !known.contains(w) {
            old.append(.string(w))
            known.insert(w)
        }
        out["enabled_templates_hotkeys"] = .array(old)
    }

    /// 새 파일을 만들 때 폴더 템플릿이 자동으로 들어가게 한다.
    ///
    /// ⚠️ Templater 2.x 는 키를 바꿨다. 예전 키는 로드할 때 **삭제된다** —
    ///    예전 키만 쓰면 모드가 "none" 이 되고 자동 삽입이 통째로 꺼진다
    ///    (2026-08-22 실물 QA 에서 확인). 게다가 `data_version` 이 없으면
    ///    Templater 가 "설정을 초기화했습니다" 경고까지 띄운다.
    ///
    ///    설치된 플러그인이 말하는 버전을 읽어 맞는 키를 쓴다. 읽지 못하면
    ///    예전 키로 떨어진다 — 구버전에서는 그게 맞는 키다. **짐작하지 않는다.**
    static func setTrigger(_ out: inout JSONObject) {
        let dir = ProcessInfo.processInfo.environment["DT_TEMPLATER_DIR"] ?? ""
        guard let ver = templaterSchemaVersion(dir) else {
            out["trigger_on_file_creation"] = .bool(true)
            out["enable_folder_templates"] = .bool(true)
            return
        }
        out["data_version"] = .int(ver)
        out["trigger_on_file_creation_mode"] = .string("folder")
        // 예전 키가 남아 있으면 경고를 띄우므로 치운다.
        for k in ["trigger_on_file_creation", "enable_folder_templates",
                  "enable_file_templates"] {
            out[k] = nil
        }
    }

    /// 설치된 Templater 가 쓰는 설정 스키마 버전. 못 읽으면 nil.
    ///
    /// python: `re.search(r"data_version\s*:\s*(\d+)", src)`
    static func templaterSchemaVersion(_ pluginDir: String) -> Int? {
        if pluginDir.isEmpty { return nil }
        let mainJS = (pluginDir as NSString).appendingPathComponent("main.js")
        guard FileManager.default.fileExists(atPath: mainJS),
              let src = try? String(contentsOfFile: mainJS, encoding: .utf8) else { return nil }
        guard let re = try? NSRegularExpression(pattern: "data_version\\s*:\\s*(\\d+)"),
              let m = re.firstMatch(in: src, range: NSRange(src.startIndex..., in: src)),
              let r = Range(m.range(at: 1), in: src) else { return nil }
        return Int(src[r])
    }
}

/// python 의 `lib/gen/i18n.py` 중 헬퍼가 쓰는 부분.
///
/// ⚠️ 전체를 옮기지 않는다. **여기서 실제로 쓰는 키만** 둔다 — 안 쓰는
///    문구를 옮기면 두 정본이 생기고 곧 갈라진다. 필요해지면 그때 더한다.
enum I18n {
    static let lang: String = {
        let v = ProcessInfo.processInfo.environment["DEVTRAIL_LANG"] ?? "ko"
        return (v == "ko" || v == "en") ? v : "ko"
    }()

    private static let table: [String: [String: String]] = [
        "hk.assigned": [
            "ko": "배정 {a}개 · 재배정 {r}개 · 건너뜀 {s}개",
            "en": "{a} assigned · {r} remapped · {s} skipped",
        ],
        "hk.remapped": [
            "ko": "  재배정 {old} → {new}",
            "en": "  remapped {old} → {new}",
        ],

        // hubs (L1 대시보드 · 일일 체크인)
        "l1.checkin": [
            "ko": "일일 체크인",
            "en": "Daily check-in",
        ],
        "col.days": [
            "ko": "체류일",
            "en": "Days",
        ],
        "col.log": [
            "ko": "일지",
            "en": "Log",
        ],
        "col.stage": [
            "ko": "단계",
            "en": "Stage",
        ],
        "col.status": [
            "ko": "상태",
            "en": "Status",
        ],
        "l1.approx_size": [
            "ko": "> ℹ️ `status` 커버리지가 {pct}% 라 분량으로 근사합니다.",
            "en": "> ℹ️ `status` coverage is {pct}%, so note length is used instead.",
        ],
        "l1.dashboard": [
            "ko": "대시보드",
            "en": "Dashboard",
        ],
        "l1.entry": [
            "ko": "> 볼트의 진입점입니다. 왼쪽 사이드바에서 북마크해두면 편합니다.",
            "en": "> The entry point to your vault. Bookmark it in the left sidebar.",
        ],
        "l1.evening_1": [
            "ko": "1. 개발일지의 '오늘 배운 것' 을 한 줄 채운다",
            "en": "1. Fill in one line under \"what I learned today\"",
        ],
        "l1.evening_2": [
            "ko": "2. 아래 '오래 묵은 것' 을 한 번 훑는다",
            "en": "2. Skim \"gone stale\" below",
        ],
        "l1.evening_3": [
            "ko": "3. 미완료를 내일로 옮긴다",
            "en": "3. Move anything unfinished to tomorrow",
        ],
        "l1.friday": [
            "ko": "주간리뷰를 만들고 아래 헬스체크를 본다.",
            "en": "Create the weekly review and run the health check below.",
        ],
        "l1.h_areas": [
            "ko": "🧭 영역별 개발메모",
            "en": "🧭 Notes by area",
        ],
        "l1.h_created": [
            "ko": "🟢 오늘 만든 노트",
            "en": "🟢 Created today",
        ],
        "l1.h_daily": [
            "ko": "☀️ 일일 루틴",
            "en": "☀️ Daily routine",
        ],
        "l1.h_evening": [
            "ko": "🌇 퇴근 전 (3분)",
            "en": "🌇 Before logging off (3 min)",
        ],
        "l1.h_friday": [
            "ko": "📅 금요일 (10분)",
            "en": "📅 Friday (10 min)",
        ],
        "l1.h_inbox_age": [
            "ko": "Inbox 적체 (오래된 순)",
            "en": "Inbox backlog (oldest first)",
        ],
        "l1.h_maint": [
            "ko": "🧹 볼트 유지보수",
            "en": "🧹 Vault maintenance",
        ],
        "l1.h_morning": [
            "ko": "🕗 아침 (2분)",
            "en": "🕗 Morning (2 min)",
        ],
        "l1.h_orphans": [
            "ko": "연결이 없는 노트",
            "en": "Notes with no links",
        ],
        "l1.h_projects": [
            "ko": "🏗️ 진행 중인 프로젝트",
            "en": "🏗️ Active projects",
        ],
        "l1.h_recent_7": [
            "ko": "최근 7일에 만든 노트",
            "en": "Created in the last 7 days",
        ],
        "l1.h_recent_log": [
            "ko": "최근 개발일지",
            "en": "Recent devlogs",
        ],
        "l1.h_stale": [
            "ko": "🔴 오래 묵은 것",
            "en": "🔴 Gone stale",
        ],
        "l1.h_week": [
            "ko": "🟡 이번 주 개발일지 (공백일 확인)",
            "en": "🟡 This week's devlogs (spot the gaps)",
        ],
        "l1.h_working": [
            "ko": "💻 작업 중 (수시)",
            "en": "💻 While working (anytime)",
        ],
        "l1.morning_1": [
            "ko": "1. `⌘⇧D` — 개발일지를 만들고 오늘 할 것 Top 3 을 적는다",
            "en": "1. `⌘⇧D` — create today's devlog and write your top 3",
        ],
        "l1.morning_2": [
            "ko": "2. `⌘⇧G` — GitHub 활동을 일지에 넣는다",
            "en": "2. `⌘⇧G` — pull GitHub activity into the devlog",
        ],
        "l1.routine_intro": [
            "ko": "> 하루를 여닫는 순서입니다. 5분이면 됩니다.",
            "en": "> How to open and close the day. Five minutes.",
        ],
        "l1.row_idea": [
            "ko": "아이디어 캡처",
            "en": "Capture an idea",
        ],
        "l1.row_note": [
            "ko": "배운 것을 메모",
            "en": "Note something you learned",
        ],
        "l1.row_save": [
            "ko": "자료 저장",
            "en": "Save a reference",
        ],
        "l1.row_stuck": [
            "ko": "막힌 것을 기록",
            "en": "Log something you got stuck on",
        ],
        "l1.row_stuck_v": [
            "ko": "트러블슈팅 폴더에서 새 노트",
            "en": "New note in the Troubleshooting folder",
        ],
        "l1.tbl_key": [
            "ko": "단축키",
            "en": "Hotkey",
        ],
        "l1.tbl_what": [
            "ko": "무엇",
            "en": "What",
        ],
        "l1.today": [
            "ko": "오늘",
            "en": "Today",
        ],
        "nav.devlog": [
            "ko": "📝 개발일지",
            "en": "📝 Devlog",
        ],
        "nav.devnote": [
            "ko": "📂 개발메모",
            "en": "📂 Notes",
        ],
        "nav.idea": [
            "ko": "💡 아이디어",
            "en": "💡 Ideas",
        ],
        "nav.inbox": [
            "ko": "📥 Inbox",
            "en": "📥 Inbox",
        ],
        "nav.library": [
            "ko": "📚 라이브러리",
            "en": "📚 Libraries",
        ],
        "nav.projects": [
            "ko": "🏗️ 프로젝트",
            "en": "🏗️ Projects",
        ],
        "nav.trouble": [
            "ko": "🔧 트러블슈팅",
            "en": "🔧 Troubleshooting",
        ],
        "nav.zettel": [
            "ko": "🗂 카드노트",
            "en": "🗂 Zettel",
        ],

        // hub (L3 폴더 허브)
        "hub.recent": [
            "ko": "최근",
            "en": "Recent",
        ],
        "col.note": [
            "ko": "노트",
            "en": "Note",
        ],
        "col.modified": [
            "ko": "수정",
            "en": "Modified",
        ],
        "hub.due": [
            "ko": "재방문할 때가 됐다",
            "en": "Due for review",
        ],
        "hub.mixed_review": [
            "ko": "> ℹ️ `review_at` 커버리지가 {pct}% 입니다 — ",
            "en": "> ℹ️ `review_at` coverage is {pct}% — ",
        ],
        "hub.mixed_note": [
            "ko": "값이 있는 노트는 예정일로, 없는 노트는 마지막 수정일로 봅니다.\n\n",
            "en": "Notes with a value use it; the rest fall back to last modified.\n\n",
        ],
        "hub.low_review": [
            "ko": "> ℹ️ 이 볼트는 `review_at` 을 거의 쓰지 않아 (커버리지 {pct}%) ",
            "en": "> ℹ️ This vault barely uses `review_at` (coverage {pct}%), so it is ",
        ],
        "hub.approx_mtime": [
            "ko": "**마지막 수정일로 근사**합니다.\n",
            "en": "approximated by **last modified date**.\n",
        ],
        "hub.align_hint": [
            "ko": "> 정확하게 하려면: `devtrail align --field review_at`\n\n",
            "en": "> For exact results: `devtrail align --field review_at`\n\n",
        ],
        "hub.unfinished": [
            "ko": "미완성",
            "en": "Unfinished",
        ],
        "hub.mixed_status": [
            "ko": "> ℹ️ `status` 커버리지가 {pct}% 입니다 — 분량이 적은 노트도 함께 봅니다.\n\n",
            "en": "> ℹ️ `status` coverage is {pct}% — short notes are included too.\n\n",
        ],
        "hub.low_status": [
            "ko": "> ℹ️ 이 볼트는 `status` 를 거의 쓰지 않아 (커버리지 {pct}%) ",
            "en": "> ℹ️ This vault barely uses `status` (coverage {pct}%), so it is ",
        ],
        "hub.approx_short": [
            "ko": "**분량이 적은 노트로 근사**합니다.\n\n",
            "en": "approximated by **short notes**.\n\n",
        ],
        "col.size": [
            "ko": "크기",
            "en": "Size",
        ],
        "hub.orphans": [
            "ko": "연결이 없다",
            "en": "No links",
        ],
        "col.folder": [
            "ko": "폴더",
            "en": "Folder",
        ],
        "hub.scope": [
            "ko": "> 이 폴더만 봅니다. DevTrail 이 만들었고 `devtrail augment --refresh-hubs` 로 갱신됩니다.",
            "en": "> This folder only. Created by DevTrail; refresh with `devtrail augment --refresh-hubs`.",
        ],
        "err.need_from": [
            "ko": "DT_HUB_FROM 이 필요합니다",
            "en": "DT_HUB_FROM is required",
        ],
    ]

    static func t(_ key: String, _ vars: [String: String] = [:]) -> String {
        guard let e = table[key] else { return key }
        var s = e[lang] ?? e["ko"] ?? key
        for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}
