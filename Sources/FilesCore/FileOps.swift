import Foundation

public enum FileOpError: LocalizedError, Equatable {
    case intoItself, invalidName, exists, toolFailed

    public var errorDescription: String? {
        switch self {
        case .intoItself: return "a folder can't be moved or copied into itself"
        case .invalidName: return "that isn't a valid name"
        case .exists: return "an item with that name already exists"
        case .toolFailed: return "the archive tool failed"
        }
    }
}

public struct OpOutcome {
    public let source: URL
    public let destination: URL?
    public let error: Error?
    public var succeeded: Bool { error == nil }
}

public enum FileOps {
    enum Style { case numbered, copy }

    /// Moves each item into `folder`. Never overwrites. One failure does not stop the others.
    public static func move(_ urls: [URL], to folder: URL) -> [OpOutcome] {
        urls.map { src in
            if isInside(folder, of: src) { return fail(src, .intoItself) }
            if same(src.deletingLastPathComponent(), folder) { return OpOutcome(source: src, destination: src, error: nil) }
            let dest = unique(src.lastPathComponent, isFolder: isDir(src), in: folder, style: .numbered)
            return attempt(src, dest) { try FileManager.default.moveItem(at: src, to: dest) }
        }
    }

    public static func copy(_ urls: [URL], to folder: URL) -> [OpOutcome] {
        urls.map { src in
            if isInside(folder, of: src) { return fail(src, .intoItself) }
            let dest = unique(src.lastPathComponent, isFolder: isDir(src), in: folder, style: .copy)
            return attempt(src, dest) { try FileManager.default.copyItem(at: src, to: dest) }
        }
    }

    public static func rename(_ url: URL, to newName: String) -> OpOutcome {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return fail(url, .invalidName) }
        if name == url.lastPathComponent { return OpOutcome(source: url, destination: url, error: nil) }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        // A case-only change (a.txt -> A.txt) "exists" on a case-insensitive disk because it is the same file.
        let caseOnly = dest.path.caseInsensitiveCompare(url.path) == .orderedSame
        if FileManager.default.fileExists(atPath: dest.path), !caseOnly { return fail(url, .exists) }
        return attempt(url, dest) { try FileManager.default.moveItem(at: url, to: dest) }
    }

    /// Finder-style alias ("name alias") next to the original.
    public static func makeAlias(of url: URL) -> OpOutcome {
        let dest = unique(url.lastPathComponent + " alias", isFolder: true, in: url.deletingLastPathComponent(), style: .numbered)
        return attempt(url, dest) {
            let data = try url.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(data, to: dest)
        }
    }

    /// Creates "New Folder" (or "New Folder 2", ...) in `folder`.
    public static func newFolder(in folder: URL) -> OpOutcome {
        let dest = unique("New Folder", isFolder: true, in: folder, style: .numbered)
        return attempt(folder, dest) { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false) }
    }

    /// Moves to the Trash. There is deliberately no permanent delete.
    public static func trash(_ urls: [URL]) -> [OpOutcome] {
        urls.map { src in
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: src, resultingItemURL: &result)
                return OpOutcome(source: src, destination: result as URL?, error: nil)
            } catch {
                return OpOutcome(source: src, destination: nil, error: error)
            }
        }
    }

    // MARK: helpers

    private static func attempt(_ src: URL, _ dest: URL, _ work: () throws -> Void) -> OpOutcome {
        do { try work(); return OpOutcome(source: src, destination: dest, error: nil) }
        catch { return OpOutcome(source: src, destination: nil, error: error) }
    }

    private static func fail(_ src: URL, _ e: FileOpError) -> OpOutcome {
        OpOutcome(source: src, destination: nil, error: e)
    }

    private static func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private static func same(_ a: URL, _ b: URL) -> Bool { resolved(a) == resolved(b) }

    private static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    /// True when `folder` is `src` itself or lies inside it (only matters when `src` is a folder).
    private static func isInside(_ folder: URL, of src: URL) -> Bool {
        guard isDir(src) else { return false }
        let f = resolved(folder), s = resolved(src)
        return f == s || f.hasPrefix(s + "/")
    }

    static func unique(_ name: String, isFolder: Bool, in folder: URL, style: Style) -> URL {
        let fm = FileManager.default
        let ns = name as NSString
        let ext = isFolder ? "" : ns.pathExtension
        let base = isFolder ? name : ns.deletingPathExtension
        func make(_ suffix: String) -> String { ext.isEmpty ? base + suffix : base + suffix + "." + ext }

        var candidate = folder.appendingPathComponent(name)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            let suffix = style == .numbered ? " \(n)" : (n == 2 ? " copy" : " copy \(n - 1)")
            candidate = folder.appendingPathComponent(make(suffix))
        }
        return candidate
    }
}
