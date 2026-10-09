import AppKit
import LauncherCore
import Observation

/// One line in the launcher: a file/app (has `path`) or an action such as an answer or clipboard item (has `run`).
struct LRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    var path: String? = nil
    var symbol: String? = nil
    var kind = ""
    var isFolder = false
    var run: (() -> Void)? = nil
}

@MainActor @Observable
final class Model {
    var text = ""
    var rows: [LRow] = []
    var selected = 0
    var visible = false
    var onDismiss: () -> Void = {}

    @ObservationIgnored private let search = Search()
    @ObservationIgnored private let usage: Usage
    @ObservationIgnored private let clips = ClipboardHistory()
    @ObservationIgnored private let index = FileIndex()
    @ObservationIgnored private var usageItems: [Candidate] = []   // history that still exists, checked off the main thread
    @ObservationIgnored private var apps: [Candidate] = []
    @ObservationIgnored private var base: [Candidate] = []   // apps + history: instant, no Spotlight
    @ObservationIgnored private var raw: [Candidate] = []    // streamed Spotlight hits
    @ObservationIgnored private var indexed: [Candidate] = [] // our own index
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(usage: Usage) {
        self.usage = usage
        search.onResults = { [weak self] candidates in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.raw = candidates
                self.rerank()
            }
        }
        clips.start()
        refreshApps()
        refreshIndex()
        refreshUsage()
    }

    func textChanged() {
        rerank(keepSelection: false) // instant: apps + history
        // Restarting queries is the expensive part; wait out fast typing / held backspace.
        searchTask?.cancel()
        let q = text
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, let self else { return }
            guard LSettings.shared.searchFiles, !PathQuery.isPath(q) else { return }
            // Our own index covers the home folder; Spotlight is only a fallback until the first scan finishes.
            if !self.index.isReady { self.search.update(q) }
            let hits = await Task.detached { self.index.search(q) }.value
            guard !Task.isCancelled else { return }
            self.indexed = hits
            self.rerank()
        }
    }

    func move(_ delta: Int) {
        guard !rows.isEmpty else { return }
        selected = (selected + delta + rows.count) % rows.count
    }

    private var selectedRow: LRow? { rows.indices.contains(selected) ? rows[selected] : nil }

    /// Text after the last "/" in path mode, else the whole query: what to highlight in titles.
    var highlight: String {
        let t = text.trimmingCharacters(in: .whitespaces)
        return PathQuery.isPath(t) ? String(t.split(separator: "/", omittingEmptySubsequences: false).last ?? "") : t
    }

    /// True when the highlighted row is a file, app or folder (not an answer or other action).
    var selectedIsFile: Bool { selectedRow?.path != nil }

    var pathMode: Bool { PathQuery.isPath(text) }

    // MARK: actions (each works on any row so the right-click menu can use them too)

    /// Dismisses first so the panel never waits on the target app; the open happens off the main thread.
    /// Folders open in Butterfinder; `reveal` shows the item's folder there with the item selected.
    func open(_ row: LRow, reveal: Bool = false) {
        if let run = row.run { run(); onDismiss(); return }
        guard let path = row.path else { return }
        usage.record(path: path)
        refreshUsage()
        onDismiss()
        Task.detached {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            let isFolder = exists && isDir.boolValue && !path.hasSuffix(".app")
            if reveal || isFolder {
                FilesBridge.show(path, select: reveal)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        }
    }

    func openSelected(reveal: Bool = false) { if let r = selectedRow { open(r, reveal: reveal) } }

    /// Tab in path mode: fill in the highlighted entry (and step into it if it's a folder).
    func completeSelected() -> Bool {
        guard pathMode, let row = selectedRow, let path = row.path else { return false }
        text = path + (row.isFolder ? "/" : "")
        return true
    }

    func copyPath(_ row: LRow) { if let p = row.path { Self.copy(p); onDismiss() } }
    func copyName(_ row: LRow) { if let p = row.path { Self.copy((p as NSString).lastPathComponent); onDismiss() } }

    func revealInFinder(_ row: LRow) {
        guard let p = row.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        onDismiss()
    }

    func openInTerminal(_ row: LRow) {
        guard let path = row.path else { return }
        let folder = row.isFolder ? path : (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
        onDismiss()
    }

    func appsFor(_ row: LRow) -> [URL] {
        guard let p = row.path else { return [] }
        return Array(NSWorkspace.shared.urlsForApplications(toOpen: URL(fileURLWithPath: p)).prefix(12))
    }

    func openWith(_ row: LRow, _ app: URL) {
        guard let p = row.path else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: p)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        onDismiss()
    }

    func canForget(_ row: LRow) -> Bool { row.path.map { usage.get($0) != nil } ?? false }

    func forget(_ row: LRow) {
        guard let p = row.path else { return }
        usage.forget(p)
        usageItems.removeAll { $0.path == p }
        base = apps + usageItems
        rerank()
    }

    /// Moves to the Trash (recoverable) and drops it from the list at once.
    func trash(_ row: LRow) {
        guard let path = row.path else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        usage.forget(path)
        raw.removeAll { $0.path == path }
        indexed.removeAll { $0.path == path }
        base.removeAll { $0.path == path }
        rerank()
    }

    // Keyboard shortcuts act on the highlighted row.
    func copyPathOfSelected() { if let r = selectedRow { copyPath(r) } }
    func openSelectedInTerminal() { if let r = selectedRow { openInTerminal(r) } }
    func trashSelected() { if let r = selectedRow { trash(r) } }

    func jump(to number: Int) {
        guard rows.indices.contains(number - 1) else { return }
        selected = number - 1
        openSelected()
    }

    /// Called when the panel opens.
    func reset() {
        text = ""
        raw = []
        indexed = []
        rows = []
        selected = 0
        base = apps + usageItems   // no disk access here: opening must feel instant
        refreshApps()
        if index.isStale() { refreshIndex() }
    }

    /// Called once the panel is fully hidden: stop the live query so it doesn't run in the background.
    func didHide() {
        search.stop()
        raw = []
        indexed = []
    }

    /// Checking that each remembered path still exists touches the disk, so it happens in the background.
    private func refreshUsage() {
        let snapshot = usage.paths   // taken here on the main thread; only the disk checks run in the background
        Task.detached(priority: .utility) {
            let items = Usage.candidates(paths: snapshot)
            await MainActor.run { self.usageItems = items; self.base = self.apps + items }
        }
    }

    private func refreshApps() {
        Task.detached {
            let found = AppIndex.scan()
            await MainActor.run { self.apps = found; self.base = found + self.usageItems }
        }
    }

    private func refreshIndex() {
        let index = self.index
        Task.detached(priority: .utility) { index.build(root: NSHomeDirectory()) }
    }

    // MARK: building rows

    private func actionRows() -> [LRow] {
        let q = text.trimmingCharacters(in: .whitespaces)
        if let url = WebTarget.url(for: q) {
            return [LRow(id: "web-open", title: "Open \(url.absoluteString)", subtitle: "Return to open in your browser",
                         symbol: "network", run: { NSWorkspace.shared.open(url) })]
        }
        if LSettings.shared.calculator, let answer = Calc.answer(q) {
            let value = answer.split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? answer
            return [LRow(id: "calc", title: answer, subtitle: "Return to copy the answer", symbol: "equal.circle.fill",
                         run: { Self.copy(value.split(separator: " ").first.map(String.init) ?? value) })]
        }
        return []
    }

    private static func fileRow(_ c: Candidate, subtitle: String) -> LRow {
        var kind = "File", folder = false
        var isDir: ObjCBool = false
        if c.isApp || c.path.hasSuffix(".app") { kind = "Application" }
        else if FileManager.default.fileExists(atPath: c.path, isDirectory: &isDir), isDir.boolValue { kind = "Folder"; folder = true }
        else { let ext = (c.path as NSString).pathExtension.uppercased(); if !ext.isEmpty { kind = ext } }
        return LRow(id: c.path, title: c.name, subtitle: subtitle, path: c.path, kind: kind, isFolder: folder)
    }

    private static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private var clipMode: String? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t == "clip" { return "" }
        return t.hasPrefix("clip ") ? String(t.dropFirst(5)) : nil
    }

    // Live updates keep the user's highlighted row; a new query starts at the top.
    private func rerank(keepSelection: Bool = true) {
        let previous = keepSelection ? selectedRow?.id : nil
        var out: [LRow]
        if let (dir, items) = PathQuery.entries(for: text) {
            // Typing a path browses folders instead of searching.
            out = items.map { Self.fileRow($0, subtitle: (dir as NSString).abbreviatingWithTildeInPath) }
            if out.isEmpty {
                out = [LRow(id: "nopath", title: "Nothing in \((dir as NSString).abbreviatingWithTildeInPath) matches", subtitle: "Keep typing, or press Esc",
                            symbol: "questionmark.folder")]
            }
        } else if LSettings.shared.clipboard, let filter = clipMode {
            out = clips.items.filter { filter.isEmpty || $0.lowercased().contains(filter) }.prefix(8).enumerated().map { i, item in
                LRow(id: "clip\(i)\(item.hashValue)", title: item.replacingOccurrences(of: "\n", with: " "), subtitle: "Return to copy again",
                     symbol: "doc.on.clipboard", run: { Self.copy(item) })
            }
        } else {
            var seen = Set<String>()
            let all = (base + (LSettings.shared.searchFiles ? raw + indexed : [])).filter { seen.insert($0.path).inserted }
            let files = Ranker.rank(query: text, candidates: all, usage: usage.get, limit: LSettings.shared.maxResults)
            out = actionRows() + files.map { Self.fileRow($0, subtitle: ($0.parent as NSString).abbreviatingWithTildeInPath) }
            let q = text.trimmingCharacters(in: .whitespaces)
            if out.isEmpty, LSettings.shared.webFallback, q.count >= 2, let url = URL(string: "https://www.google.com/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)) {
                out = [LRow(id: "web", title: "Search the web for \u{201C}\(q)\u{201D}", subtitle: "Return to open in your browser",
                            symbol: "globe", run: { NSWorkspace.shared.open(url) })]
            }
        }
        rows = out
        selected = previous.flatMap { id in out.firstIndex { $0.id == id } } ?? 0
    }
}
