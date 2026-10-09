import AppKit
import FilesCore
import Observation

enum ViewMode: String { case details, icons }

@MainActor @Observable
final class BrowserModel: Identifiable {
    private(set) var url: URL
    private(set) var visible: [FileItem] = []
    private(set) var version = 0   // bumps whenever `visible` changes, so AppKit views know to reload
    private(set) var message: String?
    var status: String?
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
    var showInfo = false
    var infoURLs: [URL] = []
    var showBatchRename = false
    var batchItems: [FileItem] = []
    @ObservationIgnored var onActivate: () -> Void = {}   // set by the tab: marks this pane as the active one
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private static let undoStack = UndoStack()
    @ObservationIgnored private static var busy = false

    @ObservationIgnored var pendingRename: URL?   // set by newFolder; the active view starts renaming it once it appears
    @ObservationIgnored private var items: [FileItem] = []
    @ObservationIgnored private var loadID = 0
    // Shared so Cut in one tab can Paste in another.
    @ObservationIgnored private static let sharedClipboard = FileClipboard(pasteboard: SystemPasteboard())
    @ObservationIgnored private var clipboard: FileClipboard { Self.sharedClipboard }
    @ObservationIgnored private let defaults = UserDefaults.standard

    init(start: URL = FileManager.default.homeDirectoryForCurrentUser) {
        url = start
        let d = UserDefaults.standard
        sortColumn = Column(rawValue: d.string(forKey: "sortColumn") ?? "") ?? .name
        ascending = d.object(forKey: "ascending") as? Bool ?? true
        viewMode = ViewMode(rawValue: d.string(forKey: "viewMode") ?? "") ?? .details
        zoom = d.object(forKey: "zoom") as? Double ?? 96
        reload()
        watch()
    }

    var showPreview: Bool { Prefs.shared.showPreview }

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
            items = []; visible = []; message = nil
            version += 1
            watch()
        }
        reload()
    }

    private func watch() {
        watcher = FolderWatcher(url: url) { [weak self] in self?.externalChange() }
    }

    /// Something else changed this folder. Wait if the user is typing so a reload can't disturb an edit.
    private func externalChange() {
        if NSApp.keyWindow?.firstResponder is NSText {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.externalChange() }
        } else {
            reload()
        }
    }

    /// Called by the launcher: show `path` (a folder), or with `select` its folder with it highlighted.
    func show(path: String, select: Bool) {
        let target = URL(fileURLWithPath: path)
        if select {
            navigate(to: target.deletingLastPathComponent())
            selection = [target.standardizedFileURL]
        } else {
            navigate(to: target)
        }
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

    func togglePreview() { Prefs.shared.showPreview.toggle() }

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

    /// Runs slow file work off the main thread so the window never freezes. One job at a time.
    private func background(_ working: String, _ work: @escaping () -> [OpOutcome], done: @escaping ([OpOutcome]) -> Void) {
        guard !Self.busy else { status = "Still working\u{2026}"; return }
        Self.busy = true
        status = working
        Task.detached {
            let out = work()
            await MainActor.run {
                Self.busy = false
                done(out)
                self.reload()
            }
        }
    }

    /// A paste either moved things (sources are gone) or copied them (sources remain).
    private func recordPaste(_ out: [OpOutcome]) {
        let fm = FileManager.default
        Self.undoStack.recordMoves("paste", out.filter { !fm.fileExists(atPath: $0.source.path) })
        Self.undoStack.recordCreated("paste", out.filter { fm.fileExists(atPath: $0.source.path) })
    }

    func paste() {
        let target = url
        let clip = clipboard
        background("Pasting\u{2026}", { clip.paste(into: target) }) { out in
            if out.isEmpty { self.status = "Nothing to paste."; return }
            self.recordPaste(out)
            self.report(out, done: "Pasted \(self.count(out.count))", failed: "paste")
        }
    }

    func trashSelection() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        background("Moving to the Trash\u{2026}", { FileOps.trash(urls) }) { out in
            Self.undoStack.recordMoves("move to Trash", out)
            self.report(out, done: "Moved \(self.count(urls.count)) to the Trash", failed: "move to the Trash")
        }
    }

    func drop(_ urls: [URL], onto folder: URL, copy: Bool) {
        guard !urls.isEmpty else { return }
        background(copy ? "Copying\u{2026}" : "Moving\u{2026}", { copy ? FileOps.copy(urls, to: folder) : FileOps.move(urls, to: folder) }) { out in
            if copy { Self.undoStack.recordCreated("copy", out) } else { Self.undoStack.recordMoves("move", out) }
            self.report(out, done: (copy ? "Copied " : "Moved ") + self.count(urls.count) + " to " + folder.lastPathComponent,
                        failed: copy ? "copy" : "move")
        }
    }

    func compress() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        background("Compressing\u{2026}", { [Archive.compress(urls)] }) { out in
            Self.undoStack.recordCreated("compress", out)
            if let dest = out.first?.destination { self.selection = [dest] }
            self.report(out, done: "Created \(out.first?.destination?.lastPathComponent ?? "archive")", failed: "compress")
        }
    }

    func extract() {
        let zips = selectedItems.map(\.url).filter { $0.pathExtension.lowercased() == "zip" }
        guard !zips.isEmpty else { return }
        background("Extracting\u{2026}", { zips.map(Archive.extract) }) { out in
            Self.undoStack.recordCreated("extract", out)
            self.report(out, done: "Extracted \(self.count(zips.count))", failed: "extract")
        }
    }

    func quickLook() { QuickLook.shared.toggle(selectedItems.map(\.url)) }

    func undo() {
        status = Self.undoStack.undo() ?? "Nothing to undo."
        reload()
    }

    func newFolder() {
        let outcome = FileOps.newFolder(in: url)
        Self.undoStack.recordCreated("new folder", [outcome])
        report([outcome], done: "Created folder", failed: "create folder")
        if let dest = outcome.destination { selection = [dest]; pendingRename = dest }
        reload()
    }

    func rename(_ item: FileItem, to name: String) {
        let outcome = FileOps.rename(item.url, to: name)
        Self.undoStack.recordMoves("rename", [outcome])
        report([outcome], done: "Renamed", failed: "rename")
        if let dest = outcome.destination { selection = [dest] }
        reload()
    }

    func applyBatchRename(base: String, start: Int) {
        let plan = BatchRename.plan(batchItems.map(\.url), base: base, start: start)
        let out = plan.map { FileOps.rename($0.url, to: $0.newName) }
        Self.undoStack.recordMoves("rename", out)
        report(out, done: "Renamed \(count(out.count))", failed: "rename")
        selection = Set(out.compactMap(\.destination))
        reload()
    }

    // MARK: small helpers (paths, Terminal, sidebar, info)

    func copyPath() {
        let paths = (selection.isEmpty ? [url] : selectedItems.map(\.url)).map(\.path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        status = paths.count == 1 ? "Copied path" : "Copied \(paths.count) paths"
    }

    func openTerminal() {
        let folder = selectedItems.count == 1 && selectedItems[0].isFolder ? selectedItems[0].url : url
        NSWorkspace.shared.open([folder], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func addToSidebar() {
        let folders = selectedItems.filter(\.isFolder)
        (folders.isEmpty ? [FileItem(url: url, isFolder: true)] : folders).forEach { Favorites.shared.add($0.url) }
        status = "Added to the sidebar"
    }

    func getInfo() {
        infoURLs = selection.isEmpty ? [url] : selectedItems.map(\.url)
        showInfo = true
    }

    func beginBatchRename() {
        guard selectedItems.count > 1 else { return }
        batchItems = selectedItems
        showBatchRename = true
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
