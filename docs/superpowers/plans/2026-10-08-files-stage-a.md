# BetterFiles Stage A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS file manager, Explorer-style: folder tree, editable address bar, details and zoomable icon views, in-folder filter, and Cut+Paste that moves files.

**Architecture:** Two new targets in the existing package. `FilesCore` is a UI-free, unit-tested library (listing, sorting, filtering, address parsing, file operations, cut/copy/paste rules). `BetterFiles` is an AppKit app: a SwiftUI shell (top bar, address bar, status bar) around AppKit lists (`NSOutlineView` tree, `NSTableView` details, `NSCollectionView` icons) driven by one `@Observable` `BrowserModel`.

**Tech Stack:** Swift 6.4, SwiftUI + AppKit, QuickLookThumbnailing, XCTest. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-08-files-stage-a-design.md`

## Global Constraints

- macOS 26, Swift 6.4, `swiftLanguageModes: [.v5]` (already set at package level). No new dependencies.
- `FilesCore` imports Foundation only. No AppKit in it.
- Hidden files and file extensions are always shown in the list (Stage A has no toggle).
- Delete always means move to Trash. No permanent delete anywhere.
- Nothing is ever overwritten: clashes get a unique name (move: `name 2.ext`; copy: `name copy.ext`, `name copy 2.ext`).
- Cut becomes a move only if the pasteboard `changeCount` is unchanged since the cut; otherwise Paste copies.
- Shortcuts: Cmd+C/X/V, Cmd+A, Return opens, F2 renames, Cmd+Delete trashes, Cmd+Up parent, Cmd+[ back, Cmd+] forward, Cmd+L address bar, Cmd+F filter, Cmd+1 details, Cmd+2 icons, Cmd+R reload.
- Icon zoom range 32 to 256 pt. View mode, sort column and direction, and zoom persist in `UserDefaults`.
- Not in Stage A: tabs, dual pane, default-app setup, Quick Look pane, folder watching, network drives, tags.
- Commits are local only. Do not push without being asked.

## Decisions this plan adds to the spec (silent in the spec)

- `FileItem` gets `isPackage` (so `.app` and similar open instead of navigating). `isFolder` is true for directories that are not packages.
- The sidebar tree lists non-hidden folders only; the file list shows everything.
- `breadcrumbs` returns `[Crumb]` (a struct with `name` and `url`) instead of a tuple.
- Copy into a folder where the name already exists always uses `name copy` style, not just same-folder copies.

## Review Focus

Inputs the spec implies but no obvious task exercises. Each line has a test or a smoke-test check named below.

1. Case-only rename (`a.txt` to `A.txt`) must work and not be refused as "already exists". Pinned in Task 4.
2. Pasting or moving into a read-only folder must report a failure and not crash or half-apply. Pinned in Task 4.
3. A 3,000-file folder must list, sort and filter in well under a second or two. Pinned in Task 2.
4. Unusual names: leading dot (`.env`), no extension, spaces, parentheses, emoji, and dotted folder names (`v1.2`). Pinned in Tasks 3 and 4.
5. Clicking folders quickly: a slow earlier load must never overwrite the folder you clicked last. Pinned in the Task 10 smoke test.

---

### Task 1: Package targets, `FileItem`, `FolderListing`

**Files:**
- Modify: `Package.swift`
- Create: `Sources/FilesCore/FileItem.swift`
- Create: `Sources/FilesCore/FolderListing.swift`
- Create: `Sources/BetterFiles/main.swift` (placeholder so the target builds)
- Create: `Tests/FilesCoreTests/Support.swift`
- Test: `Tests/FilesCoreTests/FolderListingTests.swift`

**Interfaces:**
- Produces:
  - `public struct FileItem: Equatable, Hashable, Sendable { url: URL; isFolder: Bool; isHidden: Bool; isPackage: Bool; size: Int64?; modified: Date?; kind: String; var name: String; init(url:isFolder:isHidden:isPackage:size:modified:kind:) }` (all but `url` have defaults)
  - `public enum FolderListing { static func list(_ url: URL) throws -> [FileItem] }`
  - Test support: `class TempDirTestCase: XCTestCase { var dir: URL!; func touch(_ name: String, _ content: String = "", in sub: URL? = nil) throws -> URL; func mkdir(_ name: String, in sub: URL? = nil) throws -> URL }`

- [ ] **Step 0: Commit the pending launcher and spec work on its own**

```bash
git add -A && git commit -m "feat(launcher): animated glass panel, fast word-prefix search, app index, history candidates

Adds the Stage A file manager spec.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
Expected: commit succeeds. (Skip this step if `git status` is already clean.)

- [ ] **Step 1: Add the targets to `Package.swift`**

Replace the `targets:` array so it reads:
```swift
    targets: [
        .target(name: "LauncherCore"),
        .executableTarget(name: "BetterLauncher", dependencies: ["LauncherCore"]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
        .target(name: "FilesCore"),
        .executableTarget(name: "BetterFiles", dependencies: ["FilesCore"]),
        .testTarget(name: "FilesCoreTests", dependencies: ["FilesCore"]),
    ],
```

`Sources/BetterFiles/main.swift`:
```swift
print("BetterFiles placeholder")
```

- [ ] **Step 2: Write the support helper and the failing tests**

`Tests/FilesCoreTests/Support.swift`:
```swift
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
```

`Tests/FilesCoreTests/FolderListingTests.swift`:
```swift
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
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter FolderListingTests`
Expected: FAIL to compile with "cannot find 'FolderListing' in scope".

- [ ] **Step 4: Write the implementation**

`Sources/FilesCore/FileItem.swift`:
```swift
import Foundation

public struct FileItem: Equatable, Hashable, Sendable {
    public let url: URL
    public let isFolder: Bool
    public let isHidden: Bool
    public let isPackage: Bool
    public let size: Int64?
    public let modified: Date?
    public let kind: String

    public init(url: URL, isFolder: Bool = false, isHidden: Bool = false, isPackage: Bool = false,
                size: Int64? = nil, modified: Date? = nil, kind: String = "") {
        self.url = url
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.size = size
        self.modified = modified
        self.kind = kind
    }

    /// File name including its extension.
    public var name: String { url.lastPathComponent }
}
```

`Sources/FilesCore/FolderListing.swift`:
```swift
import Foundation

public enum FolderListing {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
        .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    /// Lists a folder including hidden files, with every attribute prefetched in one pass. Safe to call off the main thread.
    public static func list(_ url: URL) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
        return urls.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isPackage = v?.isPackage ?? false
            let isDir = v?.isDirectory ?? false
            return FileItem(
                url: u,
                isFolder: isDir && !isPackage,
                isHidden: v?.isHidden ?? u.lastPathComponent.hasPrefix("."),
                isPackage: isPackage,
                size: isDir ? nil : v?.fileSize.map(Int64.init),
                modified: v?.contentModificationDate,
                kind: v?.localizedTypeDescription ?? (isDir ? "Folder" : "Document"))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter FolderListingTests`
