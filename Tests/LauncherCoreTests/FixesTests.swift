import XCTest
@testable import LauncherCore

final class FixesTests: XCTestCase {
    func c(_ n: String) -> Candidate { Candidate(name: n, path: "/x/\(n)", isApp: false) }

    // Live Spotlight updates must not move the highlight off the row the user chose.
    func testSelectionFollowsPathWhenOrderChanges() {
        XCTAssertEqual(Selection.index(of: "/x/b", in: [c("a"), c("new"), c("b")]), 2)
    }

    func testSelectionFallsBackToZero() {
        XCTAssertEqual(Selection.index(of: "/x/gone", in: [c("a")]), 0)
        XCTAssertEqual(Selection.index(of: nil, in: [c("a")]), 0)
    }

    // Spotlight's shortcut is on when its entry is missing (default) or enabled.
    func testSpotlightShortcutDefaultsToEnabled() {
        XCTAssertTrue(SpotlightShortcut.isEnabled(nil))
        XCTAssertTrue(SpotlightShortcut.isEnabled([:]))
        XCTAssertTrue(SpotlightShortcut.isEnabled(["64": ["enabled": 1]]))
        XCTAssertTrue(SpotlightShortcut.isEnabled(["64": ["enabled": true]]))
    }

    func testSpotlightShortcutDisabled() {
        XCTAssertFalse(SpotlightShortcut.isEnabled(["64": ["enabled": 0]]))
        XCTAssertFalse(SpotlightShortcut.isEnabled(["64": ["enabled": false]]))
    }
}
