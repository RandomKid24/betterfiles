import XCTest

/// Gives each test its own temporary folder, removed afterwards.
class TempDirTestCase: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Tests that make folders read-only restore permissions themselves; this is a safety net.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        try? FileManager.default.removeItem(at: dir)
    }

    @discardableResult
    func touch(_ name: String, _ content: String = "", in sub: URL? = nil) throws -> URL {
        let url = (sub ?? dir).appendingPathComponent(name)
        try Data(content.utf8).write(to: url)
        return url
    }

    @discardableResult
    func mkdir(_ name: String, in sub: URL? = nil) throws -> URL {
        let url = (sub ?? dir).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
