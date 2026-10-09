import XCTest
@testable import LauncherCore

final class PathQueryTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for d in ["Applications/Utilities", "Documents", ".hidden"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("Applications/Safari.txt"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func names(_ t: String) -> [String]? { PathQuery.entries(for: t, home: root.path)?.items.map(\.name) }

    func testNotAPath() { XCTAssertNil(names("safari")); XCTAssertNil(names("~foo")) }

    func testListsHomeAndHidesDotfiles() {
        XCTAssertEqual(names("~/"), ["Applications", "Documents"])
        XCTAssertEqual(names("~"), ["Applications", "Documents"])
    }

    func testDescendsCaseInsensitivelyAndFiltersByPrefix() {
        XCTAssertEqual(names("~/applications/"), ["Utilities", "Safari.txt"]) // folders first
        XCTAssertEqual(names("~/applications/saf"), ["Safari.txt"])
    }

    func testToleratesATypo() {
        XCTAssertEqual(names("~/docmuents/"), []) // folder is empty
        XCTAssertEqual(names("~/docuemnt"), ["Documents"])
    }

    func testShortcutAliases() {
        let r = PathQuery.entries(for: "/apps", home: root.path)
        XCTAssertEqual(r?.dir, "/Applications")
        XCTAssertFalse(r?.items.isEmpty ?? true)
    }

    func testDistance() {
        XCTAssertEqual(PathQuery.distance(Array("applicaiton"), Array("application")), 1)
    }

    func testTheExactCaseFromTheRequest() {
        let r = PathQuery.entries(for: "/applicaiton")
        XCTAssertEqual(r?.items.first?.name, "Applications")
        XCTAssertTrue(PathQuery.entries(for: "/applications/")?.items.contains { $0.name == "Safari.app" } ?? false)
    }
}
