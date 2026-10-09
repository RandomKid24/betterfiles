import SwiftUI
import LauncherCore

/// Icon lookups are slow (disk + icon services), so each path is fetched once.
@MainActor
enum Icons {
    private static let cache = NSCache<NSString, NSImage>()

    static func cached(_ path: String) -> NSImage? { cache.object(forKey: path as NSString) }

    /// Fetched off the main thread so typing never waits on icon services.
    static func load(_ path: String) async -> NSImage {
        if let hit = cached(path) { return hit }
        let image = await Task.detached { NSWorkspace.shared.icon(forFile: path) }.value
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

struct Row: View {
    let candidate: Candidate
    let selected: Bool
    let index: Int
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: icon ?? Icons.cached(candidate.path) ?? NSImage())
                .resizable()
                .frame(width: 30, height: 30)
                .scaleEffect(selected ? 1.1 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(candidate.parent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .task(id: candidate.path) { icon = await Icons.load(candidate.path) }
    }
}

struct LauncherView: View {
    @Bindable var model: Model
    @FocusState private var focused: Bool
    @Namespace private var highlight

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
                        Row(candidate: c, selected: i == model.selected, index: i)
                            .background {
                                // One pill shared by all rows: it glides to the selected row instead of blinking.
                                if i == model.selected {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.22))
                                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
                                        .matchedGeometryEffect(id: "pill", in: highlight)
                                }
                            }
                            .onTapGesture { model.selected = i; model.openSelected() }
                    }
                }
                .padding(8)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: model.selected)
                HStack(spacing: 14) {
                    Label("Open", systemImage: "return")
                    Label("Show in Files", systemImage: "command")
                    Spacer()
                    Text("\u{2191}\u{2193} to move")
                }
                .labelStyle(.titleAndIcon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 640)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        // Pop in from slightly smaller and higher, like Spotlight; spring so it settles instead of stopping dead.
        .scaleEffect(model.visible ? 1 : 0.94, anchor: .top)
        .offset(y: model.visible ? 0 : -10)
        .blur(radius: model.visible ? 0 : 14) // comes into focus as it lands
        .opacity(model.visible ? 1 : 0)
        // Springy on the way in, quick ease on the way out.
        .animation(model.visible ? .spring(response: 0.38, dampingFraction: 0.72) : .easeIn(duration: 0.14), value: model.visible)
        .padding(40) // room for the shadow; the panel itself is transparent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            model.openSelected(reveal: true)
            return .handled
        }
        .onKeyPress(.escape) { model.onDismiss(); return .handled }
        .onChange(of: model.visible) { if model.visible { focused = true } }
    }
}
