import SwiftUI
import Observation
import FilesCore

/// One tab: a folder view, optionally split into two panes.
@MainActor @Observable
final class Tab: Identifiable {
    let uid = UUID()
    let primary: BrowserModel
    private(set) var secondary: BrowserModel?
    private(set) var secondaryActive = false

    var showCompare = false
    private(set) var comparing = false
    private(set) var comparison: FolderCompare.Result?
    private(set) var compared: (left: URL, right: URL)?

    /// Compares the two panes' folders (needs the split view).
    func comparePanes() {
        guard let s = secondary else { primary.status = "Split the view first (\u{2318}\\) to compare two folders."; return }
        let l = primary.url, r = s.url
        compared = (l, r)
        comparison = nil
        comparing = true
        showCompare = true
        Task.detached {
            let res = FolderCompare.compare(l, r)
            await MainActor.run { self.comparison = res; self.comparing = false }
        }
    }

    enum SyncPlan: Equatable {
        case copyMissing(toRight: Bool)    // files that exist on one side only
        case updateOlder(toRight: Bool)    // the newer version replaces the older (which goes to the Trash)
        case both                          // all of the above, both directions
    }

    /// How many files a plan would copy, and how many it would replace.
    func counts(for plan: SyncPlan) -> (copy: Int, replace: Int) {
        guard let r = comparison else { return (0, 0) }
        switch plan {
        case .copyMissing(let right): return (right ? r.onlyLeft.count : r.onlyRight.count, 0)
        case .updateOlder(let right): return (0, right ? r.newerLeft.count : r.newerRight.count)
        case .both: return (r.onlyLeft.count + r.onlyRight.count, r.newerLeft.count + r.newerRight.count)
        }
    }

    /// Runs a sync. Nothing is deleted: replaced files go to the Trash, and Cmd+Z undoes the whole thing.
    func sync(_ plan: SyncPlan) {
        guard let c = compared, let r = comparison else { return }
        var missingRight: [String] = [], missingLeft: [String] = [], updateRight: [String] = [], updateLeft: [String] = []
        switch plan {
        case .copyMissing(let right): if right { missingRight = r.onlyLeft } else { missingLeft = r.onlyRight }
        case .updateOlder(let right): if right { updateRight = r.newerLeft } else { updateLeft = r.newerRight }
        case .both: missingRight = r.onlyLeft; missingLeft = r.onlyRight; updateRight = r.newerLeft; updateLeft = r.newerRight
        }
        let (left, right) = (c.left, c.right)
        comparing = true
        Task.detached {
            let copied = FolderCompare.copyMissing(missingRight, from: left, to: right) + FolderCompare.copyMissing(missingLeft, from: right, to: left)
            let replaced = FolderCompare.replaceOlder(updateRight, from: left, to: right) + FolderCompare.replaceOlder(updateLeft, from: right, to: left)
            await MainActor.run {
                let ok = copied.filter(\.succeeded).count, swapped = replaced.filter(\.succeeded).count
                let failed = copied.count + replaced.count - ok - swapped
                self.primary.recordSync(created: copied, replaced: replaced)
                self.primary.status = "Synced: \(ok) copied, \(swapped) updated" + (failed > 0 ? ", \(failed) failed" : "") + ". \u{2318}Z undoes it."
                self.primary.reload(); self.secondary?.reload()
                self.comparePanes()
            }
        }
    }

    @ObservationIgnored var onNewTab: (URL) -> Void = { _ in }

    init(start: URL) {
        primary = BrowserModel(start: start)
        wire(primary)
    }

    func openInOtherPane(_ url: URL) {
        if secondary == nil { toggleSplit() }
        (secondaryActive ? primary : secondary)?.navigate(to: url)
    }

    /// The pane that menu commands act on.
    var active: BrowserModel { secondaryActive ? (secondary ?? primary) : primary }
    private var other: BrowserModel? { secondary == nil ? nil : (secondaryActive ? primary : secondary) }

    private func wire(_ m: BrowserModel) {
        m.onOpenInNewTab = { [weak self] url in self?.onNewTab(url) }
        m.onOpenInOtherPane = { [weak self] url in self?.openInOtherPane(url) }
        m.onActivate = { [weak self, weak m] in
            guard let self, let m else { return }
            self.secondaryActive = (m === self.secondary)
        }
    }

