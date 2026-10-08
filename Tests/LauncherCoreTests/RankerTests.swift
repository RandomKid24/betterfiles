import XCTest
@testable import LauncherCore

final class RankerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let none: (String) -> UsageRecord? = { _ in nil }

    func c(_ name: String, app: Bool = false, dir: String = "/x") -> Candidate {
        Candidate(name: name, path: "\(dir)/\(name)", isApp: app)
    }

    func rank(_ q: String, _ cs: [Candidate], usage: ((String) -> UsageRecord?)? = nil, limit: Int = 8) -> [String] {
        Ranker.rank(query: q, candidates: cs, usage: usage ?? none, now: now, limit: limit).map(\.name)
    }

    func testPrefixBeatsSubstring() {
        XCTAssertEqual(rank("saf", [c("Unsafe"), c("Safari")]), ["Safari", "Unsafe"])
    }

    func testWordPrefixBeatsSubstring() {
        XCTAssertEqual(rank("notes", [c("Keynotes"), c("My Notes")]), ["My Notes", "Keynotes"])
    }

    func testNonMatchesAreDropped() {
        XCTAssertEqual(rank("zzz", [c("Safari")]), [])
    }

    func testFrecencyBreaksTie() {
        // Without usage "Notes" wins (shorter name). Usage on "Notebook" must flip it.
        let nb = c("Notebook"), n = c("Notes")
        let usage: (String) -> UsageRecord? = { $0 == nb.path ? UsageRecord(count: 5, last: self.now) : nil }
        XCTAssertEqual(rank("note", [n, nb], usage: usage), ["Notebook", "Notes"])
    }

    func testOldHeavyUseDecaysBelowRecentLightUse() {
        let old = c("Alpha1"), recent = c("Alpha2")
        let usage: (String) -> UsageRecord? = {
            if $0 == old.path { return UsageRecord(count: 5, last: self.now.addingTimeInterval(-60 * 86_400)) }
            if $0 == recent.path { return UsageRecord(count: 1, last: self.now) }
            return nil
        }
        XCTAssertEqual(rank("alpha", [old, recent], usage: usage), ["Alpha2", "Alpha1"])
    }

    func testAppBonusBeatsSameNamedFile() {
        XCTAssertEqual(
            Ranker.rank(query: "mail", candidates: [c("Mail", dir: "/f"), c("Mail", app: true, dir: "/a")], usage: none, now: now).map(\.path),
            ["/a/Mail", "/f/Mail"])
    }

    func testLimitIsApplied() {
        let many = (0..<20).map { c("File\($0)") }
        XCTAssertEqual(rank("file", many, limit: 8).count, 8)
    }

    // Review Focus 2
    func testEmptyAndWhitespaceQueryReturnNothing() {
        XCTAssertEqual(rank("", [c("Safari")]), [])
        XCTAssertEqual(rank("   ", [c("Safari")]), [])
    }

    // Review Focus 1
    func testDiacriticsAndCaseAreIgnored() {
        XCTAssertEqual(rank("cafe", [c("Café")]), ["Café"])
        XCTAssertEqual(rank("CAFÉ", [c("cafe")]), ["cafe"])
    }

    func testQueryIsTrimmed() {
        XCTAssertEqual(rank("  saf ", [c("Safari")]), ["Safari"])
    }
}
