import Foundation

/// Typing a path ("/", "/Applications", "~/Doc", "/apps/sa") browses folders instead of searching.
/// Case, accents, a few typos and shortcuts like "/apps" are forgiven.
public enum PathQuery {
    static let aliases: [String: String] = [
        "apps": "/Applications", "applications": "/Applications",
        "docs": "~/Documents", "documents": "~/Documents",
        "downloads": "~/Downloads", "dl": "~/Downloads", "desktop": "~/Desktop",
        "pictures": "~/Pictures", "pics": "~/Pictures", "music": "~/Music", "movies": "~/Movies", "home": "~",
    ]

    public static func isPath(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("/") || t == "~" || t.hasPrefix("~/")
    }

    /// The folder being browsed and its (filtered) entries, or nil when `text` isn't a path.
    public static func entries(for text: String, home: String = NSHomeDirectory(), limit: Int = 60) -> (dir: String, items: [Candidate])? {
        guard isPath(text) else { return nil }
        var s = text.trimmingCharacters(in: .whitespaces)
        if s == "~" { s = "~/" }
        if s.hasPrefix("~/") { s = home + s.dropFirst() }
        var parts = s.dropFirst().split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let filter = parts.popLast() ?? ""

        var dir = "/"
        for (i, comp) in parts.enumerated() where !comp.isEmpty {
            if let hit = resolve(comp, in: dir) { dir = join(dir, hit); continue }
            if i == 0, let alias = aliases[comp.lowercased()] { dir = expand(alias, home); continue }
            return (dir, [])
        }

        var found = list(dir, filter: filter, limit: limit)
        // "/apps" means the Applications folder, unless something at the root really starts with "apps".
        let realMatch = names(in: "/").contains { Ranker.fold($0).hasPrefix(Ranker.fold(filter)) }
        if dir == "/", !filter.isEmpty, !realMatch, let alias = aliases[filter.lowercased()] ?? aliases.first(where: { $0.key.hasPrefix(filter.lowercased()) })?.value {
            dir = expand(alias, home)
            found = list(dir, filter: "", limit: limit)
        }
        return (dir, found)
    }

    private static func expand(_ p: String, _ home: String) -> String { p == "~" ? home : p.hasPrefix("~/") ? home + p.dropFirst() : p }
    private static func join(_ dir: String, _ name: String) -> String { dir == "/" ? "/" + name : dir + "/" + name }

    private static func names(in dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }

    /// Finds the real folder name for a typed component: exact, then prefix, then typo-tolerant.
    private static func resolve(_ comp: String, in dir: String) -> String? {
        let f = Ranker.fold(comp)
        let all = names(in: dir)
        func isDir(_ n: String) -> Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: join(dir, n), isDirectory: &d) && d.boolValue }
        let folders = all.filter(isDir)
        return folders.first { Ranker.fold($0) == f }
            ?? folders.first { Ranker.fold($0).hasPrefix(f) }
            ?? folders.filter { fuzzy(f, Ranker.fold($0)) }.min { $0.count < $1.count }
    }

    private static func list(_ dir: String, filter: String, limit: Int) -> [Candidate] {
        let f = Ranker.fold(filter)
        var scored: [(name: String, rank: Int, folder: Bool)] = []
        for name in names(in: dir) {
            if name.hasPrefix(".") && !f.hasPrefix(".") { continue }
            let n = Ranker.fold(name)
            let rank: Int
            if f.isEmpty { rank = 0 }
            else if n.hasPrefix(f) { rank = 0 }
            else if n.contains(f) { rank = 1 }
            else if fuzzy(f, n) { rank = 2 }
            else { continue }
            var d: ObjCBool = false
            let folder = FileManager.default.fileExists(atPath: join(dir, name), isDirectory: &d) && d.boolValue && !name.hasSuffix(".app")
            scored.append((name, rank, folder))
        }
        scored.sort {
            if $0.rank != $1.rank { return $0.rank < $1.rank }
            if $0.folder != $1.folder { return $0.folder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return scored.prefix(limit).map { Candidate(name: $0.name, path: join(dir, $0.name), isApp: $0.name.hasSuffix(".app")) }
    }

    /// Within one typo (two for long words) of the start of `name`; needs 4+ typed characters.
    static func fuzzy(_ typed: String, _ name: String) -> Bool {
        guard typed.count >= 4 else { return false }
        let head = String(name.prefix(typed.count))
        return distance(Array(typed), Array(head)) <= (typed.count >= 8 ? 2 : 1)
    }

    /// Edit distance where swapping two neighbouring letters counts as one mistake.
    static func distance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }
}
