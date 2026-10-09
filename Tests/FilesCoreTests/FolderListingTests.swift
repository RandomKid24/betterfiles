import XCTest
@testable import FilesCore

final class FolderListingTests: TempDirTestCase {
    func testListsFilesFoldersHiddenAndPackages() throws {
        try touch("a.txt", "hello")
        try touch(".hidden")
        try mkdir("dir")
        try mkdir("X.app")

        let items = try FolderListing.list(dir)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        XCTAssertEqual(Set(byName.keys), ["a.txt", ".hidden", "dir", "X.app"])
        XCTAssertEqual(byName["a.txt"]?.size, 5)
        XCTAssertEqual(byName["a.txt"]?.isFolder, false)
        XCTAssertEqual(byName[".hidden"]?.isHidden, true)
        XCTAssertEqual(byName["dir"]?.isFolder, true)
        XCTAssertNil(byName["dir"]?.size)
        XCTAssertEqual(byName["X.app"]?.isFolder, false)
        XCTAssertEqual(byName["X.app"]?.isPackage, true)
        XCTAssertFalse(byName["a.txt"]!.kind.isEmpty)
        XCTAssertNotNil(byName["a.txt"]?.modified)
    }

    func testKeepsExtensionsInNames() throws {
        try touch("report.final.pdf")
        XCTAssertEqual(try FolderListing.list(dir).map(\.name), ["report.final.pdf"])
    }

    func testMissingFolderThrows() {
        XCTAssertThrowsError(try FolderListing.list(dir.appendingPathComponent("nope")))
    }

    func testSubfoldersSkipsFilesHiddenAndPackages() throws {
        try mkdir("Docs"); try mkdir(".secret"); try mkdir("App.app"); try touch("a.txt")
        XCTAssertEqual(FolderListing.subfolders(dir).map(\.name).sorted(), ["Docs"])
    }
}
