import Foundation

/// Things you type that are really addresses: "192.168.1.1", "localhost:3000", "github.com/foo/bar", "https://…".
public enum WebTarget {
    /// Only domains ending in these count, so file names like "main.swift" or "notes.md" are never mistaken for sites.
    static let tlds: Set<String> = ["com", "org", "net", "io", "dev", "ai", "co", "in", "edu", "gov", "info", "me", "xyz", "tech", "cloud",
                                   "uk", "de", "fr", "ca", "au", "us", "tv", "gg", "so", "to"]

    public static func url(for text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: t) }

        // host[:port][/path]
        let hostPort = String(t.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        let parts = hostPort.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2 else { return nil }
        let host = parts[0].lowercased()
        var port: Int?
        if parts.count == 2 {
            guard let p = Int(parts[1]), (1...65535).contains(p) else { return nil }
            port = p
        }

        let isIP = isIPv4(host)
        let isLocal = host == "localhost"
        let isDomain = host.split(separator: ".").count >= 2 && tlds.contains(host.split(separator: ".").last.map(String.init) ?? "")
            && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
        // "name:3000" with a plain word also counts: a dev server on some host.
        let isPortedWord = port != nil && !host.isEmpty && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
        guard isIP || isLocal || isDomain || isPortedWord else { return nil }

        // Local and private addresses are plain http; public domains default to https.
        let scheme = (isIP || isLocal || port != nil) && !isDomain ? "http" : "https"
        return URL(string: scheme + "://" + t)
    }

    static func isIPv4(_ s: String) -> Bool {
        let p = s.split(separator: ".", omittingEmptySubsequences: false)
        return p.count == 4 && p.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