Expected: PASS, 3 tests. If `X.app`'s `isPackage` is false for an empty directory on this macOS version, create `X.app/Contents` inside it in the test and re-run (ledger the change).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(files): FilesCore targets, FileItem, FolderListing

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `Column`, `Sorter`, `Filter`

**Files:**
- Create: `Sources/FilesCore/Sorter.swift`
- Create: `Sources/FilesCore/Filter.swift`
- Test: `Tests/FilesCoreTests/SorterFilterTests.swift`

**Interfaces:**
- Consumes: `FileItem` (Task 1)
- Produces:
  - `public enum Column: String, CaseIterable, Sendable { case name, modified, size, kind }`
  - `public enum Sorter { static func sort(_ items: [FileItem], by column: Column, ascending: Bool) -> [FileItem] }`
  - `public enum Filter { static func filter(_ items: [FileItem], text: String) -> [FileItem] }`

- [ ] **Step 1: Write the failing tests**

`Tests/FilesCoreTests/SorterFilterTests.swift`:
```swift
import XCTest
@testable import FilesCore

final class SorterFilterTests: TempDirTestCase {
    func item(_ name: String, folder: Bool = false, size: Int64? = nil, modified: Double? = nil, kind: String = "") -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/x/\(name)"), isFolder: folder, size: size,
                 modified: modified.map { Date(timeIntervalSince1970: $0) }, kind: kind)
    }

    func names(_ items: [FileItem]) -> [String] { items.map(\.name) }

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SorterFilterTests`
Expected: FAIL to compile with "cannot find 'Sorter' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/FilesCore/Sorter.swift`:
```swift
import Foundation

public enum Column: String, CaseIterable, Sendable {
    case name, modified, size, kind
}

public enum Sorter {
    /// Folders always come first, in both directions (as in Explorer). Ties always fall back to name ascending.
    public static func sort(_ items: [FileItem], by column: Column, ascending: Bool) -> [FileItem] {
        items.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            let r = compare(a, b, column)
            if r != .orderedSame { return ascending ? r == .orderedAscending : r == .orderedDescending }
            let n = compareNames(a.name, b.name)
            return n != .orderedSame ? n == .orderedAscending : a.name < b.name
        }
    }

    private static func compare(_ a: FileItem, _ b: FileItem, _ column: Column) -> ComparisonResult {
        switch column {
        case .name: return compareNames(a.name, b.name)
        case .modified: return cmp(a.modified ?? .distantPast, b.modified ?? .distantPast)
        case .size: return cmp(a.size ?? -1, b.size ?? -1)
        case .kind: return compareNames(a.kind, b.kind)
        }
    }

    private static func compareNames(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric])
    }

    private static func cmp<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
```

`Sources/FilesCore/Filter.swift`:
```swift
import Foundation

public enum Filter {
    public static func filter(_ items: [FileItem], text: String) -> [FileItem] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return items }
        return items.filter { $0.name.range(of: t, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SorterFilterTests`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(files): Sorter and Filter

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `AddressPath`

**Files:**
- Create: `Sources/FilesCore/AddressPath.swift`
- Test: `Tests/FilesCoreTests/AddressPathTests.swift`

**Interfaces:**
- Produces:
  - `public struct Crumb: Equatable, Identifiable, Sendable { name: String; url: URL; var id: URL }`
  - `public enum AddressPath { static func resolve(_ text: String, from base: URL) -> URL?; static func breadcrumbs(_ url: URL) -> [Crumb] }`

- [ ] **Step 1: Write the failing tests**

`Tests/FilesCoreTests/AddressPathTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AddressPathTests`
Expected: FAIL to compile with "cannot find 'AddressPath' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/FilesCore/AddressPath.swift`:
```swift
import Foundation

public struct Crumb: Equatable, Identifiable, Sendable {
    public let name: String
    public let url: URL
    public var id: URL { url }
}

public enum AddressPath {
    /// Turns typed or pasted text into an existing folder, or nil.
    public static func resolve(_ text: String, from base: URL) -> URL? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 2, let f = s.first, f == s.last, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return nil }
        let expanded = (s as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : base.appendingPathComponent(expanded)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url.standardizedFileURL
    }

    /// Root first, current folder last.
    public static func breadcrumbs(_ url: URL) -> [Crumb] {
        var out: [Crumb] = []
        var cur = url.standardizedFileURL
        while true {
            let isRoot = cur.path == "/"
            let name = isRoot
                ? ((try? cur.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "/")
                : cur.lastPathComponent
            out.append(Crumb(name: name, url: cur))
            if isRoot { break }
            cur = cur.deletingLastPathComponent()
        }
        return out.reversed()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AddressPathTests`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(files): AddressPath resolve and breadcrumbs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `FileOps`

**Files:**
- Create: `Sources/FilesCore/FileOps.swift`
- Test: `Tests/FilesCoreTests/FileOpsTests.swift`

**Interfaces:**
- Produces:
  - `public enum FileOpError: LocalizedError, Equatable { case intoItself, invalidName, exists }`
  - `public struct OpOutcome { source: URL; destination: URL?; error: Error?; var succeeded: Bool }`
  - `public enum FileOps { static func move(_ urls: [URL], to folder: URL) -> [OpOutcome]; static func copy(_ urls: [URL], to folder: URL) -> [OpOutcome]; static func rename(_ url: URL, to newName: String) -> OpOutcome; static func trash(_ urls: [URL]) -> [OpOutcome] }`

- [ ] **Step 1: Write the failing tests**

