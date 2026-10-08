import Foundation

public struct Crumb: Equatable, Identifiable, Sendable {
    public let name: String
    public let url: URL
    public var id: URL { url }
}

public enum AddressPath {
    /// Turns typed or pasted text into an existing folder, or nil.
    public static func resolve(_ text: String, from base: URL) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return nil }
        let expanded = (s as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url.standardizedFileURL
    }

    /// Root first, current folder last.
    public static func breadcrumbs(_ url: URL) -> [Crumb] {
        var out: [Crumb] = []
        var cur = url.standardizedFileURL
        while true {
            let isRoot = cur.path == "/"
            let name = isRoot
                ? ((try? cur.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "/")
                : cur.lastPathComponent
            out.append(Crumb(name: name, url: cur))
            if isRoot { break }
            cur = cur.deletingLastPathComponent()
        }
        return out.reversed()
    }
}
