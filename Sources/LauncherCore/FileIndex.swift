import Foundation

/// Our own name index of the home folder, so search isn't limited to Spotlight's first 300 hits.
/// Built in the background; names are folded once so a query is a plain substring scan.
public final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []   // folded (lowercase, no accents)
    private var paths: [String] = []
    private var builtAt: Date?

    /// Folders that are huge and never what you are searching for.
    static let skipped: Set<String> = ["Library", "node_modules", "Pods", "DerivedData", ".build", "build", "target", "venv", ".venv",
                                          "dist", "vendor", "site-packages", "__pycache__", "bower_components", "Carthage", "Intermediates.noindex"]

    public init() {}

    /// True once a scan has finished and found something, so Spotlight isn't needed as a fallback.
    public var isReady: Bool {
        lock.lock(); defer { lock.unlock() }
        return builtAt != nil && !names.isEmpty
    }

    public func isStale(after seconds: TimeInterval = 1800) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return builtAt.map { Date().timeIntervalSince($0) > seconds } ?? true
    }

    static let protectedFolders: Set<String> = ["Desktop", "Documents", "Downloads"]

    /// Folders people keep their own files in: scanned first, with the most room.
    static let priority = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Developer", "Projects", "Code", "Sites"]

    // ponytail: full rescan, capped so memory stays around 100 MB. Each top-level folder gets its own limit so one huge
    // developer folder can't use up the whole index. Use FSEvents for incremental updates if rescans get slow.
    public func build(root: String, cap: Int = 200_000, perPriority: Int = 60_000, perOther: Int = 25_000) {
        var n: [String] = [], p: [String] = []
        let fm = FileManager.default
        let top = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }
        // Folders macOS may hide until the user allows access come last: scanning them can stall on a permission dialog,
        // and everything before them is already searchable by then.
        let ordered = (Self.priority.filter(top.contains) + top.filter { !Self.priority.contains($0) && !Self.skipped.contains($0) }.sorted())
            .sorted { Self.protectedFolders.contains($0) != Self.protectedFolders.contains($1) ? !Self.protectedFolders.contains($0) : false }
        for name in ordered where n.count < cap {
            let url = URL(fileURLWithPath: root).appendingPathComponent(name)
            n.append(Ranker.fold(name)); p.append(url.path)
            let room = min(Self.priority.contains(name) ? perPriority : perOther, cap - n.count)
            scan(url, room: room, names: &n, paths: &p)
            lock.lock(); names = n; paths = p; lock.unlock()   // searchable as soon as each folder is done
        }
        lock.lock()
        names = n; paths = p; builtAt = Date()
        lock.unlock()
    }

    private func scan(_ dir: URL, room: Int, names n: inout [String], paths p: inout [String]) {
        var added = 0
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return }
        for case let item as URL in e where added < room {
            let name = item.lastPathComponent
            if Self.skipped.contains(name), (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                e.skipDescendants()
                continue
            }
            n.append(Ranker.fold(name)); p.append(item.path)
            added += 1
        }
    }

    /// Prefix matches first, then substring matches, up to `limit`.
    public func search(_ query: String, limit: Int = 300) -> [Candidate] {
        let q = Ranker.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        lock.lock()
        let names = self.names, paths = self.paths
        lock.unlock()
        var hits: [Int] = []
        for i in names.indices where names[i].hasPrefix(q) {
            hits.append(i)
            if hits.count >= limit { break }
        }
        if hits.count < limit {
            let have = Set(hits)
            for i in names.indices where !have.contains(i) && names[i].contains(q) {
                hits.append(i)
                if hits.count >= limit { break }
            }
        }
        return hits.map { i in
            let path = paths[i]
            return Candidate(name: (path as NSString).lastPathComponent, path: path, isApp: path.hasSuffix(".app"))
        }
    }
}
