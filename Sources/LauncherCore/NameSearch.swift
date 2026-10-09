import Foundation

/// File-name search through Spotlight's index (`mdfind -name`), run off the main thread.
/// Covers the whole home folder with no memory of our own; a new search cancels the previous one.
public final class NameSearch: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Process?

    public init() {}

    /// Blocking: call it off the main thread. Returns at most `limit` paths, in Spotlight's order (the caller ranks them).
    public func run(_ query: String, home: String = NSHomeDirectory(), limit: Int = 300) -> [Candidate] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return [] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["-onlyin", home, "-name", q]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice

        lock.lock()
        current?.terminate()   // a newer keystroke makes the old search pointless
        current = p
        lock.unlock()
        do { try p.run() } catch { return [] }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }

        // Read in chunks and stop as soon as there are enough lines: a two-letter query can match thousands of files.
        var buffer = Data()
        var newlines = 0
        let handle = pipe.fileHandleForReading
        while newlines < limit * 3 {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            newlines += chunk.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
        }
        if p.isRunning { p.terminate() }
        p.waitUntilExit()

        return Self.candidates(from: String(decoding: buffer, as: UTF8.self), home: home, limit: limit)
    }

    /// Drops hidden files, ~/Library and dependency folders, and builds candidates.
    static func candidates(from output: String, home: String, limit: Int) -> [Candidate] {
        output.split(separator: "\n").lazy.map(String.init)
            .filter { !$0.contains("/.") && !$0.hasPrefix(home + "/Library/") && !$0.contains("/node_modules/") }
            .prefix(limit)
            .map { Candidate(name: ($0 as NSString).lastPathComponent, path: $0, isApp: $0.hasSuffix(".app")) }
    }
}
