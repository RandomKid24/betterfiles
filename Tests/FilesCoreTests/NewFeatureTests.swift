import XCTest
@testable import FilesCore

final class NewFeatureTests: TempDirTestCase {
    func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    func testUndoMoveAndRename() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let f = try touch("f.txt", "x", in: a)
        let undo = UndoStack()
        let moved = FileOps.move([f], to: b)
        undo.recordMoves("move", moved)
        XCTAssertFalse(exists(f))
        XCTAssertEqual(undo.undo(), "Undid move")
        XCTAssertTrue(exists(f))
        XCTAssertNil(undo.undo())
    }

    func testUndoRefusesToOverwrite() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let f = try touch("f.txt", "x", in: a)
        let undo = UndoStack()
        undo.recordMoves("move", FileOps.move([f], to: b))
        try touch("f.txt", "new", in: a) // something took the original spot
        XCTAssertTrue(undo.undo()!.contains("Couldn"))
        XCTAssertEqual(try String(contentsOf: f, encoding: .utf8), "new")
    }

    func testUndoCreatedGoesToTrash() throws {
        let undo = UndoStack()
        let out = FileOps.newFolder(in: dir)
        undo.recordCreated("new folder", [out])
        XCTAssertTrue(exists(out.destination!))
        _ = undo.undo()
        XCTAssertFalse(exists(out.destination!))
    }

    func testZipRoundTrip() throws {
        let f = try touch("note.txt", "hello")
        let zip = Archive.compress([f])
        XCTAssertEqual(zip.destination?.lastPathComponent, "note.txt.zip")
        let out = Archive.extract(zip.destination!)
        XCTAssertEqual(out.destination?.lastPathComponent, "note.txt 2") // never overwrites the original
        XCTAssertEqual(try String(contentsOf: out.destination!.appendingPathComponent("note.txt"), encoding: .utf8), "hello")
    }

    func testBatchRenamePlan() {
        let urls = (1...3).map { dir.appendingPathComponent("x\($0).jpg") } + [dir.appendingPathComponent("README")]
        let names = BatchRename.plan(urls, base: "Trip", start: 8).map(\.newName)
        XCTAssertEqual(names, ["Trip 08.jpg", "Trip 09.jpg", "Trip 10.jpg", "Trip 11"])
    }

    func testFoldersFirstCanBeTurnedOff() {
        let items = [FileItem(url: dir.appendingPathComponent("b"), isFolder: true), FileItem(url: dir.appendingPathComponent("a.txt"))]
        XCTAssertEqual(Sorter.sort(items, by: .name, ascending: true).map(\.name), ["b", "a.txt"])
        XCTAssertEqual(Sorter.sort(items, by: .name, ascending: true, foldersFirst: false).map(\.name), ["a.txt", "b"])
    }

    func testAliasResolvesToOriginal() throws {
        let f = try touch("doc.txt", "hi")
        let out = FileOps.makeAlias(of: f)
        XCTAssertEqual(out.destination?.lastPathComponent, "doc.txt alias")
        let resolved = try URL(resolvingAliasFileAt: out.destination!)
        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, f.resolvingSymlinksInPath().path)
    }

    func testCompareAndCopyMissing() throws {
        let l = try mkdir("L"), r = try mkdir("R")
        try mkdir("sub", in: l)
        try touch("same.txt", "x", in: l); try touch("same.txt", "x", in: r)
        try touch("only-left.txt", "a", in: l)
        try touch("deep.txt", "d", in: l.appendingPathComponent("sub"))
        try touch("only-right.txt", "b", in: r)
        try touch("diff.txt", "short", in: l); try touch("diff.txt", "much longer", in: r)
        let res = FolderCompare.compare(l, r)
        XCTAssertEqual(res.onlyLeft, ["only-left.txt", "sub/deep.txt"])
        XCTAssertEqual(res.onlyRight, ["only-right.txt"])
        XCTAssertEqual(res.different, ["diff.txt"])
        let out = FolderCompare.copyMissing(res.onlyLeft, from: l, to: r)
        XCTAssertTrue(out.allSatisfy(\.succeeded))
        XCTAssertEqual(try String(contentsOf: r.appendingPathComponent("sub/deep.txt"), encoding: .utf8), "d")
        XCTAssertEqual(FolderCompare.compare(l, r).onlyLeft, [])
        // never overwrites
        XCTAssertFalse(FolderCompare.copyMissing(["diff.txt"], from: l, to: r)[0].succeeded)
    }

    func testTagToggle() throws {
        let f = try touch("t.txt")
        let item = { FileItem(url: f, tags: (try? f.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []) }
        XCTAssertTrue(Tags.toggle("Red", on: [item()])[0].succeeded)
        XCTAssertEqual(try f.resourceValues(forKeys: [.tagNamesKey]).tagNames, ["Red"])
        Tags.toggle("Red", on: [item()])
        XCTAssertEqual(try f.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? [], [])
        XCTAssertTrue(Filter.filter([FileItem(url: f, tags: ["Blue"])], text: "blue").count == 1)
    }
}
