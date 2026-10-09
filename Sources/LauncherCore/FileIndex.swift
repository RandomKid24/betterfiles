import Foundation

/// Our own name index of the home folder, so search isn't limited to Spotlight's first 300 hits.
/// Built in the background; names are folded once so a query is a plain substring scan.
public final class FileIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []   // folded (lowercase, no accents)
    private var paths: [String] = []
    private var builtAt: Date?

    /// Folders that are huge and never what you are searching for.
    static let skipped: Set<String> = ["Library", "node_modules", "Pods", "DerivedData", ".build", "build", "target", "venv", ".venv"]

    public init() {}

    public func isStale(after seconds: TimeInterval = 600) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return builtAt.map { Date().timeIntervalSince($0) > seconds } ?? true
    }

    // ponytail: full rescan, capped so memory stays around 100 MB. Use FSEvents for incremental updates if rescans get slow.
    public func build(root: String, cap: Int = 300_000) {
        var n: [String] = [], p: [String] = []
        let url = URL(fileURLWithPath: root)
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let item as URL in e {
                let name = item.lastPathComponent
                if Self.skipped.contains(name), (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    e.skipDescendants()
                    continue
                }
                n.append(Ranker.fold(name))
                p.append(item.path)
                if n.count >= cap { break }
            }
        }
        lock.lock()
        names = n; paths = p; builtAt = Date()
        lock.unlock()
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
