import AppKit
import Darwin
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

    @ObservationIgnored private let names = NameSearch()
    @ObservationIgnored private let usage: Usage
    @ObservationIgnored private let clips = ClipboardHistory()
    @ObservationIgnored private let index = FileIndex()
    @ObservationIgnored private var usageItems: [Candidate] = []   // history that still exists, checked off the main thread
    @ObservationIgnored private var apps: [Candidate] = []
    @ObservationIgnored private var base: [Candidate] = []   // apps + history: instant, no Spotlight
    @ObservationIgnored private var raw: [Candidate] = []    // streamed Spotlight hits
    @ObservationIgnored private var indexed: [Candidate] = [] // our own index
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var contentTask: Task<Void, Never>?
    @ObservationIgnored private var contentHits: [Candidate] = []
    @ObservationIgnored private var contentSearching = false
    @ObservationIgnored private var protectedCheckAnswered = false
    @ObservationIgnored private var canReadProtected = true   // can we list Documents, Desktop and Downloads? (macOS privacy)

    init(usage: Usage) {
        self.usage = usage
        clips.start()
        refreshApps()
        refreshIndex()
        refreshUsage()
        checkProtectedFolders()
    }

    /// macOS hides Documents, Desktop and Downloads from apps until you allow it, and an unanswered permission dialog makes
    /// the first access hang. So the check runs in the background, and silence for two seconds counts as "blocked".
    private func checkProtectedFolders() {
        Task.detached(priority: .utility) {
            let home = NSHomeDirectory()
            let ok = ["Documents", "Desktop", "Downloads"].allSatisfy {
                (try? FileManager.default.contentsOfDirectory(atPath: home + "/" + $0)) != nil
            }
            await MainActor.run { self.protectedCheckAnswered = true; self.applyProtected(ok) }
        }
        protectedCheckAnswered = false
        Task {
            try? await Task.sleep(for: .seconds(2))
            if !self.protectedCheckAnswered { self.applyProtected(false) }
        }
    }

    private func applyProtected(_ ok: Bool) {
        let newlyAllowed = ok && !canReadProtected
        let changed = ok != canReadProtected
        canReadProtected = ok
        if changed { rerank() }
        if newlyAllowed { refreshIndex() }   // include the folders that were hidden
    }

    func textChanged() {
        rerank(keepSelection: false) // instant: apps + history
        // Restarting queries is the expensive part; wait out fast typing / held backspace.
        searchTask?.cancel()
        contentTask?.cancel()
        if let q = contentQuery {
            // "? words": search inside files. Spotlight's content index can take a moment, so show that we're working.
            contentHits = []
            contentSearching = q.count >= 2
            rerank(keepSelection: false)
            guard q.count >= 2 else { return }
            contentTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let hits = await Task.detached { ContentSearch.run(q) }.value
                guard !Task.isCancelled, let self else { return }
                self.contentHits = hits
                self.contentSearching = false
                self.rerank()
            }
            return
        }
        let q = text
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(70))
            guard !Task.isCancelled, let self else { return }
            guard LSettings.shared.searchFiles, !PathQuery.isPath(q) else { return }
            // Layer 1: our small in-memory index (instant). Layer 2: Spotlight's name search (complete), off the main thread.
            let hits = await Task.detached { self.index.search(q) }.value
            guard !Task.isCancelled else { return }
            self.indexed = hits
            self.rerank()
            let spot = await Task.detached { self.names.run(q) }.value
            guard !Task.isCancelled else { return }
            self.raw = spot
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

    /// The words after "? " when searching file contents, "" for a bare "?".
    private var contentQuery: String? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "?" { return "" }
        return t.hasPrefix("? ") ? String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces) : nil
    }

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
        contentHits = []
        contentSearching = false
        rows = []
        selected = 0
        base = apps + usageItems   // no disk access here: opening must feel instant
        if !canReadProtected { checkProtectedFolders() }
        refreshApps()
        if index.isStale() { refreshIndex() }
    }

    /// Called once the panel is fully hidden: stop the live query so it doesn't run in the background.
    func didHide() {
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

    /// Quick commands typed as whole words: "lock", "sleep", "dark mode", "uuid", "timestamp", "ip".
    private func quickRows(_ q: String) -> [LRow] {
        func row(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ run: @escaping () -> Void) -> [LRow] {
            [LRow(id: "quick-" + id, title: title, subtitle: subtitle, symbol: symbol, run: run)]
        }
        switch q.lowercased() {
        case "lock", "lock screen":
            return row("lock", "Lock Screen", "Turns the display off; your password is asked on wake", "lock") { Self.shell("/usr/bin/pmset", ["displaysleepnow"]) }
        case "sleep":
            return row("sleep", "Sleep", "Puts the Mac to sleep", "moon.zzz") { Self.shell("/usr/bin/pmset", ["sleepnow"]) }
        case "dark mode", "toggle dark mode", "light mode":
            return row("dark", "Toggle Dark Mode", "Switches between light and dark appearance", "circle.lefthalf.filled") {
                Self.shell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode"])
            }
        case "uuid", "guid":
            let id = UUID().uuidString.lowercased()
            return row("uuid", id, "A new UUID: Return to copy", "number") { Self.copy(id) }
        case "timestamp", "unix time", "epoch", "now":
            let t = String(Int(Date().timeIntervalSince1970))
            let iso = ISO8601DateFormatter().string(from: Date())
            return row("time", t, "Unix time (\(iso)): Return to copy", "clock") { Self.copy(t) }
        case "ip", "my ip", "ip address", "local ip":
            guard let ip = Self.localIP() else { return [] }
            return row("ip", ip, "Your local IP address: Return to copy", "network") { Self.copy(ip) }
        default:
            return []
        }
    }

    private static func shell(_ tool: String, _ args: [String]) {
        Task.detached { let p = Process(); p.executableURL = URL(fileURLWithPath: tool); p.arguments = args; try? p.run() }
    }

    /// The first IPv4 address on a Wi-Fi or Ethernet interface.
    private static func localIP() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return nil }
        defer { freeifaddrs(list) }
        var cursor = list
        while let entry = cursor {
            let i = entry.pointee
            if let addr = i.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: i.ifa_name).hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return String(cString: host)
            }
            cursor = i.ifa_next
        }
        return nil
    }

    private func actionRows() -> [LRow] {
        let q = text.trimmingCharacters(in: .whitespaces)
        if let s = WebTarget.shortcut(for: q) {
            return [LRow(id: "shortcut", title: s.title, subtitle: "Return to open in your browser", symbol: "magnifyingglass.circle", run: { NSWorkspace.shared.open(s.url) })]
        }
        let quick = quickRows(q)
        if !quick.isEmpty { return quick }
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
        if let q = contentQuery {
            if contentSearching {
                out = [LRow(id: "searching", title: "Searching inside files for \u{201C}\(q)\u{201D}\u{2026}", subtitle: "Uses Spotlight's content index", symbol: "text.magnifyingglass")]
            } else if q.count < 2 {
                out = [LRow(id: "content-help", title: "Search inside files", subtitle: "Type ? then the words to find, e.g. ? invoice 2025", symbol: "text.magnifyingglass")]
            } else if contentHits.isEmpty {
                out = [LRow(id: "content-none", title: "No file contains \u{201C}\(q)\u{201D}", subtitle: "Spotlight may still be indexing", symbol: "text.magnifyingglass")]
            } else {
                out = contentHits.map { Self.fileRow($0, subtitle: ($0.parent as NSString).abbreviatingWithTildeInPath) }
            }
        } else if let (dir, items) = PathQuery.entries(for: text) {
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
            if !canReadProtected, q.count >= 2 {
                out.append(LRow(id: "needs-access", title: "Can\u{2019}t see Documents, Desktop or Downloads", subtitle: "Return to allow access in Privacy & Security, then search again",
                                symbol: "lock.shield", run: {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(u) }
                }))
            }
            if out.isEmpty, LSettings.shared.webFallback, q.count >= 2, let url = URL(string: "https://www.google.com/search?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)) {
                out = [LRow(id: "web", title: "Search the web for \u{201C}\(q)\u{201D}", subtitle: "Return to open in your browser",
                            symbol: "globe", run: { NSWorkspace.shared.open(url) })]
            }
        }
        rows = out
        selected = previous.flatMap { id in out.firstIndex { $0.id == id } } ?? 0
    }
}
