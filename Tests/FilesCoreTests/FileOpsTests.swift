import XCTest
@testable import FilesCore

final class FileOpsTests: TempDirTestCase {
    func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testMoveNeverOverwrites() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let src = try touch("f.txt", "from A", in: a)
        try touch("f.txt", "from B", in: b)

        let out = FileOps.move([src], to: b)

        XCTAssertEqual(out.first?.destination?.lastPathComponent, "f 2.txt")
        XCTAssertEqual(read(b.appendingPathComponent("f.txt")), "from B")
        XCTAssertEqual(read(b.appendingPathComponent("f 2.txt")), "from A")
        XCTAssertFalse(exists(src))
    }

    func testMoveIntoSameFolderIsNoOp() throws {
        let f = try touch("f.txt", "x")
        let out = FileOps.move([f], to: dir)
        XCTAssertTrue(out[0].succeeded)
        XCTAssertEqual(out[0].destination?.lastPathComponent, "f.txt")
        XCTAssertEqual(read(f), "x")
    }

    func testCopyIntoSameFolderMakesCopyNames() throws {
        let f = try touch("f.txt", "x")
        let first = FileOps.copy([f], to: dir)
        let second = FileOps.copy([f], to: dir)
        XCTAssertEqual(first[0].destination?.lastPathComponent, "f copy.txt")
        XCTAssertEqual(second[0].destination?.lastPathComponent, "f copy 2.txt")
        XCTAssertEqual(read(f), "x")
        XCTAssertEqual(read(dir.appendingPathComponent("f copy 2.txt")), "x")
    }

    // Review Focus 4
    func testDotfilesNoExtensionAndDottedFolders() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let env = try touch(".env", "1", in: a)
        try touch(".env", "2", in: b)
        let readme = try touch("README", "1", in: a)
        try touch("README", "2", in: b)
        let v = try mkdir("v1.2", in: a)
        try mkdir("v1.2", in: b)

        XCTAssertEqual(FileOps.move([env], to: b)[0].destination?.lastPathComponent, ".env 2")
        XCTAssertEqual(FileOps.move([readme], to: b)[0].destination?.lastPathComponent, "README 2")
        XCTAssertEqual(FileOps.copy([v], to: b)[0].destination?.lastPathComponent, "v1.2 copy")
    }

    func testFolderIntoItselfIsRefused() throws {
        let folder = try mkdir("F")
        let sub = try mkdir("sub", in: folder)
        for out in [FileOps.move([folder], to: sub), FileOps.copy([folder], to: sub), FileOps.move([folder], to: folder)] {
            XCTAssertEqual(out[0].error as? FileOpError, .intoItself)
            XCTAssertNil(out[0].destination)
        }
        XCTAssertTrue(exists(folder))
    }

    func testPartialFailureKeepsGoing() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let good = try touch("good.txt", "g", in: a)
        let missing = a.appendingPathComponent("missing.txt")
        let alsoGood = try touch("also.txt", "a", in: a)

        let out = FileOps.move([good, missing, alsoGood], to: b)

        XCTAssertEqual(out.map(\.succeeded), [true, false, true])
        XCTAssertTrue(exists(b.appendingPathComponent("good.txt")))
        XCTAssertTrue(exists(b.appendingPathComponent("also.txt")))
    }

    func testRename() throws {
        let f = try touch("old.txt", "x")
        let out = FileOps.rename(f, to: "new.txt")
        XCTAssertTrue(out.succeeded)
        XCTAssertTrue(exists(dir.appendingPathComponent("new.txt")))
        XCTAssertFalse(exists(f))
    }

    func testRenameRejectsBadNamesAndClashes() throws {
        let f = try touch("a.txt")
        try touch("b.txt")
        for bad in ["", "   ", "a/b", ".", ".."] {
            XCTAssertEqual(FileOps.rename(f, to: bad).error as? FileOpError, .invalidName, "name: \(bad)")
        }
        XCTAssertEqual(FileOps.rename(f, to: "b.txt").error as? FileOpError, .exists)
        XCTAssertTrue(exists(f))
    }

    func testRenameToSameNameIsNoOp() throws {
        let f = try touch("a.txt")
        XCTAssertTrue(FileOps.rename(f, to: "a.txt").succeeded)
    }

    // Review Focus 1
    func testCaseOnlyRenameWorks() throws {
        let f = try touch("a.txt", "x")
        let out = FileOps.rename(f, to: "A.txt")
        XCTAssertTrue(out.succeeded, "case-only rename must not be refused as already existing")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["A.txt"])
    }

    // Review Focus 2
    func testReadOnlyDestinationReportsFailure() throws {
        let src = try touch("f.txt", "x")
        let locked = try mkdir("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let moved = FileOps.move([src], to: locked)
        let copied = FileOps.copy([src], to: locked)

        XCTAssertFalse(moved[0].succeeded)
        XCTAssertFalse(copied[0].succeeded)
        XCTAssertTrue(exists(src), "a failed move must leave the source alone")
    }

    func testTrashMovesToTrashAndMissingFileFailsCleanly() throws {
        let name = "betterfiles-test-\(UUID().uuidString).txt"
        let f = try touch(name, "x")
        let missing = dir.appendingPathComponent("gone.txt")

        let out = FileOps.trash([f, missing])

        XCTAssertTrue(out[0].succeeded)
        XCTAssertFalse(exists(f))
        XCTAssertFalse(out[1].succeeded)
        if let trashed = out[0].destination { try? FileManager.default.removeItem(at: trashed) } // clean up our own test file
    }
}
