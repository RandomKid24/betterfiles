import Foundation

public struct UsageRecord: Codable, Equatable, Sendable {
    public var count: Int
    public var last: Date

    public init(count: Int, last: Date) {
        self.count = count
        self.last = last
    }
}

public final class Usage {
    private var records: [String: UsageRecord] = [:]
    private let url: URL

    public init(url: URL) {
        self.url = url
        guard let data = try? Data(contentsOf: url) else { return }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        records = (try? d.decode([String: UsageRecord].self, from: data)) ?? [:]
    }

    public func get(_ path: String) -> UsageRecord? { records[path] }

    public func record(path: String, now: Date = Date()) {
        var r = records[path] ?? UsageRecord(count: 0, last: now)
        r.count += 1
        r.last = now
        records[path] = r
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        if let data = try? e.encode(records) { try? data.write(to: url, options: .atomic) }
    }
}
