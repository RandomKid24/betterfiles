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
            items = []; visible = []; message = nil
            version += 1
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
