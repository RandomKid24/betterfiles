import Foundation

/// Compares two folders file by file (recursively) and copies what's missing. It never overwrites or deletes.
public enum FolderCompare {
    public struct Result {
        public var onlyLeft: [String] = []    // paths relative to the folder, sorted
        public var onlyRight: [String] = []
        public var different: [String] = []   // on both sides, but size or modified time differs
        public var sameCount = 0
    }

    private struct Info { let size: Int64; let modified: Date }

    public static func compare(_ left: URL, _ right: URL) -> Result {
        let l = files(in: left), r = files(in: right)
        var out = Result()
        for (path, a) in l {
            guard let b = r[path] else { out.onlyLeft.append(path); continue }
            if a.size != b.size || abs(a.modified.timeIntervalSince(b.modified)) > 2 { out.different.append(path) } else { out.sameCount += 1 }
        }
        out.onlyRight = r.keys.filter { l[$0] == nil }
        out.onlyLeft.sort(); out.onlyRight.sort(); out.different.sort()
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
}
