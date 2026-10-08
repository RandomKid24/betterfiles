import XCTest
@testable import LauncherCore

final class UsageTests: XCTestCase {
    var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("usage.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testRecordAndRoundTrip() {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let u = Usage(url: url)
        u.record(path: "/a", now: t)
        u.record(path: "/a", now: t.addingTimeInterval(60))
        let reloaded = Usage(url: url)
        XCTAssertEqual(reloaded.get("/a"), UsageRecord(count: 2, last: t.addingTimeInterval(60)))
        XCTAssertNil(reloaded.get("/b"))
    }

    // Review Focus 3
    func testCorruptFileStartsEmpty() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let u = Usage(url: url)
        XCTAssertNil(u.get("/a"))
        u.record(path: "/a")
        XCTAssertEqual(Usage(url: url).get("/a")?.count, 1)
    }
}