`Tests/FilesCoreTests/FileOpsTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileOpsTests`
Expected: FAIL to compile with "cannot find 'FileOps' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/FilesCore/FileOps.swift`:
```swift
import Foundation

public enum FileOpError: LocalizedError, Equatable {
    case intoItself, invalidName, exists

    public var errorDescription: String? {
        switch self {
        case .intoItself: return "a folder can't be moved or copied into itself"
        case .invalidName: return "that isn't a valid name"
        case .exists: return "an item with that name already exists"
        }
    }
}

public struct OpOutcome {
    public let source: URL
    public let destination: URL?
    public let error: Error?
    public var succeeded: Bool { error == nil }
}

public enum FileOps {
    private enum Style { case numbered, copy }

    /// Moves each item into `folder`. Never overwrites. One failure does not stop the others.
    public static func move(_ urls: [URL], to folder: URL) -> [OpOutcome] {
        urls.map { src in
            if isInside(folder, of: src) { return fail(src, .intoItself) }
            if same(src.deletingLastPathComponent(), folder) { return OpOutcome(source: src, destination: src, error: nil) }
            let dest = unique(src.lastPathComponent, isFolder: isDir(src), in: folder, style: .numbered)
            return attempt(src, dest) { try FileManager.default.moveItem(at: src, to: dest) }
        }
    }

    public static func copy(_ urls: [URL], to folder: URL) -> [OpOutcome] {
        urls.map { src in
            if isInside(folder, of: src) { return fail(src, .intoItself) }
            let dest = unique(src.lastPathComponent, isFolder: isDir(src), in: folder, style: .copy)
            return attempt(src, dest) { try FileManager.default.copyItem(at: src, to: dest) }
        }
    }

    public static func rename(_ url: URL, to newName: String) -> OpOutcome {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { return fail(url, .invalidName) }
        if name == url.lastPathComponent { return OpOutcome(source: url, destination: url, error: nil) }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        // A case-only change (a.txt -> A.txt) "exists" on a case-insensitive disk because it is the same file.
        let caseOnly = dest.path.caseInsensitiveCompare(url.path) == .orderedSame
        if FileManager.default.fileExists(atPath: dest.path), !caseOnly { return fail(url, .exists) }
        return attempt(url, dest) { try FileManager.default.moveItem(at: url, to: dest) }
    }

    /// Moves to the Trash. There is deliberately no permanent delete.
    public static func trash(_ urls: [URL]) -> [OpOutcome] {
        urls.map { src in
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: src, resultingItemURL: &result)
                return OpOutcome(source: src, destination: result as URL?, error: nil)
            } catch {
                return OpOutcome(source: src, destination: nil, error: error)
            }
        }
    }

    // MARK: helpers

    private static func attempt(_ src: URL, _ dest: URL, _ work: () throws -> Void) -> OpOutcome {
        do { try work(); return OpOutcome(source: src, destination: dest, error: nil) }
        catch { return OpOutcome(source: src, destination: nil, error: error) }
    }

    private static func fail(_ src: URL, _ e: FileOpError) -> OpOutcome {
        OpOutcome(source: src, destination: nil, error: e)
    }

    private static func resolved(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private static func same(_ a: URL, _ b: URL) -> Bool { resolved(a) == resolved(b) }

    private static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    /// True when `folder` is `src` itself or lies inside it (only matters when `src` is a folder).
    private static func isInside(_ folder: URL, of src: URL) -> Bool {
        guard isDir(src) else { return false }
        let f = resolved(folder), s = resolved(src)
        return f == s || f.hasPrefix(s + "/")
    }

    private static func unique(_ name: String, isFolder: Bool, in folder: URL, style: Style) -> URL {
        let fm = FileManager.default
        let ns = name as NSString
        let ext = isFolder ? "" : ns.pathExtension
        let base = isFolder ? name : ns.deletingPathExtension
        func make(_ suffix: String) -> String { ext.isEmpty ? base + suffix : base + suffix + "." + ext }

        var candidate = folder.appendingPathComponent(name)
        var n = 1
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            let suffix = style == .numbered ? " \(n)" : (n == 2 ? " copy" : " copy \(n - 1)")
            candidate = folder.appendingPathComponent(make(suffix))
        }
        return candidate
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter FileOpsTests`
Expected: PASS, 11 tests. On a case-sensitive volume `testCaseOnlyRenameWorks` still passes.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(files): FileOps (move, copy, rename, trash)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `FileClipboard`

**Files:**
- Create: `Sources/FilesCore/FileClipboard.swift`
- Test: `Tests/FilesCoreTests/FileClipboardTests.swift`

**Interfaces:**
- Consumes: `FileOps`, `OpOutcome` (Task 4)
- Produces:
  - `public protocol PasteboardProtocol: AnyObject { var changeCount: Int { get }; var urls: [URL] { get }; func write(urls: [URL]) }` (`write(urls: [])` clears)
  - `public final class FileClipboard { init(pasteboard: PasteboardProtocol); func copy(_ urls: [URL]); func cut(_ urls: [URL]); var canPaste: Bool; func paste(into folder: URL) -> [OpOutcome] }`

- [ ] **Step 1: Write the failing tests**

`Tests/FilesCoreTests/FileClipboardTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter FileClipboardTests`
Expected: FAIL to compile with "cannot find type 'PasteboardProtocol' in scope".

- [ ] **Step 3: Write the implementation**

`Sources/FilesCore/FileClipboard.swift`:
```swift
import Foundation

/// The slice of NSPasteboard that FileClipboard needs, so tests can use a fake.
public protocol PasteboardProtocol: AnyObject {
    var changeCount: Int { get }
    var urls: [URL] { get }
    /// An empty array clears the pasteboard.
    func write(urls: [URL])
}

/// Explorer-style Cut / Copy / Paste. A cut is only honoured as a move if nothing else
/// has been put on the pasteboard since; otherwise Paste copies whatever is there now.
public final class FileClipboard {
    private let pasteboard: PasteboardProtocol
    private var pendingCutChangeCount: Int?

    public init(pasteboard: PasteboardProtocol) {
        self.pasteboard = pasteboard
    }

    public var canPaste: Bool { !pasteboard.urls.isEmpty }

    public func copy(_ urls: [URL]) {
        pasteboard.write(urls: urls)
        pendingCutChangeCount = nil
    }

    public func cut(_ urls: [URL]) {
        pasteboard.write(urls: urls)
        pendingCutChangeCount = pasteboard.changeCount
    }

    @discardableResult
    public func paste(into folder: URL) -> [OpOutcome] {
        let urls = pasteboard.urls
        guard !urls.isEmpty else { return [] }
        if pendingCutChangeCount == pasteboard.changeCount {
            let outcomes = FileOps.move(urls, to: folder)
            pendingCutChangeCount = nil
            pasteboard.write(urls: []) // like Explorer: a completed cut-paste empties the clipboard
            return outcomes
        }
        return FileOps.copy(urls, to: folder)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass, then the whole suite**

Run: `swift test`
Expected: PASS: all `LauncherCoreTests` and `FilesCoreTests` (about 60 tests, 0 failures).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(files): FileClipboard cut/copy/paste rules

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: App shell: `BrowserModel`, window, menus, top bar, address bar, status bar

**Files:**
- Create: `Sources/BetterFiles/SystemPasteboard.swift`
- Create: `Sources/BetterFiles/BrowserModel.swift`
- Create: `Sources/BetterFiles/BrowserView.swift` (contains `BrowserView`, `TopBar`, `StatusBar`)
- Create: `Sources/BetterFiles/AddressBar.swift`
- Create: `Sources/BetterFiles/AppDelegate.swift`
- Modify: `Sources/BetterFiles/main.swift`

**Interfaces:**
- Consumes: everything in `FilesCore`.
- Produces:
  - `enum ViewMode: String { case details, icons }`
  - `@MainActor @Observable final class BrowserModel` with: `private(set) var url, visible, version, message, status, sortColumn, ascending, viewMode, zoom, backStack, forwardStack`; `var selection: Set<URL>`, `var filter: String`, `var addressFocusToken: Int`, `var filterFocusToken: Int`; computed `canGoBack`, `canGoForward`, `displayMessage`, `selectedItems`; methods `navigate(to:)`, `goBack()`, `goForward()`, `goUp()`, `reload()`, `recompute()`, `setSort(_:ascending:)`, `setViewMode(_:)`, `setZoom(_:)`, `open(_:)`, `openSelection()`, `copySelection()`, `cutSelection()`, `paste()`, `trashSelection()`, `rename(_:to:)`
  - `final class SystemPasteboard: PasteboardProtocol`

No unit tests (UI layer). Verified by build plus the smoke test in Task 10.

- [ ] **Step 1: Write `SystemPasteboard.swift`**

```swift
import AppKit
import FilesCore

