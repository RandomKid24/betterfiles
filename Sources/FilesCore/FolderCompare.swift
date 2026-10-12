import Foundation

/// Compares two folders file by file (recursively) and copies what's missing. It never overwrites or deletes.
public enum FolderCompare {
    public struct Result {
        public var onlyLeft: [String] = []    // paths relative to the folder, sorted
        public var onlyRight: [String] = []
        public var newerLeft: [String] = []   // on both sides, the left copy was changed more recently
        public var newerRight: [String] = []
        public var conflicts: [String] = []   // same modified time but a different size: nobody can tell which is right
        public var sameCount = 0

        /// Everything that exists on both sides but differs.
        public var different: [String] { (newerLeft + newerRight + conflicts).sorted() }
    }

    /// A file that was replaced by a newer version. The old one waits in the Trash at `trashed`, so this can be undone.
    public struct Replacement {
        public let dest: URL
        public let trashed: URL?
        public let error: Error?
        public var succeeded: Bool { error == nil }
    }

    private struct Info { let size: Int64; let modified: Date }

    public static func compare(_ left: URL, _ right: URL) -> Result {
        let l = files(in: left), r = files(in: right)
        var out = Result()
        for (path, a) in l {
            guard let b = r[path] else { out.onlyLeft.append(path); continue }
            let gap = a.modified.timeIntervalSince(b.modified)
            if gap > 2 { out.newerLeft.append(path) }
            else if gap < -2 { out.newerRight.append(path) }
            else if a.size != b.size { out.conflicts.append(path) }
            else { out.sameCount += 1 }
        }
        out.onlyRight = r.keys.filter { l[$0] == nil }
        out.onlyLeft.sort(); out.onlyRight.sort(); out.newerLeft.sort(); out.newerRight.sort(); out.conflicts.sort()
        return out
    }

    private static func files(in root: URL) -> [String: Info] {
        var out: [String: Info] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return out }
        let base = root.standardizedFileURL.path
        for case let url as URL in e {
            guard url.lastPathComponent != ".DS_Store",
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            out[rel] = Info(size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate ?? .distantPast)
        }
        return out
    }

    /// Copies each relative path from one folder to the other, creating sub-folders as needed. Existing files are left alone.
    public static func copyMissing(_ paths: [String], from: URL, to: URL) -> [OpOutcome] {
        paths.map { rel in
            let src = from.appendingPathComponent(rel), dest = to.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: dest.path) { return OpOutcome(source: src, destination: nil, error: FileOpError.exists) }
            do {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: src, to: dest)
                return OpOutcome(source: src, destination: dest, error: nil)
            } catch {
                return OpOutcome(source: src, destination: nil, error: error)
            }
        }
    }

    /// Replaces the file at each relative path in `to` with the one from `from`. The old file goes to the Trash first
    /// (nothing is ever deleted), and if the copy fails the old file is put back.
    public static func replaceOlder(_ paths: [String], from: URL, to: URL) -> [Replacement] {
        paths.map { rel in
            let src = from.appendingPathComponent(rel), dest = to.appendingPathComponent(rel)
            var trashed: NSURL?
            do {
                try FileManager.default.trashItem(at: dest, resultingItemURL: &trashed)
                try FileManager.default.copyItem(at: src, to: dest)
                return Replacement(dest: dest, trashed: trashed as URL?, error: nil)
            } catch {
                if let t = trashed { try? FileManager.default.moveItem(at: t as URL, to: dest) }   // put the old one back
                return Replacement(dest: dest, trashed: nil, error: error)
            }
        }
    }
}
