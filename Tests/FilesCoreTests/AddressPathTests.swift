import XCTest
@testable import FilesCore

final class AddressPathTests: TempDirTestCase {
    func same(_ a: URL?, _ b: URL) -> Bool {
        a?.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path
    }

    func testAbsolutePathTrailingSlashAndPadding() throws {
        let sub = try mkdir("sub")
        XCTAssertTrue(same(AddressPath.resolve(sub.path, from: dir), sub))
        XCTAssertTrue(same(AddressPath.resolve(sub.path + "/", from: dir), sub))
        XCTAssertTrue(same(AddressPath.resolve("  \(sub.path)  ", from: dir), sub))
    }

    func testQuotesAreStripped() throws {
        let sub = try mkdir("sub")
        XCTAssertTrue(same(AddressPath.resolve("\"\(sub.path)\"", from: dir), sub))
        XCTAssertTrue(same(AddressPath.resolve("'\(sub.path)'", from: dir), sub))
    }

    func testRelativeAndParentPaths() throws {
        let sub = try mkdir("sub")
        let inner = try mkdir("inner", in: sub)
        XCTAssertTrue(same(AddressPath.resolve("inner", from: sub), inner))
        XCTAssertTrue(same(AddressPath.resolve("..", from: sub), dir))
    }

    func testTildeMeansHome() {
        XCTAssertTrue(same(AddressPath.resolve("~", from: dir), FileManager.default.homeDirectoryForCurrentUser))
    }

    func testMissingFileAndEmptyReturnNil() throws {
        let f = try touch("file.txt")
        XCTAssertNil(AddressPath.resolve(dir.appendingPathComponent("nope").path, from: dir))
        XCTAssertNil(AddressPath.resolve(f.path, from: dir), "a file is not a folder")
        XCTAssertNil(AddressPath.resolve("", from: dir))
        XCTAssertNil(AddressPath.resolve("   ", from: dir))
        XCTAssertNil(AddressPath.resolve("\"\"", from: dir))
    }

    // Review Focus 4
    func testUnusualFolderNames() throws {
        let odd = try mkdir("my folder (1) café ☕")
        let dotted = try mkdir("v1.2")
        XCTAssertTrue(same(AddressPath.resolve(odd.path, from: dir), odd))
        XCTAssertTrue(same(AddressPath.resolve("v1.2", from: dir), dotted))
    }

    func testBreadcrumbs() {
        let crumbs = AddressPath.breadcrumbs(URL(fileURLWithPath: "/usr/bin"))
        XCTAssertEqual(crumbs.map(\.url.path), ["/", "/usr", "/usr/bin"])
        XCTAssertEqual(crumbs.suffix(2).map(\.name), ["usr", "bin"])
        XCTAssertFalse(crumbs[0].name.isEmpty)
    }

    func testBreadcrumbsOfRootIsJustRoot() {
        XCTAssertEqual(AddressPath.breadcrumbs(URL(fileURLWithPath: "/")).map(\.url.path), ["/"])
    }
}
