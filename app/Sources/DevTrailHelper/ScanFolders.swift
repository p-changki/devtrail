import Foundation

extension VaultScan {

    /// 역할 후보에서 빼는 경로.
    ///
    /// ⚠️ 자동 수집물·백업은 원본 폴더를 흉내내서, 그대로 두면 진짜 역할
    ///    폴더를 밀어낸다 — 실제로 레포docs 하위 30여 개가 devlog 후보
    ///    상위를 점령했다.
    static func isNoisy(_ relDir: String) -> Bool {
        let s = ("/" + relDir).lowercased()
        for w in ["archive", "아카이브", "backup", "백업", "_staging", "/_",
                  "template", "템플릿"] where s.contains(w) {
            return true
        }
        return false
    }

    /// `\d{4}-\d{2}-\d{2}` 가 들어 있는가.
    static func hasDate(_ s: String) -> Bool {
        let a = Array(s)
        var i = 0
        while i + 10 <= a.count {
            if a[i].isNumber, a[i+1].isNumber, a[i+2].isNumber, a[i+3].isNumber,
               a[i+4] == "-", a[i+5].isNumber, a[i+6].isNumber,
               a[i+7] == "-", a[i+8].isNumber, a[i+9].isNumber { return true }
            i += 1
        }
        return false
    }

    /// `\d{4}-?W\d{2}` (대소문자 무시)가 들어 있는가.
    static func hasWeek(_ s: String) -> Bool {
        let a = Array(s.uppercased())
        var i = 0
        while i < a.count {
            guard i + 4 < a.count,
                  a[i].isNumber, a[i+1].isNumber, a[i+2].isNumber, a[i+3].isNumber else {
                i += 1; continue
            }
            var j = i + 4
            if j < a.count, a[j] == "-" { j += 1 }
            if j + 2 < a.count, a[j] == "W", a[j+1].isNumber, a[j+2].isNumber { return true }
            i += 1
        }
        return false
    }

    struct FolderInfo {
        let path: String
        let notes: Int
        let subfolders: Int
        let depth: Int
        let datedRatio: Double
        let lastModified: Int
        var roles: [(String, Double)]
    }

    /// 폴더별 신호를 재고 역할 후보를 점수화한다.
    static func analyseFolders(vault: String, filesByDir: [(String, [String])],
                               now: Int) -> [FolderInfo] {
        var out: [FolderInfo] = []
        // python: `sorted(files_by_dir.items())` — 키 문자열 순
        let sorted = Py.stableSorted(filesByDir) { Py.less($0.0, $1.0) }

        for (relDir, entries) in sorted where !entries.isEmpty {
            let names = entries.map { String(($0 as NSString).lastPathComponent.dropLast(3)) }
            let n = names.count
            let dated = names.filter { hasDate($0) }.count
            let weekly = names.filter { hasWeek($0) }.count

            var mtimes: [Double] = []
            for p in entries {
                if let at = try? FileManager.default.attributesOfItem(atPath: p),
                   let d = at[.modificationDate] as? Date {
                    mtimes.append(d.timeIntervalSince1970)
                }
            }
            let fullDir = relDir == "." ? vault : (vault as NSString).appendingPathComponent(relDir)
            let sub = countSubdirs(fullDir)

            let last = mtimes.isEmpty ? 0 : Int(mtimes.max()!)
            let depth = relDir == "." ? 0 : relDir.filter { $0 == "/" }.count + 1
            let noisy = isNoisy(relDir)

            // ⚠️ 바닥을 둔다. min(n/30,1) 만 쓰면 노트 8개짜리 폴더가 0.27 이
            //    되어 0.3 임계값에서 잘린다 — 이제 막 쓰기 시작한 사람의 일지
            //    폴더가 통째로 안 잡힌다.
            let scale = max(min(Double(n) / 30.0, 1.0), 0.45)
            let recent = (now != 0 && last != 0 && (now - last) < recentDays * 86400) ? 1.0 : 0.55

            var roles: [(String, Double)] = []
            let eligible = depth <= maxRoleDepth && !noisy

            if eligible, n >= 3 {
                if Double(dated) / Double(n) >= 0.6 {
                    roles.append(("devlog",
                                  round2(Double(dated) / Double(n) * scale * recent)))
                }
                if Double(weekly) / Double(n) >= 0.5 {
                    roles.append(("weekly",
                                  round2(Double(weekly) / Double(n) * scale * recent)))
                }
            }

            // 프로젝트 컨테이너는 반대다 — 직속 노트가 적은 게 정상이다.
            // n >= 3 안에 묶어뒀다가 README 하나뿐인 진짜 프로젝트 폴더를 놓쳤다.
            if eligible, sub >= 2, n <= sub {
                let marked = countMarkedChildren(fullDir)
                if marked >= 2 {
                    roles.append(("projects", round2(min(Double(marked) / 3.0, 1.0) * recent)))
                }
            }

            out.append(FolderInfo(
                path: relDir, notes: n, subfolders: sub, depth: depth,
                datedRatio: n > 0 ? round2(Double(dated) / Double(n)) : 0,
                lastModified: last, roles: roles))
        }

        // 역할별 상위 2개만 남긴다 — 사용자가 고를 수 있는 분량이어야 한다.
        var best: [String: [(Double, String)]] = [:]
        var roleOrder: [String] = []
        for f in out {
            for (role, sc) in f.roles {
                if best[role] == nil { roleOrder.append(role) }
                best[role, default: []].append((sc, f.path))
            }
        }
        var keep: [String: Set<String>] = [:]
        for role in roleOrder {
            // python: `sorted(v, reverse=True)[:2]` — 튜플 (점수, 경로) 내림차순
            let ranked = best[role]!.sorted { a, b in
                if a.0 != b.0 { return a.0 > b.0 }
                return Py.less(b.1, a.1)          // reverse=True 라 경로도 내림차순
            }
            keep[role] = Set(ranked.prefix(2).filter { $0.0 >= 0.3 }.map { $0.1 })
        }
        for i in out.indices {
            out[i].roles = out[i].roles.filter { role, sc in
                sc >= 0.3 && (keep[role]?.contains(out[i].path) ?? false)
            }
        }
        return out
    }

    private static func countSubdirs(_ dir: String) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return 0
        }
        var n = 0
        for name in names where !skipDirs.contains(name) && !name.hasPrefix(".") {
            var isDir: ObjCBool = false
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                n += 1
            }
        }
        return n
    }

    /// docs/ 폴더나 README.md 를 가진 하위 폴더의 수.
    private static func countMarkedChildren(_ dir: String) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
            return 0
        }
        let fm = FileManager.default
        var marked = 0
        for name in names where !name.hasPrefix(".") {
            let p = (dir as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue else { continue }
            var d: ObjCBool = false
            let docs = (p as NSString).appendingPathComponent("docs")
            let readme = (p as NSString).appendingPathComponent("README.md")
            if (fm.fileExists(atPath: docs, isDirectory: &d) && d.boolValue)
                || fm.fileExists(atPath: readme) {
                marked += 1
            }
        }
        return marked
    }

    /// python: `round(x, 2)` — 은행가 반올림 + 정확한 십진 변환.
    /// `(x * 100).rounded() / 100` 은 틀린다 (ADR 0006, hub 이관에서 확인).
    static func round2(_ x: Double) -> Double {
        Double(String(format: "%.2f", x)) ?? 0
    }

    /// python: `round(x, 1)`
    static func round1(_ x: Double) -> Double {
        Double(String(format: "%.1f", x)) ?? 0
    }
}