final class SystemPasteboard: PasteboardProtocol {
    private let pb = NSPasteboard.general

    var changeCount: Int { pb.changeCount }

    var urls: [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func write(urls: [URL]) {
        pb.clearContents()
        if !urls.isEmpty { pb.writeObjects(urls as [NSURL]) }
    }
}
```

- [ ] **Step 2: Write `BrowserModel.swift`**

```swift
import AppKit
import FilesCore
import Observation

enum ViewMode: String { case details, icons }

@MainActor @Observable
final class BrowserModel {
    private(set) var url: URL
    private(set) var visible: [FileItem] = []
    private(set) var version = 0   // bumps whenever `visible` changes, so AppKit views know to reload
    private(set) var message: String?
    private(set) var status: String?
    private(set) var sortColumn: Column
    private(set) var ascending: Bool
    private(set) var viewMode: ViewMode
    private(set) var zoom: Double
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    var selection: Set<URL> = []
    var filter = ""
    var addressFocusToken = 0
    var filterFocusToken = 0

    @ObservationIgnored private var items: [FileItem] = []
    @ObservationIgnored private var loadID = 0
    @ObservationIgnored private let clipboard = FileClipboard(pasteboard: SystemPasteboard())
    @ObservationIgnored private let defaults = UserDefaults.standard

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = start
        let d = UserDefaults.standard
        sortColumn = Column(rawValue: d.string(forKey: "sortColumn") ?? "") ?? .name
        ascending = d.object(forKey: "ascending") as? Bool ?? true
        viewMode = ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .details
        zoom = d.object(forKey: "zoom") as? Double ?? 96
        reload()
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var selectedItems: [FileItem] { visible.filter { selection.contains($0.url) } }
    var displayMessage: String? {
        message ?? (visible.isEmpty && !filter.isEmpty ? "Nothing matches \u{201C}\(filter)\u{201D}." : nil)
    }

    // MARK: navigation

    func navigate(to target: URL, recordHistory: Bool = true) {
        let target = target.standardizedFileURL
        if target.path != url.path {
            if recordHistory { backStack.append(url); forwardStack.removeAll() }
            url = target
            selection = []
            filter = ""
            status = nil
        }
        reload()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(url)
        navigate(to: prev, recordHistory: false)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(url)
        navigate(to: next, recordHistory: false)
    }

    func goUp() {
        guard url.path != "/" else { return }
        navigate(to: url.deletingLastPathComponent())
    }

    // MARK: loading

    func reload() {
        loadID += 1
        let id = loadID, target = url
        Task.detached {
            let result = Result { try FolderListing.list(target) }
            await MainActor.run { self.finishLoad(id, result) }
        }
    }

    private func finishLoad(_ id: Int, _ result: Result<[FileItem], Error>) {
        guard id == loadID else { return } // a newer folder was requested while this one loaded
        switch result {
        case .success(let list):
            items = list
            message = list.isEmpty ? "This folder is empty." : nil
        case .failure(let error):
            items = []
            message = Self.describe(error)
        }
        recompute()
    }

    private static func describe(_ error: Error) -> String {
        switch (error as NSError).code {
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
            return "This folder no longer exists."
        case NSFileReadNoPermissionError:
            return "Can\u{2019}t open this folder. macOS may need you to allow access in System Settings > Privacy & Security > Files and Folders."
        default:
            return error.localizedDescription
        }
    }

    func recompute() {
        visible = Sorter.sort(Filter.filter(items, text: filter), by: sortColumn, ascending: ascending)
        selection = selection.intersection(Set(visible.map(\.url)))
        version += 1
    }

    // MARK: view settings

    func setSort(_ column: Column, ascending: Bool) {
        sortColumn = column
        self.ascending = ascending
        defaults.set(column.rawValue, forKey: "sortColumn")
        defaults.set(ascending, forKey: "ascending")
        recompute()
    }

    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        defaults.set(mode.rawValue, forKey: "viewMode")
    }

    func setZoom(_ value: Double) {
        zoom = min(256, max(32, value))
        defaults.set(zoom, forKey: "zoom")
    }

    // MARK: actions

    func open(_ item: FileItem) {
        if item.isFolder { navigate(to: item.url) } else { NSWorkspace.shared.open(item.url) }
    }

    func openSelection() {
        let picked = selectedItems
        if picked.count == 1, let one = picked.first { open(one); return }
        picked.filter { !$0.isFolder }.forEach { NSWorkspace.shared.open($0.url) }
    }

    func copySelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.copy(urls)
        status = "Copied \(count(urls.count))"
    }

    func cutSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        clipboard.cut(urls)
        status = "Cut \(count(urls.count)). Paste to move."
    }

    func paste() {
        let outcomes = clipboard.paste(into: url)
        if outcomes.isEmpty { status = "Nothing to paste."; return }
        report(outcomes, done: "Pasted \(count(outcomes.count))", failed: "paste")
        reload()
    }

    func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        report(FileOps.trash(urls), done: "Moved \(count(urls.count)) to the Trash", failed: "move to the Trash")
        reload()
    }

    func rename(_ item: FileItem, to name: String) {
        let outcome = FileOps.rename(item.url, to: name)
        report([outcome], done: "Renamed", failed: "rename")
        if let dest = outcome.destination { selection = [dest] }
        reload()
    }

    private func count(_ n: Int) -> String { n == 1 ? "1 item" : "\(n) items" }

    private func report(_ outcomes: [OpOutcome], done: String, failed verb: String) {
        let failures = outcomes.filter { !$0.succeeded }
        guard let first = failures.first else { status = done; return }
        let why = first.error?.localizedDescription ?? "unknown error"
        status = "Couldn\u{2019}t \(verb) \(first.source.lastPathComponent): \(why)"
            + (failures.count > 1 ? " (and \(failures.count - 1) more)" : "")
    }
}
```

- [ ] **Step 3: Write `AddressBar.swift`**

```swift
import SwiftUI
import FilesCore

