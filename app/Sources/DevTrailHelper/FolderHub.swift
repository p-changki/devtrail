import Foundation

/// `lib/gen/hub.py` 의 Swift 판 — L3 폴더 허브 생성기.
///
/// ⚠️ 핵심은 **쿼리를 볼트 상태에 맞춰 고른다**는 것이다.
///
///      값 커버리지 ≥ 50%   정식   frontmatter 기반. 정확하다.
///                10~50%   병용   frontmatter 우선, 없으면 파일시스템으로 보완
///                 < 10%   폴백   파일시스템 메타만. 근사치라고 밝힌다.
///
///    커버리지를 무시하고 정식 쿼리를 박으면 Dataview 가 필드 없는 노트를
///    **조용히 제외**해 빈 결과가 나온다. 사용자는 그걸 "밀린 게 없다" 로
///    읽고 방치한다 — 원본 볼트에서 카드노트 12개 · 월간리뷰 0개가 그렇게
///    만들어졌다.
///
/// ⚠️ 이것은 재작성이 아니라 **이관**이다. 목표는 같은 출력이다.
enum FolderHub {

    static let staleDays = 90
    static let thinBytes = 500

    enum Tier { case full, mixed, fallback }

    static func tier(_ pct: Double) -> Tier {
        if pct >= 50 { return .full }
        if pct >= 10 { return .mixed }
        return .fallback
    }

    static func run(_ args: [String]) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let src = env["DT_HUB_FROM"] ?? ""
        let title = env["DT_HUB_TITLE"] ?? I18n.t("col.folder")
        let key = env["DT_HUB_KEY"] ?? ""
        let date = env["DT_HUB_DATE"] ?? ""
        if src.isEmpty {
            FileHandle.standardError.write(Data((I18n.t("err.need_from") + "\n").utf8))
            return 2
        }

        let covReview = pct(env["DT_HUB_COV_REVIEW"])
        let covStatus = pct(env["DT_HUB_COV_STATUS"])

        let parts: [String] = [
            "---",
            "tags:",
            "  - type/moc",
            "type: moc",
            "scope: folder",           // 폴더 허브 · 주제 MOC 를 이걸로 구분한다
            "devtrail_key: \(key)",    // devtrail path 로 되찾을 수 있게
            "created: \(date)",
            "updated: \(date)",
            "---",
            "",
            "# \(title)",
            "",
            I18n.t("hub.scope"),
            "",
            blockRecent(src),
            "",
            blockStale(src, covReview),
            "",
            blockUnfinished(src, covStatus),
            "",
            blockOrphan(src),
            "",
        ]
        print(parts.joined(separator: "\n"))
        return 0
    }

    /// python: `round(float(env.get(name, "0")), 1)`, 실패하면 0.0
    ///
    /// ⚠️ `(v * 10).rounded() / 10` 로 쓰면 **틀린다.** 두 가지가 어긋난다:
    ///
    ///    1. Swift 의 `.rounded()` 는 half-away-from-zero, python 의 `round`
    ///       는 **half-to-even**(은행가 반올림)이다.
    ///       `round(0.25, 1)` → python 0.2 · Swift 0.3
    ///    2. `× 10` 이 부동소수 오차를 만든다. `33.35 * 10` 은
    ///       `333.49999999999994` 라 333 으로 내려간다 — python 은 실제
    ///       double 값(33.3500000000000014)을 보고 33.4 를 낸다.
    ///
    ///    실측(2026-08-24): 시험한 5개 값 중 **4개가 달랐다.**
    ///    `%.1f` 는 C 의 정확한 십진 변환 + half-to-even 이라 8/8 일치한다.
    static func pct(_ raw: String?) -> Double {
        guard let raw, let v = Double(raw) else { return 0.0 }
        return Double(String(format: "%.1f", v)) ?? 0.0
    }

    /// ⚠️ python 의 f-string 은 정수 같은 float 를 `33.3` / `80.0` 처럼
    ///    repr 로 찍는다. `%g` 를 쓰면 `80` 이 되어 다른 문자열이 된다.
    static func fmt(_ d: Double) -> String { JSON.pythonNumber(d) }

    // ── 블록 ────────────────────────────────────────────────────────────────

    static func blockRecent(_ src: String) -> String {
        """
        ## \(I18n.t("hub.recent"))

        ```dataview
        TABLE WITHOUT ID
          file.link AS "\(I18n.t("col.note"))",
          dateformat(file.mtime, "yyyy-MM-dd") AS "\(I18n.t("col.modified"))"
        FROM "\(src)"
        WHERE file.name != "_index"
        SORT file.mtime DESC
        LIMIT 15
        ```
        """
    }

    static func blockStale(_ src: String, _ p: Double) -> String {
        let note: String
        let whereClause: String
        let order: String
        switch tier(p) {
        case .full:
            note = ""
            whereClause = "review_at AND review_at <= date(today)"
            order = "review_at ASC"
        case .mixed:
            note = I18n.t("hub.mixed_review", ["pct": fmt(p)]) + I18n.t("hub.mixed_note")
            whereClause = "(review_at AND review_at <= date(today))\n"
                + "  OR (!review_at AND file.mtime <= date(today) - dur(\(staleDays) days))"
            order = "file.mtime ASC"
        case .fallback:
            note = I18n.t("hub.low_review", ["pct": fmt(p)])
                + I18n.t("hub.approx_mtime") + I18n.t("hub.align_hint")
            whereClause = "file.mtime <= date(today) - dur(\(staleDays) days)"
            order = "file.mtime ASC"
        }
        return """
        ## \(I18n.t("hub.due"))

        \(note)```dataview
        LIST
        FROM "\(src)"
        WHERE file.name != "_index"
          AND (\(whereClause))
        SORT \(order)
        LIMIT 15
        ```
        """
    }

    static func blockUnfinished(_ src: String, _ p: Double) -> String {
        let note: String
        let whereClause: String
        switch tier(p) {
        case .full:
            note = ""
            whereClause = "status = \"draft\""
        case .mixed:
            note = I18n.t("hub.mixed_status", ["pct": fmt(p)])
            whereClause = "status = \"draft\" OR (!status AND file.size < \(thinBytes))"
        case .fallback:
            note = I18n.t("hub.low_status", ["pct": fmt(p)]) + I18n.t("hub.approx_short")
            whereClause = "file.size < \(thinBytes)"
        }
        return """
        ## \(I18n.t("hub.unfinished"))

        \(note)```dataview
        TABLE WITHOUT ID file.link AS "\(I18n.t("col.note"))", file.size AS "\(I18n.t("col.size"))"
        FROM "\(src)"
        WHERE file.name != "_index" AND (\(whereClause))
        SORT file.size ASC
        LIMIT 10
        ```
        """
    }

    static func blockOrphan(_ src: String) -> String {
        """
        ## \(I18n.t("hub.orphans"))

        ```dataview
        LIST
        FROM "\(src)"
        WHERE file.name != "_index"
          AND length(file.outlinks) = 0 AND length(file.inlinks) = 0
        SORT file.ctime DESC
        LIMIT 10
        ```
        """
    }
}
