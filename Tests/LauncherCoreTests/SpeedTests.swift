import XCTest
@testable import LauncherCore

final class SpeedTests: XCTestCase {
    // --- SpotlightQuery: user text goes into an MDQuery string, so it must be escaped.
    func testQueryStringIsWordPrefix() {
        XCTAssertEqual(SpotlightQuery.mdString(for: "note"), "kMDItemDisplayName == \"note*\"wcd")
        XCTAssertEqual(SpotlightQuery.mdString(for: "  my notes "), "kMDItemDisplayName == \"my notes*\"wcd")
    }

    func testSingleCharacterOrEmptyDoesNotQueryFiles() {
        XCTAssertNil(SpotlightQuery.mdString(for: "a"))
        XCTAssertNil(SpotlightQuery.mdString(for: "   "))
        XCTAssertNil(SpotlightQuery.mdString(for: ""))
    }

    func testWildcardsAndQuotesAreStripped() {
        XCTAssertNil(SpotlightQuery.mdString(for: "**"))
        XCTAssertNil(SpotlightQuery.mdString(for: "\"\\?"))
        XCTAssertEqual(SpotlightQuery.mdString(for: "no\"te*"), "kMDItemDisplayName == \"note*\"wcd")
        XCTAssertEqual(SpotlightQuery.mdString(for: "a\\b"), "kMDItemDisplayName == \"ab*\"wcd")
    }

    // --- AppIndex: apps are found without asking Spotlight.
    func testAppIndexFindsAppsOneLevelDeep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Safari.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Utilities/Terminal.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Docs"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("readme.txt"))

        let found = AppIndex.scan(dirs: [root.path, "/definitely/not/here"])
        XCTAssertEqual(found.map(\.name).sorted(), ["Safari", "Terminal"])
        XCTAssertTrue(found.allSatisfy(\.isApp))
        XCTAssertTrue(found.first { $0.name == "Safari" }!.path.hasSuffix("/Safari.app"))
    }

    // --- Usage history feeds the candidate list so frequent items always show up.
    func testUsageProducesCandidatesAndDropsMissingFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Foo.app"), withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("report.pdf")
        try Data().write(to: file)

        let u = Usage(url: dir.appendingPathComponent("usage.json"))
        u.record(path: dir.appendingPathComponent("Foo.app").path)
        u.record(path: file.path)
        u.record(path: dir.appendingPathComponent("deleted.txt").path)

        let cs = u.candidates().sorted { $0.name < $1.name }
        XCTAssertEqual(cs.map(\.name), ["Foo", "report.pdf"])
        XCTAssertEqual(cs.map(\.isApp), [true, false])
    }
}
