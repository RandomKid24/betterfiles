import SwiftUI
import LauncherCore
import Shared

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
    let row: LRow
    let selected: Bool
    let number: Int?          // 1...9: the Cmd+number shortcut
    let query: String         // highlighted inside the title
    @State private var icon: NSImage?

    private var title: AttributedString {
        var a = AttributedString(row.title)
        if row.path != nil, !query.isEmpty, let r = a.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].foregroundColor = LSettings.shared.theme.accentColor
            a[r].font = .system(size: 14, weight: .bold)
        }
        return a
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let symbol = row.symbol {
                    Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(LSettings.shared.theme.accentColor)
                } else {
                    Image(nsImage: icon ?? row.path.flatMap(Icons.cached) ?? NSImage()).resizable()
                }
            }
            .frame(width: 30, height: 30)
            .scaleEffect(selected ? 1.1 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !row.kind.isEmpty {
                Text(row.kind).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
            }
            if let number { Text("\u{2318}\(number)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .task(id: row.path) { if let p = row.path { icon = await Icons.load(p) } }
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
                TextField("Search apps and files, or type / to browse", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22))
                    .focused($focused)
                    .onSubmit { model.openSelected() }
                    .onChange(of: model.text) { model.textChanged() }
                    // Attached to the field itself so these chords aren't swallowed as text editing.
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.command) { model.openSelected(reveal: true); return .handled }
                        if press.modifiers.contains(.option) { model.copyPathOfSelected(); return .handled }
                        if press.modifiers.contains(.shift) { model.openSelectedInTerminal(); return .handled }
                        return .ignored
                    }
                    .onKeyPress(.tab, phases: .down) { _ in model.completeSelected() ? .handled : .ignored }
                    .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                        guard press.modifiers.contains(.command), let n = press.characters.first.flatMap({ Int(String($0)) }), n > 0 else { return .ignored }
                        model.jump(to: n)
                        return .handled
                    }
                    .onKeyPress(.delete, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        model.trashSelected()
                        return .handled
                    }
            }
            .padding(.horizontal, 22)
            .frame(height: 64)

            if !model.rows.isEmpty {
                Divider().padding(.horizontal, 16).transition(.opacity)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(Array(model.rows.enumerated()), id: \.element.id) { i, row in
                                Row(row: row, selected: i == model.selected, number: i < 9 ? i + 1 : nil, query: model.highlight)
                                    .background {
                                        // One pill shared by all rows: it glides to the selected row instead of blinking.
                                        if i == model.selected {
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(LSettings.shared.theme.accentColor.opacity(0.22))
                                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    .strokeBorder(LSettings.shared.theme.accentColor.opacity(0.35), lineWidth: 1))
                                                .matchedGeometryEffect(id: "pill", in: highlight)
                                        }
                                    }
                                    .id(row.id)
                                    .onTapGesture { model.selected = i; model.openSelected() }
                                    .contextMenu { RowMenu(model: model, row: row) }
                            }
                        }
                        .padding(8)
                    }
                    // Fits the rows up to a cap; longer lists (a folder, say) scroll.
                    .frame(height: min(CGFloat(model.rows.count) * 45 + 16, 400))
                    .onChange(of: model.selected) {
                        if model.rows.indices.contains(model.selected) { proxy.scrollTo(model.rows[model.selected].id) }
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: model.selected)
                HStack(spacing: 12) {
                    Text("\u{21A9} Open")
                    if model.pathMode { Text("\u{21E5} Complete") }
                    Text("\u{2318}\u{21A9} Files")
                    Text("\u{2325}\u{21A9} Path")
                    Text("\u{21E7}\u{21A9} Terminal")
                    Text("\u{2318}\u{232B} Trash")
                    Text("Right-click: more")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 640)
        .background { if !LSettings.shared.glass { shape.fill(LSettings.shared.theme.surfaceColor ?? Color(nsColor: .windowBackgroundColor)) } }
        .glassEffect(LSettings.shared.glass ? .regular : .identity, in: shape)
        .overlay { shape.strokeBorder(LSettings.shared.theme.accentColor.opacity(0.25), lineWidth: 1) }
        .shadow(color: .black.opacity(0.28), radius: 28, y: 12)
        // Pop in from slightly smaller and higher, like Spotlight; spring so it settles instead of stopping dead.
        .scaleEffect(model.visible ? 1 : 0.94, anchor: .top)
        .offset(y: model.visible ? 0 : -10)
        .blur(radius: model.visible ? 0 : 14) // comes into focus as it lands
        .opacity(model.visible ? 1 : 0)
        // Springy on the way in, quick ease on the way out.
        // The results block grows/collapses smoothly; per-keystroke count changes deliberately don't animate.
        .animation(.smooth(duration: 0.24), value: model.rows.isEmpty)
        .animation(model.visible ? .spring(response: 0.38, dampingFraction: 0.72) : .easeIn(duration: 0.14), value: model.visible)
        .padding(40) // room for the shadow; the panel itself is transparent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.escape) { model.onDismiss(); return .handled }
        .onChange(of: model.visible) { if model.visible { focused = true } }
    }
}

/// Right-click menu for a result.
struct RowMenu: View {
    let model: Model
    let row: LRow

    var body: some View {
        if row.path != nil {
            Button("Open") { model.open(row) }
            Button("Show in Butterfinder") { model.open(row, reveal: true) }
            Button("Reveal in Finder") { model.revealInFinder(row) }
            Menu("Open With") {
                ForEach(model.appsFor(row), id: \.self) { app in
                    Button(app.deletingPathExtension().lastPathComponent) { model.openWith(row, app) }
                }
            }
            Divider()
            Button("Copy Path") { model.copyPath(row) }
            Button("Copy Name") { model.copyName(row) }
            Button("Open in Terminal") { model.openInTerminal(row) }
            Divider()
            if model.canForget(row) { Button("Remove from Recents") { model.forget(row) } }
            Button("Move to Trash", role: .destructive) { model.trash(row) }
        } else if row.run != nil {
            Button("Run") { model.open(row) }
        }
    }
}
