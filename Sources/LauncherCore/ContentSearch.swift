import Foundation

/// Searches inside files (their text) using Spotlight's content index: type "? invoice 2025".
public enum ContentSearch {
    /// An mdfind predicate: every word must appear somewhere in the file (Spotlight can't match exact phrases),
    /// and the last word may be unfinished ("invo" finds "invoice"). Nil when there is nothing to search for.
    /// Quotes, backslashes and wildcards are removed from the input because it is spliced into the query string.
    public static func predicate(for query: String) -> String? {
        let cleaned = String(query.filter { !"\"'\\*?".contains($0) })
        let words = cleaned.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let last = words.last, words.joined().count >= 2 else { return nil }
        let clauses = words.dropLast().map { "kMDItemTextContent == \"\($0)\"cd" } + ["kMDItemTextContent == \"\(last)*\"cd"]
        return clauses.joined(separator: " && ")
    }

    /// Blocking: call it off the main thread. Gives up after three seconds.
    public static func run(_ query: String, limit: Int = 25, home: String = NSHomeDirectory()) -> [Candidate] {
        guard let predicate = predicate(for: query) else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", home, predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return lines.lazy
            .filter { !$0.contains("/.") && !$0.hasPrefix(home + "/Library/") && !$0.contains("/node_modules/") }
            .prefix(limit)
            .map { Candidate(name: ($0 as NSString).lastPathComponent, path: $0, isApp: false) }
    }
}
