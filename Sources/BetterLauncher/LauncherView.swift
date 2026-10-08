import SwiftUI
import LauncherCore

/// Icon lookups are slow (disk + icon services), so each path is fetched once.
@MainActor
enum Icons {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct Row: View {
    let candidate: Candidate
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: Icons.icon(for: candidate.path))
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(candidate.parent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct LauncherView: View {
    @Bindable var model: Model
    @FocusState private var focused: Bool

    // Matches the large continuous corners of macOS 26 windows and Spotlight.
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Search apps, files, folders", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onSubmit { model.openSelected() }
                    .onChange(of: model.text) { model.textChanged() }
            }
            .padding(.horizontal, 22)
            .frame(height: 64)

            if !model.results.isEmpty {
                Divider().padding(.horizontal, 16)
                VStack(spacing: 2) {
                    ForEach(Array(model.results.enumerated()), id: \.element.path) { i, c in
                        Row(candidate: c, selected: i == model.selected)
                            .onTapGesture { model.selected = i; model.openSelected() }
                    }
                }
                .padding(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: 640)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        // Pop in from slightly smaller and higher, like Spotlight; spring so it settles instead of stopping dead.
        .scaleEffect(model.visible ? 1 : 0.94, anchor: .top)
        .offset(y: model.visible ? 0 : -10)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.visible)
        .animation(.snappy(duration: 0.2), value: model.results.count)
        .padding(40) // room for the shadow; the panel itself is transparent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.escape) { model.onDismiss(); return .handled }
        .onChange(of: model.visible) { if model.visible { focused = true } }
    }
}
