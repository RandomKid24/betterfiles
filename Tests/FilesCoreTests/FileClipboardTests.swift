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

    func testPasteWithEmptyClipboardDoesNothing() {
        XCTAssertFalse(clip.canPaste)
        XCTAssertTrue(clip.paste(into: dir).isEmpty)
    }
}
