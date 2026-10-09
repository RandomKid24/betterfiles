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
    }

    func textChanged() {
        rerank(keepSelection: false) // instant: apps + history
        // Restarting queries is the expensive part; wait out fast typing / held backspace.
        searchTask?.cancel()
        let q = text
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, let self else { return }
            guard LSettings.shared.searchFiles else { return }
            self.search.update(q)
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

    /// Dismisses first so the panel never waits on the target app; the open happens off the main thread.
    /// Folders open in BetterFiles; `reveal` shows the item's folder there with the item selected.
    func openSelected(reveal: Bool = false) {
        guard let row = selectedRow else { return }
        if let run = row.run { run(); onDismiss(); return }
        guard let path = row.path else { return }
        usage.record(path: path)
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

    // Option+Return, Shift+Return: quick actions on the highlighted file.
    func copyPathOfSelected() {
        guard let path = selectedRow?.path else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        onDismiss()
    }

    func openSelectedInTerminal() {
        guard let path = selectedRow?.path else { return }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let folder = isDir.boolValue && !path.hasSuffix(".app") ? path : (path as NSString).deletingLastPathComponent
        NSWorkspace.shared.open([URL(fileURLWithPath: folder)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
        onDismiss()
    }

    func trashSelected() {
        guard let path = selectedRow?.path else { return }
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
        raw.removeAll { $0.path == path }
        indexed.removeAll { $0.path == path }
        base.removeAll { $0.path == path }
        rerank()
    }

    /// Called when the panel opens.
    func reset() {
        text = ""
        raw = []
        indexed = []
        rows = []
        selected = 0
        base = apps + usage.candidates()
        refreshApps()
        if index.isStale() { refreshIndex() }
    }

    /// Called once the panel is fully hidden: stop the live query so it doesn't run in the background.
    func didHide() {
        search.stop()
        raw = []
        indexed = []
    }

    private func refreshApps() {
        Task.detached {
            let found = AppIndex.scan()
            await MainActor.run { self.apps = found; if self.base.isEmpty { self.base = found } }
        }
    }

    private func refreshIndex() {
        let index = self.index
        Task.detached(priority: .utility) { index.build(root: NSHomeDirectory()) }
    }

    // MARK: building rows

    private func actionRows() -> [LRow] {
        let q = text.trimmingCharacters(in: .whitespaces)
        if LSettings.shared.calculator, let answer = Calc.answer(q) {
            let value = answer.split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? answer
            return [LRow(id: "calc", title: answer, subtitle: "Return to copy the answer", symbol: "equal.circle.fill",
                         run: { Self.copy(value.split(separator: " ").first.map(String.init) ?? value) })]
        }
        return []
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
        if LSettings.shared.clipboard, let filter = clipMode {
            out = clips.items.filter { filter.isEmpty || $0.lowercased().contains(filter) }.prefix(8).enumerated().map { i, item in
                LRow(id: "clip\(i)\(item.hashValue)", title: item.replacingOccurrences(of: "\n", with: " "), subtitle: "Return to copy again",
                     symbol: "doc.on.clipboard", run: { Self.copy(item) })
            }
        } else {
            var seen = Set<String>()
            let all = (base + (LSettings.shared.searchFiles ? raw + indexed : [])).filter { seen.insert($0.path).inserted }
            let files = Ranker.rank(query: text, candidates: all, usage: usage.get, limit: LSettings.shared.maxResults)
            out = actionRows() + files.map { LRow(id: $0.path, title: $0.name, subtitle: $0.parent, path: $0.path) }
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
