import XCTest
@testable import FilesCore

final class FakePasteboard: PasteboardProtocol {
    private(set) var changeCount = 0
    private(set) var urls: [URL] = []
    func write(urls: [URL]) { self.urls = urls; changeCount += 1 }
}

final class FileClipboardTests: TempDirTestCase {
    var board: FakePasteboard!
    var clip: FileClipboard!

    override func setUpWithError() throws {
        try super.setUpWithError()
        board = FakePasteboard()
        clip = FileClipboard(pasteboard: board)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func testCutThenPasteMovesAndClearsTheClipboard() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let f = try touch("f.txt", "x", in: a)

        clip.cut([f])
        let out = clip.paste(into: b)

        XCTAssertTrue(out[0].succeeded)
        XCTAssertFalse(exists(f))
        XCTAssertTrue(exists(b.appendingPathComponent("f.txt")))
        XCTAssertFalse(clip.canPaste, "a finished cut-paste leaves nothing to paste")
        XCTAssertTrue(clip.paste(into: b).isEmpty)
    }

    func testCutThenSomethingElseCopiedPasteCopiesInstead() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let cutFile = try touch("cut.txt", "x", in: a)
        let other = try touch("other.txt", "y", in: a)

        clip.cut([cutFile])
        board.write(urls: [other]) // something else is copied (here or in another app)
        clip.paste(into: b)

        XCTAssertTrue(exists(cutFile), "the stale cut must not move anything")
        XCTAssertTrue(exists(other), "paste after a newer copy copies")
        XCTAssertTrue(exists(b.appendingPathComponent("other.txt")))
        XCTAssertFalse(exists(b.appendingPathComponent("cut.txt")))
    }

    func testCutThenSameFilesRecopiedElsewhereIsACopy() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let f = try touch("f.txt", "x", in: a)

        clip.cut([f])
        board.write(urls: [f])
        clip.paste(into: b)

        XCTAssertTrue(exists(f))
        XCTAssertTrue(exists(b.appendingPathComponent("f.txt")))
    }

    func testCopyThenPasteCopiesAndCanPasteAgain() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let f = try touch("f.txt", "x", in: a)

        clip.copy([f])
        clip.paste(into: b)
        clip.paste(into: b)

        XCTAssertTrue(exists(f))
        XCTAssertTrue(exists(b.appendingPathComponent("f.txt")))
        XCTAssertTrue(exists(b.appendingPathComponent("f copy.txt")))
    }

    func testCutPasteIntoSameFolderIsNoOp() throws {
        let f = try touch("f.txt", "x")
        clip.cut([f])
        let out = clip.paste(into: dir)
        XCTAssertTrue(out[0].succeeded)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["f.txt"])
    }

    func testCopyPasteIntoSameFolderMakesACopy() throws {
        let f = try touch("f.txt", "x")
        clip.copy([f])
        clip.paste(into: dir)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)), ["f.txt", "f copy.txt"])
    }

    func testPartialFailureKeepsFailedItemsCutForRetry() throws {
        let a = try mkdir("A"), b = try mkdir("B")
        let good = try touch("good.txt", "x", in: a)
        let missing = a.appendingPathComponent("missing.txt") // does not exist yet

        clip.cut([good, missing])
        let out = clip.paste(into: b)

        XCTAssertFalse(exists(good))
        XCTAssertTrue(exists(b.appendingPathComponent("good.txt")))
        XCTAssertEqual(out.count, 2)
        XCTAssertFalse(out[1].succeeded)
        XCTAssertTrue(clip.canPaste, "failed items must stay on the clipboard")
        XCTAssertEqual(board.urls, [missing])

        try Data("y".utf8).write(to: missing) // the problem is fixed; retry
        clip.paste(into: b)

        XCTAssertFalse(exists(missing), "the retried cut must still be a move")
        XCTAssertTrue(exists(b.appendingPathComponent("missing.txt")))
        XCTAssertFalse(clip.canPaste)
    }

    func testPasteWithEmptyClipboardDoesNothing() {
        XCTAssertFalse(clip.canPaste)
        XCTAssertTrue(clip.paste(into: dir).isEmpty)
    }
}