struct AddressBar: View {
    @Bindable var model: BrowserModel
    @State private var editing = false
    @State private var text = ""
    @State private var shakes = 0.0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if editing {
                TextField("Path", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { if !focused { editing = false } }
            } else {
                HStack(spacing: 2) {
                    ForEach(AddressPath.breadcrumbs(model.url)) { crumb in
                        Button(crumb.name) { model.navigate(to: crumb.url) }.buttonStyle(.plain)
                        if crumb.url.path != model.url.path {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .modifier(Shake(amount: shakes))
        .onChange(of: model.addressFocusToken) { beginEditing() }
    }

    private func beginEditing() {
        text = model.url.path
        editing = true
        DispatchQueue.main.async {
            focused = true
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func commit() {
        if let target = AddressPath.resolve(text, from: model.url) {
            editing = false
            model.navigate(to: target)
        } else {
            withAnimation(.linear(duration: 0.3)) { shakes += 1 } // invalid path: shake and keep what was typed
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
```

- [ ] **Step 4: Write `BrowserView.swift`**

The list area is a temporary plain SwiftUI list. Tasks 7, 8 and 9 replace the marked blocks.

```swift
import SwiftUI
import FilesCore

struct BrowserView: View {
    @Bindable var model: BrowserModel

    var body: some View {
        // TEMPORARY (Task 9 replaces this with SidebarView in a NavigationSplitView)
        VStack(spacing: 0) {
            TopBar(model: model)
            Divider()
            ZStack {
                // TEMPORARY (Tasks 7 and 8 replace this with DetailsView / IconView)
                List(model.visible, id: \.url) { item in
                    Text(item.name).onTapGesture(count: 2) { model.open(item) }
                }
                if let m = model.displayMessage {
                    Text(m).foregroundStyle(.secondary).multilineTextAlignment(.center).padding().allowsHitTesting(false)
                }
            }
            Divider()
            StatusBar(model: model)
        }
        .frame(minWidth: 640, minHeight: 360)
    }
}

struct TopBar: View {
    @Bindable var model: BrowserModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!model.canGoBack)
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canGoForward)
            Button { model.goUp() } label: { Image(systemName: "arrow.up") }.disabled(model.url.path == "/")
            AddressBar(model: model)
            TextField("Filter", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($filterFocused)
                .onChange(of: model.filter) { model.recompute() }
                .onExitCommand { model.filter = "" }
            if model.viewMode == .icons {
                Slider(value: Binding(get: { model.zoom }, set: { model.setZoom($0) }), in: 32...256)
                    .frame(width: 110)
            }
            Picker("View", selection: Binding(get: { model.viewMode }, set: { model.setViewMode($0) })) {
                Image(systemName: "list.bullet").tag(ViewMode.details)
                Image(systemName: "square.grid.2x2").tag(ViewMode.icons)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
        }
        .buttonStyle(.borderless)
        .padding(8)
        .onChange(of: model.filterFocusToken) { filterFocused = true }
    }
}

struct StatusBar: View {
    let model: BrowserModel

    var body: some View {
        HStack {
            Text("\(model.visible.count) items" + (model.selection.isEmpty ? "" : " \u{00B7} \(model.selection.count) selected"))
            Spacer()
            if let s = model.status { Text(s).lineLimit(1) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 5: Write `AppDelegate.swift` and `main.swift`**

`Sources/BetterFiles/AppDelegate.swift`:
```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = BrowserModel()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let hosting = NSHostingController(rootView: BrowserView(model: model))
        hosting.sizingOptions = [] // the window decides its size, not the SwiftUI content
        window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.title = "BetterFiles"
        window.setFrameAutosaveName("BetterFilesMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: actions (menu items that need the model; cut/copy/paste/select-all use the responder chain instead)

    @objc private func trash() {
        if NSApp.keyWindow?.firstResponder is NSText { return } // Cmd+Delete belongs to the text field while editing
        model.trashSelection()
    }
    @objc private func reload() { model.reload() }
    @objc private func showDetails() { model.setViewMode(.details) }
    @objc private func showIcons() { model.setViewMode(.icons) }
    @objc private func back() { model.goBack() }
    @objc private func forward() { model.goForward() }
    @objc private func up() { model.goUp() }
    @objc private func focusAddress() { model.addressFocusToken += 1 }
    @objc private func focusFilter() { model.filterFocusToken += 1 }

    // MARK: menu

    private func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(); main.addItem(top)
            let menu = NSMenu(title: title); items.forEach(menu.addItem); top.submenu = menu
        }
        func item(_ title: String, _ action: Selector, _ key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        let upKey = String(UnicodeScalar(NSUpArrowFunctionKey)!)

        add("BetterFiles", [
            item("About BetterFiles", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide BetterFiles", #selector(NSApplication.hide(_:)), "h"),
            item("Quit BetterFiles", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            item("Move to Trash", #selector(trash), "\u{8}", target: self),
            item("Reload", #selector(reload), "r", target: self),
        ])
        add("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("View", [
            item("Details", #selector(showDetails), "1", target: self),
            item("Icons", #selector(showIcons), "2", target: self),
        ])
        add("Go", [
            item("Back", #selector(back), "[", target: self),
            item("Forward", #selector(forward), "]", target: self),
            item("Enclosing Folder", #selector(up), upKey, target: self),
            .separator(),
            item("Address Bar", #selector(focusAddress), "l", target: self),
            item("Filter", #selector(focusFilter), "f", target: self),
        ])
        add("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = main
    }
}
```

`Sources/BetterFiles/main.swift`:
```swift
import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
```

- [ ] **Step 6: Build and run**

Run: `swift build --product BetterFiles`
Expected: Build succeeds. Fix compile errors minimally and ledger any API-name changes.

Run (background, so the terminal stays free): `swift run BetterFiles`
Expected: a window opens at your home folder with a top bar (back/forward/up, breadcrumb bar, filter box, view picker) and a plain list of names. Double-click a folder name and the breadcrumbs update. Cmd+L turns the breadcrumbs into an editable path. Quit with Cmd+Q.

---

### Task 7: `DetailsView` and `Icons`

**Files:**
- Create: `Sources/BetterFiles/Icons.swift`
- Create: `Sources/BetterFiles/DetailsView.swift`
- Modify: `Sources/BetterFiles/BrowserView.swift` (replace the temporary `List` block)

**Interfaces:**
- Consumes: `BrowserModel` (Task 6)
- Produces:
  - `@MainActor enum Icons { static func icon(for item: FileItem) -> NSImage }`
  - `struct DetailsView: NSViewRepresentable { init(model: BrowserModel, version: Int, selection: Set<URL>, sort: Column, ascending: Bool) }`
  - `final class FileTableView: NSTableView` with closures `onOpen`, `onRename`, `onCopy`, `onCut`, `onPaste`

- [ ] **Step 1: Write `Icons.swift`**

```swift
import AppKit
import FilesCore
import UniformTypeIdentifiers

/// Icon lookups are slow, so each distinct icon (one per file type, one for folders) is fetched once.
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: FileItem) -> NSImage {
        if item.isFolder { return cached("folder") { NSWorkspace.shared.icon(for: .folder) } }
        if item.isPackage { return cached(item.url.path) { NSWorkspace.shared.icon(forFile: item.url.path) } }
        let ext = item.url.pathExtension.lowercased()
        return cached("ext:" + ext) { NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data) }
    }

    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }
}
```

- [ ] **Step 2: Write `DetailsView.swift`**

```swift
import AppKit
import SwiftUI
import FilesCore

final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onRename: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()   // Return, keypad Enter
        case 120: onRename?()    // F2
        default: super.keyDown(with: event)
        }
    }

    // Found through the responder chain by the Edit menu.
    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func cut(_ sender: Any?) { onCut?() }
    @objc func paste(_ sender: Any?) { onPaste?() }
}

struct DetailsView: NSViewRepresentable {
    let model: BrowserModel
    // These are read by the parent's body so SwiftUI calls updateNSView when any of them change.
    let version: Int
    let selection: Set<URL>
    let sort: Column
    let ascending: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = FileTableView()
        table.style = .fullWidth
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.usesAlternatingRowBackgroundColors = true
        table.autosaveName = "BetterFilesDetails"
        table.autosaveTableColumns = true

        for (column, title, width) in [(Column.name, "Name", 380.0), (.modified, "Date modified", 170),
                                       (.size, "Size", 90), (.kind, "Kind", 160)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            col.title = title
            col.width = width
            col.minWidth = 60
            col.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            table.addTableColumn(col)
        }
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.onOpen = { [weak model] in model?.openSelection() }
        table.onRename = { [weak c, weak table] in if let table { c?.beginRename(table) } }
        table.onCopy = { [weak model] in model?.copySelection() }
        table.onCut = { [weak model] in model?.cutSelection() }
        table.onPaste = { [weak model] in model?.paste() }
        c.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? FileTableView else { return }
        context.coordinator.update(table, version: version, selection: selection, sort: sort, ascending: ascending)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        let model: BrowserModel
        weak var table: FileTableView?
        private var items: [FileItem] = []
        private var lastVersion = -1
        private var syncing = false

        init(_ model: BrowserModel) { self.model = model }

        func update(_ table: FileTableView, version: Int, selection: Set<URL>, sort: Column, ascending: Bool) {
            syncing = true
            defer { syncing = false }
            if version != lastVersion {
                items = model.visible
                lastVersion = version
                table.reloadData()
            }
            let wanted = NSSortDescriptor(key: sort.rawValue, ascending: ascending)
            if table.sortDescriptors.first?.key != wanted.key || table.sortDescriptors.first?.ascending != ascending {
                table.sortDescriptors = [wanted]
            }
            let rows = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
            if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
        }

        // MARK: data source / delegate

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard let id = column?.identifier, let kind = Column(rawValue: id.rawValue), row < items.count else { return nil }
            let item = items[row]
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeCell(id, withIcon: kind == .name)
            switch kind {
            case .name:
                cell.imageView?.image = Icons.icon(for: item)
                cell.textField?.stringValue = item.name
                cell.textField?.delegate = self
                cell.textField?.alphaValue = item.isHidden ? 0.55 : 1
            case .modified:
                cell.textField?.stringValue = item.modified?.formatted(date: .abbreviated, time: .shortened) ?? ""
            case .size:
                cell.textField?.stringValue = item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
                cell.textField?.alignment = .right
            case .kind:
                cell.textField?.stringValue = item.kind
            }
            return cell
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            if withIcon {
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                cell.imageView = icon
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                ])
            } else {
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url : nil })
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !syncing, let d = tableView.sortDescriptors.first, let key = d.key, let column = Column(rawValue: key) else { return }
            model.setSort(column, ascending: d.ascending)
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            row < items.count ? items[row].name : nil
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            model.open(items[table.clickedRow])
        }

        // MARK: in-place rename (F2)

        func beginRename(_ table: NSTableView) {
            let row = table.selectedRow
            guard row >= 0, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            field.isEditable = true
            table.window?.makeFirstResponder(field)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let table else { return }
            field.isEditable = false
            let row = table.row(for: field)
            table.window?.makeFirstResponder(table)
            guard row >= 0, row < items.count else { return }
            let item = items[row]
            if field.stringValue != item.name { model.rename(item, to: field.stringValue) } else { field.stringValue = item.name }
        }
    }
}
```

- [ ] **Step 3: Use it in `BrowserView.swift`**

Replace the temporary `List(...)` block (the `// TEMPORARY (Tasks 7 and 8 ...)` comment and the `List`) with:
```swift
                DetailsView(model: model, version: model.version, selection: model.selection,
                            sort: model.sortColumn, ascending: model.ascending)
```

- [ ] **Step 4: Build and check**

Run: `swift build --product BetterFiles`
Expected: Build succeeds.

Run `swift run BetterFiles` and check: four columns with icons; clicking a header sorts and the arrow flips; folders stay on top; double-click opens a folder or file; Cmd+C / Cmd+X in the list then Cmd+V in another folder copies/moves (status bar says what happened); F2 edits the name in place and Return commits; Cmd+Delete trashes the selection; typing letters jumps to a name.

---

### Task 8: `IconView`, thumbnails and zoom

**Files:**
- Create: `Sources/BetterFiles/Thumbnails.swift`
- Create: `Sources/BetterFiles/IconView.swift`
- Modify: `Sources/BetterFiles/BrowserView.swift`

**Interfaces:**
- Consumes: `BrowserModel`, `Icons` (Tasks 6, 7)
- Produces: `struct IconView: NSViewRepresentable { init(model: BrowserModel, version: Int, selection: Set<URL>, zoom: Double) }`, `Thumbnails.load(url:size:completion:)`

- [ ] **Step 1: Write `Thumbnails.swift`**

```swift
import AppKit
import QuickLookThumbnailing

@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    /// Calls `completion` on the main actor with a real thumbnail if the file has one. Files without a
    /// thumbnail never call back, so the caller's file-type icon stays.
    static func load(url: URL, size: CGFloat, completion: @escaping @MainActor (NSImage) -> Void) {
        guard size >= 48 else { return } // tiny icons: the file-type icon is enough
        let bucket = Int(size / 32) * 32
        let key = "\(url.path)@\(bucket)" as NSString
        if let hit = cache.object(forKey: key) { completion(hit); return }

        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: size, height: size),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let rep else { return }
            let image = NSImage(cgImage: rep.cgImage, size: .zero)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    cache.setObject(image, forKey: key)
                    completion(image)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Write `IconView.swift`**

```swift
import AppKit
import SwiftUI
import FilesCore

final class ZoomableCollectionView: NSCollectionView {
    var onZoom: ((Double) -> Void)?
    var onOpen: (() -> Void)?
    var onRename: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { onZoom?(event.scrollingDeltaY * 2) } else { super.scrollWheel(with: event) }
    }

    override func magnify(with event: NSEvent) { onZoom?(event.magnification * 200) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()
        case 120: onRename?()
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func cut(_ sender: Any?) { onCut?() }
    @objc func paste(_ sender: Any?) { onPaste?() }
}

final class IconCell: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconCell")
    private(set) var representedURL: URL?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.wraps = true
        for sub in [icon, label] { sub.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(sub) }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            icon.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            icon.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            label.heightAnchor.constraint(lessThanOrEqualToConstant: 34),
        ])
        view = v
        imageView = icon
        textField = label
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : nil
        }
    }

    @MainActor
    func configure(_ item: FileItem, size: CGFloat) {
        representedURL = item.url
        label.stringValue = item.name
        label.alphaValue = item.isHidden ? 0.55 : 1
        icon.image = Icons.icon(for: item)
        guard !item.isFolder else { return }
        Thumbnails.load(url: item.url, size: size) { [weak self] image in
            // The cell may have been reused for another file while the thumbnail loaded.
            if self?.representedURL == item.url { self?.icon.image = image }
        }
    }
}

struct IconView: NSViewRepresentable {
    let model: BrowserModel
    let version: Int
    let selection: Set<URL>
    let zoom: Double

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let cv = ZoomableCollectionView()
        cv.collectionViewLayout = layout
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.register(IconCell.self, forItemWithIdentifier: IconCell.id)
        cv.dataSource = c
        cv.delegate = c
        cv.onZoom = { [weak model] delta in if let model { model.setZoom(model.zoom + delta) } }
        cv.onOpen = { [weak model] in model?.openSelection() }
        cv.onRename = { [weak c, weak cv] in if let cv { c?.beginRename(cv) } }
        cv.onCopy = { [weak model] in model?.copySelection() }
        cv.onCut = { [weak model] in model?.cutSelection() }
        cv.onPaste = { [weak model] in model?.paste() }
        let double = NSClickGestureRecognizer(target: c, action: #selector(Coordinator.doubleClicked(_:)))
        double.numberOfClicksRequired = 2
        double.delaysPrimaryMouseButtonEvents = false
        cv.addGestureRecognizer(double)
        c.collection = cv

        let scroll = NSScrollView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let cv = scroll.documentView as? ZoomableCollectionView else { return }
        context.coordinator.update(cv, version: version, selection: selection, zoom: zoom)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate {
        let model: BrowserModel
        weak var collection: ZoomableCollectionView?
        private var items: [FileItem] = []
        private var lastVersion = -1
        private var lastZoom = 0.0
        private var syncing = false

        init(_ model: BrowserModel) { self.model = model }

        func update(_ cv: ZoomableCollectionView, version: Int, selection: Set<URL>, zoom: Double) {
            syncing = true
            defer { syncing = false }
            var needsReload = false
            if version != lastVersion { items = model.visible; lastVersion = version; needsReload = true }
            if zoom != lastZoom {
                lastZoom = zoom
                (cv.collectionViewLayout as? NSCollectionViewFlowLayout)?.itemSize = NSSize(width: zoom + 36, height: zoom + 48)
                needsReload = true // cells must re-request thumbnails at the new size
            }
            if needsReload { cv.reloadData() }
            let wanted = Set(items.indices.filter { selection.contains(items[$0].url) }.map { IndexPath(item: $0, section: 0) })
            if cv.selectionIndexPaths != wanted { cv.selectionIndexPaths = wanted }
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = cv.makeItem(withIdentifier: IconCell.id, for: indexPath) as! IconCell
            cell.configure(items[indexPath.item], size: CGFloat(lastZoom))
            cell.textField?.delegate = self
            return cell
        }

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }
        func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }

        private func pushSelection(_ cv: NSCollectionView) {
            guard !syncing else { return }
            model.selection = Set(cv.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].url : nil })
        }

        @objc func doubleClicked(_ g: NSClickGestureRecognizer) {
            guard let cv = collection, let path = cv.indexPathForItem(at: g.location(in: cv)), path.item < items.count else { return }
            model.open(items[path.item])
        }

        func beginRename(_ cv: NSCollectionView) {
            guard let path = cv.selectionIndexPaths.first, let cell = cv.item(at: path) as? IconCell,
                  let field = cell.textField else { return }
            field.isEditable = true
            cv.window?.makeFirstResponder(field)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let cv = collection else { return }
            field.isEditable = false
            cv.window?.makeFirstResponder(cv)
            guard let path = cv.selectionIndexPaths.first, path.item < items.count else { return }
            let item = items[path.item]
            if field.stringValue != item.name { model.rename(item, to: field.stringValue) } else { field.stringValue = item.name }
        }
    }
}
```

- [ ] **Step 3: Switch between the views in `BrowserView.swift`**

Replace the `DetailsView(...)` line from Task 7 with:
```swift
                switch model.viewMode {
                case .details:
                    DetailsView(model: model, version: model.version, selection: model.selection,
                                sort: model.sortColumn, ascending: model.ascending)
                case .icons:
                    IconView(model: model, version: model.version, selection: model.selection, zoom: model.zoom)
                }
```

- [ ] **Step 4: Build and check**

Run: `swift build --product BetterFiles`
Expected: Build succeeds.

Run `swift run BetterFiles` and check: Cmd+2 shows an icon grid and Cmd+1 goes back to details; the slider and Cmd+scroll and pinch zoom between 32 and 256 pt; photos and PDFs show real thumbnails once zoomed to 48 pt or more; selection highlight follows clicks; double-click opens; F2, Cmd+C/X/V and Cmd+Delete work here too.

---

### Task 9: `SidebarView` (folder tree)

**Files:**
- Create: `Sources/BetterFiles/SidebarView.swift`
- Modify: `Sources/BetterFiles/BrowserView.swift`

**Interfaces:**
- Consumes: `BrowserModel`, `Icons`-style system icons
- Produces: `struct SidebarView: NSViewRepresentable { init(model: BrowserModel, url: URL) }` (the `url` parameter makes SwiftUI call `updateNSView` when the current folder changes)

- [ ] **Step 1: Write `SidebarView.swift`**

```swift
import AppKit
import SwiftUI
import FilesCore

final class Node: NSObject {
    let url: URL
    let name: String
    private(set) var children: [Node]?   // nil until first expanded

    init(url: URL, name: String) {
        self.url = url
        self.name = name
    }

    /// Non-hidden sub-folders, loaded on first use.
    func loadChildren() -> [Node] {
        if let children { return children }
        let folders = ((try? FolderListing.list(url)) ?? []).filter { $0.isFolder && !$0.isHidden }
        let nodes = Sorter.sort(folders, by: .name, ascending: true).map { Node(url: $0.url, name: $0.name) }
        children = nodes
        return nodes
    }
}

struct SidebarView: NSViewRepresentable {
    let model: BrowserModel
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let outline = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.dataSource = c
        outline.delegate = c
        c.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.reveal(url)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let model: BrowserModel
        weak var outline: NSOutlineView?
        private let roots: [Node]
        private var syncing = false
        private var lastRevealed: String?

        init(_ model: BrowserModel) {
            self.model = model
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var nodes = [Node(url: home, name: "Home")]
            for (folder, title) in [("Desktop", "Desktop"), ("Documents", "Documents"), ("Downloads", "Downloads")] {
                nodes.append(Node(url: home.appendingPathComponent(folder), name: title))
            }
            nodes.append(Node(url: URL(fileURLWithPath: "/Applications"), name: "Applications"))
            let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
            for v in volumes {
                let name = (try? v.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? v.lastPathComponent
                nodes.append(Node(url: v, name: name))
            }
            roots = nodes
        }

        // MARK: data source

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? Node else { return roots.count }
            return node.loadChildren().count
        }

        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? Node else { return roots[index] }
            return node.loadChildren()[index]
        }

        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            return node.children.map { !$0.isEmpty } ?? true
        }

        // MARK: delegate

        func outlineView(_ ov: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let id = NSUserInterfaceItemIdentifier("node")
            let cell = (ov.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = id
                let icon = NSImageView(), text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingTail
                for sub in [icon, text] { sub.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(sub) }
                c.imageView = icon
                c.textField = text
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    icon.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = node.name
            cell.imageView?.image = NSWorkspace.shared.icon(for: .folder)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let ov = outline, ov.selectedRow >= 0, let node = ov.item(atRow: ov.selectedRow) as? Node else { return }
            lastRevealed = node.url.path // we are already there; no need to re-reveal
            model.navigate(to: node.url)
        }

        // MARK: follow the current folder

        func reveal(_ target: URL) {
            guard let ov = outline else { return }
            let path = target.standardizedFileURL.path
            guard path != lastRevealed else { return }
            lastRevealed = path

            func contains(_ root: Node) -> Bool {
                let r = root.url.standardizedFileURL.path
                return path == r || path.hasPrefix(r == "/" ? "/" : r + "/")
            }
            guard let root = roots.filter(contains).max(by: { $0.url.path.count < $1.url.path.count }) else {
                syncing = true; ov.deselectAll(nil); syncing = false
                return
            }
            var node = root
            ov.expandItem(root)
            let relative = path.dropFirst(root.url.standardizedFileURL.path == "/" ? 1 : root.url.standardizedFileURL.path.count)
            for part in relative.split(separator: "/") {
                guard let next = node.loadChildren().first(where: { $0.name == String(part) }) else { break }
                ov.expandItem(next)
                node = next
            }
            let row = ov.row(forItem: node)
            if row >= 0 {
                syncing = true
                ov.selectRowIndexes([row], byExtendingSelection: false)
                ov.scrollRowToVisible(row)
                syncing = false
            }
        }
    }
}
```

- [ ] **Step 2: Put the sidebar in the window (`BrowserView.swift`)**

Replace the `body` of `BrowserView` with:
```swift
    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, url: model.url)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
        } detail: {
            VStack(spacing: 0) {
                TopBar(model: model)
                Divider()
                ZStack {
                    switch model.viewMode {
                    case .details:
                        DetailsView(model: model, version: model.version, selection: model.selection,
                                    sort: model.sortColumn, ascending: model.ascending)
                    case .icons:
                        IconView(model: model, version: model.version, selection: model.selection, zoom: model.zoom)
                    }
                    if let m = model.displayMessage {
                        Text(m).foregroundStyle(.secondary).multilineTextAlignment(.center).padding().allowsHitTesting(false)
                    }
                }
                Divider()
                StatusBar(model: model)
            }
        }
        .frame(minWidth: 800, minHeight: 400)
    }
