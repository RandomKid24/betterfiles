import XCTest
@testable import FilesCore

final class SorterFilterTests: TempDirTestCase {
    func item(_ name: String, folder: Bool = false, size: Int64? = nil, modified: Double? = nil, kind: String = "") -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/x/\(name)"), isFolder: folder, size: size,
                 modified: modified.map { Date(timeIntervalSince1970: $0) }, kind: kind)
    }

    func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

    func testLargeFolderSortAndFilterArePrompt() {
        let items = (0..<10_000).map { item("file\($0).txt", kind: $0 % 2 == 0 ? "Text" : "Image") }
        let start = Date()
        _ = Sorter.sort(items, by: .name, ascending: true)
        _ = Sorter.sort(Filter.filter(items, text: "9"), by: .kind, ascending: false)
        let elapsed = Date().timeIntervalSince(start)
        print("LARGE_SORT_SECONDS \(elapsed)")
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testFoldersAlwaysFirstInBothDirections() {
        let items = [item("b.txt"), item("zdir", folder: true), item("a.txt"), item("adir", folder: true)]
        XCTAssertEqual(names(Sorter.sort(items, by: .name, ascending: true)), ["adir", "zdir", "a.txt", "b.txt"])
        XCTAssertEqual(names(Sorter.sort(items, by: .name, ascending: false)), ["zdir", "adir", "b.txt", "a.txt"])
    }

    func testNameSortIsNumericAwareAndCaseInsensitive() {
        let items = [item("file10"), item("file2"), item("File1")]
        XCTAssertEqual(names(Sorter.sort(items, by: .name, ascending: true)), ["File1", "file2", "file10"])
    }

    func testNameSortIgnoresAccents() {
        let items = [item("b"), item("É"), item("a")]
        XCTAssertEqual(names(Sorter.sort(items, by: .name, ascending: true)), ["a", "b", "É"])
    }

    func testSizeSort() {
        let items = [item("a", size: 10), item("b", size: 5), item("c", size: 7)]
        XCTAssertEqual(names(Sorter.sort(items, by: .size, ascending: true)), ["b", "c", "a"])
        XCTAssertEqual(names(Sorter.sort(items, by: .size, ascending: false)), ["a", "c", "b"])
    }

    func testModifiedSortPutsMissingDatesOldest() {
        let items = [item("new", modified: 200), item("none"), item("old", modified: 100)]
        XCTAssertEqual(names(Sorter.sort(items, by: .modified, ascending: true)), ["none", "old", "new"])
    }

    func testKindSortTiesFallBackToNameAscending() {
        let items = [item("b", kind: "PDF"), item("a", kind: "PDF"), item("c", kind: "Image")]
        XCTAssertEqual(names(Sorter.sort(items, by: .kind, ascending: true)), ["c", "a", "b"])
        XCTAssertEqual(names(Sorter.sort(items, by: .kind, ascending: false)), ["a", "b", "c"])
    }

    func testFilterIsCaseAndAccentInsensitiveSubstring() {
        let items = [item("Café.txt"), item("notes.md"), item("CAFETERIA")]
        XCTAssertEqual(names(Filter.filter(items, text: "cafe")), ["Café.txt", "CAFETERIA"])
        XCTAssertEqual(names(Filter.filter(items, text: "TES")), ["notes.md"])
    }

    func testEmptyOrWhitespaceFilterReturnsEverything() {
        let items = [item("a"), item("b")]
        XCTAssertEqual(Filter.filter(items, text: "").count, 2)
        XCTAssertEqual(Filter.filter(items, text: "   ").count, 2)
    }

    // Review Focus 3
    func testThreeThousandFilesListSortAndFilterQuickly() throws {
        for i in 0..<3000 { try touch("file \(i).txt") }
        let start = Date()
        let items = try FolderListing.list(dir)
        let sorted = Sorter.sort(Filter.filter(items, text: "file 1"), by: .name, ascending: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(items.count, 3000)
        XCTAssertEqual(sorted.count, 1111) // 1, 10-19, 100-199, 1000-1999
        XCTAssertLessThan(elapsed, 2.0)
    }
}
