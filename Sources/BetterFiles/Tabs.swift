import SwiftUI
import Observation

@MainActor @Observable
final class Tabs {
    private(set) var all: [BrowserModel] = [BrowserModel()]
    private(set) var index = 0
    var current: BrowserModel { all[index] }

    func new() {
        all.append(BrowserModel(start: current.url))
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
            ForEach(Array(tabs.all.enumerated()), id: \.element.id) { i, m in
                let active = i == tabs.index
                HStack(spacing: 6) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    Text(m.url.path == "/" ? "/" : m.url.lastPathComponent).lineLimit(1)
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
