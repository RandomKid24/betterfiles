import SwiftUI
import Observation

/// One tab: a folder view, optionally split into two panes.
@MainActor @Observable
final class Tab: Identifiable {
    let primary: BrowserModel
    private(set) var secondary: BrowserModel?
    private(set) var secondaryActive = false

    init(start: URL) {
        primary = BrowserModel(start: start)
        wire(primary)
    }

    /// The pane that menu commands act on.
    var active: BrowserModel { secondaryActive ? (secondary ?? primary) : primary }
    private var other: BrowserModel? { secondary == nil ? nil : (secondaryActive ? primary : secondary) }

    private func wire(_ m: BrowserModel) {
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
    private(set) var all: [Tab] = [Tab(start: FileManager.default.homeDirectoryForCurrentUser)]
    private(set) var index = 0
    var current: Tab { all[index] }

    func new() {
        all.append(Tab(start: current.active.url))
        index = all.count - 1
    }

    /// Returns false when this was the last tab (the caller closes the window instead).
    @discardableResult
    func close(_ i: Int? = nil) -> Bool {
        guard all.count > 1 else { return false }
        let i = i ?? index
        all.remove(at: i)
        index = min(index > i ? index - 1 : index, all.count - 1)
        return true
    }

    func select(_ i: Int) { if all.indices.contains(i) { index = i } }
    func step(_ d: Int) { index = (index + d + all.count) % all.count }
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
                .background(active ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                .contentShape(Capsule())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { tabs.select(i) } }
            }
            Button { withAnimation(.snappy(duration: 0.2)) { tabs.new() } } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
    }
}
