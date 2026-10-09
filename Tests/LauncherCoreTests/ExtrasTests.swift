import XCTest
@testable import LauncherCore

final class ExtrasTests: XCTestCase {
    func testArithmetic() {
        XCTAssertEqual(Calc.answer("12*(3+4)"), "84")
        XCTAssertEqual(Calc.answer("2^3^2"), "512")
        XCTAssertEqual(Calc.answer("10/4"), "2.5")
        XCTAssertEqual(Calc.answer("1,000 + 5"), "1005")
        XCTAssertEqual(Calc.answer("7 × 6"), "42")
    }

    func testNonCalculationsStayQuiet() {
        XCTAssertNil(Calc.answer("safari"))
        XCTAssertNil(Calc.answer("42"))
        XCTAssertNil(Calc.answer("-5"))
        XCTAssertNil(Calc.answer("2+"))
        XCTAssertNil(Calc.answer("(1+2"))
        XCTAssertNil(Calc.answer("1/0"))
    }

    func testConversion() {
        XCTAssertEqual(Calc.answer("1 km to m"), "1 km = 1000 m")
        XCTAssertEqual(Calc.answer("100c in f"), "100 c = 212 f")
        XCTAssertEqual(Calc.answer("2 kg to lb")?.hasPrefix("2 kg = 4.4092"), true)
        XCTAssertNil(Calc.answer("5 km to kg")) // different kinds of unit
    }

    func testFileIndexFindsDeepFilesAndSkipsJunk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("a/b/Résumé final.pdf"))
        try Data().write(to: root.appendingPathComponent("node_modules/pkg/resume.js"))
        let index = FileIndex()
        index.build(root: root.path)
        let hits = index.search("resume")
        XCTAssertEqual(hits.map(\.name), ["Résumé final.pdf"])
        XCTAssertTrue(index.search("r").isEmpty) // one character is too broad
    }

    func testWebTargets() {
        XCTAssertEqual(WebTarget.url(for: "192.168.1.1")?.absoluteString, "http://192.168.1.1")
        XCTAssertEqual(WebTarget.url(for: "192.168.1.1:8080/admin")?.absoluteString, "http://192.168.1.1:8080/admin")
        XCTAssertEqual(WebTarget.url(for: "localhost:3000")?.absoluteString, "http://localhost:3000")
        XCTAssertEqual(WebTarget.url(for: "github.com/apple/swift")?.absoluteString, "https://github.com/apple/swift")
        XCTAssertEqual(WebTarget.url(for: "https://example.com")?.absoluteString, "https://example.com")
        XCTAssertEqual(WebTarget.url(for: "myserver:8000")?.absoluteString, "http://myserver:8000")
        // not addresses
        for t in ["main.swift", "notes.md", "safari", "999.1.1.1", "3.14", "report.pdf", "a b.com", "file:9999999"] {
            XCTAssertNil(WebTarget.url(for: t), t)
        }
    }

    func testSearchShortcuts() {
        XCTAssertEqual(WebTarget.shortcut(for: "g swift tips & tricks")?.url.absoluteString, "https://www.google.com/search?q=swift%20tips%20%26%20tricks")
        XCTAssertEqual(WebTarget.shortcut(for: "gh  repo:foo")?.title, "Search GitHub for \u{201C}repo:foo\u{201D}")
        XCTAssertNil(WebTarget.shortcut(for: "g"))
        XCTAssertNil(WebTarget.shortcut(for: "g "))
        XCTAssertNil(WebTarget.shortcut(for: "gx something"))
    }

    func testContentSearchPredicateIsSanitised() {
        XCTAssertEqual(ContentSearch.predicate(for: "invoice 2025"), "kMDItemTextContent == \"invoice\"cd && kMDItemTextContent == \"2025*\"cd")
        XCTAssertEqual(ContentSearch.predicate(for: "a\"b*c\\"), "kMDItemTextContent == \"abc*\"cd")
        XCTAssertNil(ContentSearch.predicate(for: "x"))
        XCTAssertNil(ContentSearch.predicate(for: "**"))
    }

    func testOneHugeFolderCannotStarveTheOthers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("aaa-huge"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        for i in 0..<200 { try Data().write(to: root.appendingPathComponent("aaa-huge/junk\(i).txt")) }
        try Data().write(to: root.appendingPathComponent("Documents/needle.txt"))
        let index = FileIndex()
        index.build(root: root.path, cap: 500, perPriority: 50, perOther: 20)
        XCTAssertEqual(index.search("needle").map(\.name), ["needle.txt"])
        XCTAssertLessThan(index.search("junk", limit: 1000).count, 30)   // the huge folder was cut off at its own limit
    }
}