```

- [ ] **Step 3: Build and check**

Run: `swift build --product BetterFiles`
Expected: Build succeeds.

Run `swift run BetterFiles` and check: the tree shows Home, Desktop, Documents, Downloads, Applications and your disk; clicking a folder opens it; the disclosure arrows expand lazily; opening a deep folder from the address bar expands the tree down to it and highlights it; clicking a breadcrumb or pressing Cmd+Up moves the highlight.

---

### Task 10: Full verification and the manual smoke test

**Files:**
- Modify: `PROGRESS.md`, `CHANGELOG.md`

- [ ] **Step 1: Run the whole suite and a clean build**

Run: `swift test && swift build`
Expected: all tests pass (about 60), both products build, no errors.

- [ ] **Step 2: Manual smoke test (the user runs this)**

Run: `swift run BetterFiles`

Check each of these:
1. **Opens at Home** with the tree, top bar and a details list. Hidden files (like `.zshrc`) and extensions are visible.
2. **Sort:** click each of the four headers, twice each. Folders stay on top; arrows flip. Quit and relaunch: the same sort and view come back.
3. **Address bar:** Cmd+L, type `~/Documents`, Return. Then Cmd+L, type `/nonexistent`, Return: the bar shakes and keeps your text. Esc cancels. Paste a path with quotes around it: it works.
4. **Breadcrumbs, back, forward, up:** Cmd+[, Cmd+], Cmd+Up and the toolbar buttons all work; the tree highlight follows.
5. **Cut and paste (the main event):** make two folders on the Desktop. Put a file in the first. Select it, Cmd+X, open the second, Cmd+V: the file moved (gone from the first). Repeat with Cmd+C: the file is in both. Paste again: a `name copy` appears.
6. **Stale cut:** Cmd+X a file, then Cmd+C a different file, paste elsewhere: the second file is copied and the first stays put.
7. **Trash:** select a file, Cmd+Delete: it's in the Trash and nothing is permanently deleted. Cmd+Delete while typing in the filter box does nothing to files.
8. **Rename:** F2 in both views, change the name, Return. Change only the case (`a.txt` to `A.txt`): it works. Rename to an existing name: the status bar says it already exists.
9. **Filter:** Cmd+F, type part of a name: the list narrows instantly; Esc clears it.
10. **Icon view:** Cmd+2; slider, Cmd+scroll and pinch zoom; photos and PDFs show thumbnails when zoomed in; Cmd+1 goes back.
11. **Big folder:** open `/usr/lib` or a folder with thousands of files. Scrolling is smooth.
12. **Review Focus 5 (race):** click folders in the tree very fast, ending on a different folder than where you started. The list and breadcrumbs end on the last one you clicked.
13. **Permissions:** open a folder macOS protects (try `/Library/Application Support/com.apple.TCC`). A clear message appears and the app doesn't crash.
14. **Read-only target:** try pasting a file into a read-only folder. The status bar names the failure; nothing else breaks.

Expected: all 14 behave as described. Report any that don't.

- [ ] **Step 3: Update `PROGRESS.md` and `CHANGELOG.md`**

In `PROGRESS.md`, add a "Part 2: BetterFiles Stage A" section under Done (core browser built, smoke test pending) and tick the matching items under Remaining; link the Stage A spec and this plan. In `CHANGELOG.md` under `[Unreleased] / Added`, add: `BetterFiles Stage A: Explorer-style file manager (folder tree, address bar with breadcrumbs, details and zoomable icon views, filter, Cut+Paste-to-move, Trash). FilesCore library with tests.` Also add under Added the launcher changes: glass panel with animation, fast word-prefix search, app index, usage-history candidates.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(files): BetterFiles Stage A app (tree, details, icons, address bar, cut/paste)

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
Do not push unless asked.

---

## Self-review notes

- **Spec coverage:** FileItem/FolderListing (T1), Sorter/Filter (T2), AddressPath (T3), FileOps (T4), FileClipboard + protocol (T5), BrowserModel/AddressBar/FilterField/shortcuts/persistence/errors (T6), DetailsView (T7), IconView + zoom + thumbnails (T8), Sidebar tree (T9), manual checklist (T10). Spec "Known ceilings" (no folder watching) is honoured: reload after every operation and on Cmd+R.
- **Spec deviations (listed in "Decisions this plan adds"):** `isPackage` on `FileItem`, `Crumb` struct, tree shows non-hidden folders only, copy clashes always use "copy" naming.
- **Type check:** `Column` (T2) is used by `BrowserModel.setSort` (T6) and the table columns (T7). `OpOutcome.succeeded/destination/error` (T4) are used by `FileClipboard` (T5) and `BrowserModel.report` (T6). `PasteboardProtocol` (T5) is implemented by `SystemPasteboard` (T6). `FileTableView`/`ZoomableCollectionView` closures match the `BrowserModel` method names (`openSelection`, `copySelection`, `cutSelection`, `paste`).
- **Known risk:** the AppKit layer is not unit-tested; SDK API names may need small fixes at build time. Ledger each fix.
