import SwiftUI
import FilesCore
import Shared

struct BrowserView: View {
    let tabs: Tabs

    var body: some View {
        VStack(spacing: 0) {
            if tabs.all.count > 1 {
                VStack(spacing: 0) { TabBar(tabs: tabs); Divider() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // .id rebuilds the AppKit views per tab so each keeps its own folder, selection and scroll state.
            TabContent(tab: tabs.current, onNewTab: { tabs.new() }).id(tabs.current.id)
                .transition(.opacity)
        }
        .tint(Settings.shared.theme.accentColor)
        .animation(.smooth(duration: 0.22), value: tabs.all.count)
        .animation(.smooth(duration: 0.18), value: tabs.current.id)
    }
}

struct TabContent: View {
    let tab: Tab
    let onNewTab: () -> Void

    var body: some View {
        let active = tab.active
        NavigationSplitView {
            SidebarView(model: active, url: active.url, favorites: Favorites.shared.urls, style: Settings.shared.revision)
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
        } detail: {
            HStack(spacing: 0) {
                Pane(model: tab.primary, onNewTab: onNewTab, highlight: tab.secondary != nil && !tab.secondaryActive)
                if let second = tab.secondary {
                    Divider()
                    Pane(model: second, onNewTab: onNewTab, highlight: tab.secondaryActive)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                if active.showPreview {
                    Divider()
                    PreviewPane(items: active.selectedItems, onClose: { active.togglePreview() }).frame(width: 300)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.smooth(duration: 0.3), value: active.showPreview)
            .animation(.smooth(duration: 0.3), value: tab.secondary == nil)
        }
        .frame(minWidth: 950, minHeight: 400)
        .sheet(isPresented: Binding(get: { active.showInfo }, set: { active.showInfo = $0 })) {
            InfoView(urls: active.infoURLs) { active.showInfo = false }
        }
        .sheet(isPresented: Binding(get: { active.showBatchRename }, set: { active.showBatchRename = $0 })) {
            BatchRenameView(items: active.batchItems, onApply: { active.applyBatchRename(base: $0, start: $1) }) { active.showBatchRename = false }
        }
    }
}

struct Pane: View {
    @Bindable var model: BrowserModel
    let onNewTab: () -> Void
    let highlight: Bool

    var body: some View {
        let settings = Settings.shared
        let rev = settings.revision
        VStack(spacing: 0) {
            TopBar(model: model, onNewTab: onNewTab)
                .simultaneousGesture(TapGesture().onEnded { model.onActivate() })
            Divider()
            ZStack {
                switch model.viewMode {
                case .details:
                    DetailsView(model: model, version: model.version, selection: model.selection,
                                sort: model.sortColumn, ascending: model.ascending, style: rev)
                case .icons:
                    IconView(model: model, version: model.version, selection: model.selection, zoom: model.zoom, style: rev)
                }
                if let m = model.displayMessage {
                    VStack(spacing: 8) {
                        Image(systemName: model.filter.isEmpty ? "folder" : "magnifyingglass").font(.system(size: 34, weight: .light))
                        Text(m).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary).padding().allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.smooth(duration: 0.2), value: model.viewMode)
            .animation(.smooth(duration: 0.2), value: model.displayMessage)
            if settings.showStatusBar {
                Divider()
                StatusBar(model: model)
            }
        }
        .background(settings.theme.surfaceColor ?? Color.clear)
        .overlay(alignment: .top) {
            Rectangle().fill(settings.theme.accentColor).frame(height: 2).opacity(highlight ? 1 : 0)
        }
        .animation(.smooth(duration: 0.2), value: highlight)
        .onChange(of: rev) { model.recompute() }
    }
}

/// Small icon button with a hover highlight.
struct ToolButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(active ? Color.white : (enabled ? Color.primary : Color.secondary.opacity(0.4)))
                .background(active ? Settings.shared.theme.accentColor : (hover && enabled ? Color.primary.opacity(0.1) : .clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .animation(.easeOut(duration: 0.12), value: active)
    }
}

struct TopBar: View {
    @Bindable var model: BrowserModel
    let onNewTab: () -> Void
    @FocusState private var filterFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                ToolButton(symbol: "chevron.left", help: "Back (\u{2318}[)") { model.goBack() }.disabled(!model.canGoBack)
                ToolButton(symbol: "chevron.right", help: "Forward (\u{2318}])") { model.goForward() }.disabled(!model.canGoForward)
                ToolButton(symbol: "arrow.up", help: "Enclosing folder (\u{2318}\u{2191})") { model.goUp() }.disabled(model.url.path == "/")
            }
            AddressBar(model: model)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Filter", text: $model.filter)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onChange(of: model.filter) { model.recompute() }
                    .onExitCommand { model.filter = "" }
                if !model.filter.isEmpty {
                    Button { model.filter = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(width: 170)
            .background(Color.primary.opacity(filterFocused ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Settings.shared.theme.accentColor.opacity(filterFocused ? 0.8 : 0), lineWidth: 1.5))
            .animation(.easeOut(duration: 0.15), value: filterFocused)
            if model.viewMode == .icons {
                Slider(value: Binding(get: { model.zoom }, set: { model.setZoom($0) }), in: 32...256).frame(width: 100)
                    .transition(.opacity)
            }
            HStack(spacing: 2) {
                ToolButton(symbol: "list.bullet", help: "Details (\u{2318}1)", active: model.viewMode == .details) { model.setViewMode(.details) }
                ToolButton(symbol: "square.grid.2x2", help: "Icons (\u{2318}2)", active: model.viewMode == .icons) { model.setViewMode(.icons) }
            }
            ToolButton(symbol: "sidebar.right", help: "Preview pane (\u{21E7}\u{2318}P)", active: model.showPreview) { model.togglePreview() }
            ToolButton(symbol: "plus.square.on.square", help: "New tab (\u{2318}T)", action: onNewTab)
            ToolButton(symbol: "gearshape", help: "Settings (\u{2318},)") { SettingsWindow.show() }
        }
        .animation(.smooth(duration: 0.2), value: model.viewMode)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .onChange(of: model.filterFocusToken) { filterFocused = true }
    }
}

struct StatusBar: View {
    let model: BrowserModel

    private var summary: String {
        var s = "\(model.visible.count) items"
        let picked = model.selectedItems
        if !picked.isEmpty {
            s += " \u{00B7} \(picked.count) selected"
            let bytes = picked.compactMap(\.size).reduce(0, +)
            if bytes > 0 { s += " (\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))" }
        }
        return s
    }

    private var free: String? {
        guard let v = try? model.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = v.volumeAvailableCapacityForImportantUsage else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " available"
    }

    var body: some View {
        HStack {
            Text(summary)
            if let s = model.status { Text("\u{00B7} " + s).lineLimit(1).transition(.opacity) }
            Spacer()
            if let free { Text(free) }
        }
        .animation(.smooth(duration: 0.2), value: model.status)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}