    func toggleSplit() {
        if secondary == nil {
            let m = BrowserModel(start: primary.url)
            wire(m)
            secondary = m
            secondaryActive = true
        } else {
            secondary = nil
            secondaryActive = false
        }
    }

    /// F5 / F6: send the selection to the folder shown in the other pane.
    func sendToOther(move: Bool) {
        guard let other else { active.status = "Split the view first (\u{2318}\\)."; return }
        active.drop(active.selectedItems.map(\.url), onto: other.url, copy: !move)
    }
}

@MainActor @Observable
final class Tabs {
    private(set) var all: [Tab] = []
    private(set) var index = 0
    var current: Tab { all[index] }
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        // Reopen the tabs from last time (folders that no longer exist are skipped).
        let d = UserDefaults.standard
        if Settings.shared.restoreTabs, let paths = d.stringArray(forKey: "tabSession") {
            all = paths.filter { FileManager.default.fileExists(atPath: $0) }.map { Tab(start: URL(fileURLWithPath: $0)) }
            index = min(max(0, d.integer(forKey: "tabSessionIndex")), max(0, all.count - 1))
        }
        if all.isEmpty { all = [Tab(start: Settings.shared.startFolder)] }
        all.forEach { wire($0) }
        observer = NotificationCenter.default.addObserver(forName: .butterfinderNavigated, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveSession() }
        }
    }

    private func wire(_ tab: Tab) { tab.onNewTab = { [weak self] in self?.new(at: $0) } }

    private func saveSession() {
        guard Settings.shared.restoreTabs else { return }
        let d = UserDefaults.standard
        d.set(all.map { $0.primary.url.path }, forKey: "tabSession")
        d.set(index, forKey: "tabSessionIndex")
    }

    func new(at url: URL? = nil) {
        let tab = Tab(start: url ?? current.active.url)
        wire(tab)
        all.append(tab)
        index = all.count - 1
        saveSession()
    }

    /// Returns false when this was the last tab (the caller closes the window instead).
    @discardableResult
    func close(_ i: Int? = nil) -> Bool {
        guard all.count > 1 else { return false }
        let i = i ?? index
        all.remove(at: i)
        index = min(index > i ? index - 1 : index, all.count - 1)
        saveSession()
        return true
    }

    func select(_ i: Int) { if all.indices.contains(i) { index = i; saveSession() } }
    func step(_ d: Int) { index = (index + d + all.count) % all.count; saveSession() }

    /// Drag a tab onto another to put it before that one; `before: nil` moves it to the end.
    func move(_ uid: UUID, before target: UUID?) {
        guard let from = all.firstIndex(where: { $0.uid == uid }), uid != target else { return }
        let selected = all[index]
        let tab = all.remove(at: from)
        let to = target.flatMap { t in all.firstIndex { $0.uid == t } } ?? all.count
        all.insert(tab, at: to)
        index = all.firstIndex { $0 === selected } ?? 0
        saveSession()
    }
}

struct TabBar: View {
    let tabs: Tabs

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.all.enumerated()), id: \.element.id) { i, tab in
                let active = i == tabs.index
                let url = tab.primary.url
                HStack(spacing: 6) {
                    Image(systemName: tab.secondary == nil ? "folder" : "rectangle.split.2x1").foregroundStyle(.secondary)
                    Text(url.path == "/" ? "/" : url.lastPathComponent).lineLimit(1)
                    Button { tabs.close(i) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(active ? Settings.shared.theme.accentColor.opacity(0.22) : Color.clear, in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { tabs.select(i) } }
                .draggable(tab.uid.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                    withAnimation(.snappy(duration: 0.2)) { tabs.move(id, before: tab.uid) }
                    return true
                }
            }
            Button { withAnimation(.snappy(duration: 0.2)) { tabs.new() } } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            Spacer()
                .dropDestination(for: String.self) { ids, _ in   // dropping in the empty space moves a tab to the end
                    guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                    withAnimation(.snappy(duration: 0.2)) { tabs.move(id, before: nil) }
                    return true
                }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }
}
