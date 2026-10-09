import SwiftUI
import FilesCore

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
            SidebarView(model: active, url: active.url, favorites: Favorites.shared.urls)
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
        VStack(spacing: 0) {
            TopBar(model: model, onNewTab: onNewTab)
                .simultaneousGesture(TapGesture().onEnded { model.onActivate() })
            Divider()
            ZStack {
                switch model.viewMode {
                case .details:
                    DetailsView(model: model, version: model.version, selection: model.selection,
                                sort: model.sortColumn, ascending: model.ascending)
                case .icons:
                    IconView(model: model, version: model.version, selection: model.selection, zoom: model.zoom)
                }
                if let m = model.displayMessage {
                    Text(m).foregroundStyle(.secondary).multilineTextAlignment(.center).padding().allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .animation(.smooth(duration: 0.2), value: model.viewMode)
            .animation(.smooth(duration: 0.2), value: model.displayMessage)
            Divider()
            StatusBar(model: model)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accentColor).frame(height: 2).opacity(highlight ? 1 : 0)
        }
        .animation(.smooth(duration: 0.2), value: highlight)
    }
}

struct TopBar: View {
    @Bindable var model: BrowserModel
    let onNewTab: () -> Void
    @FocusState private var filterFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!model.canGoBack)
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!model.canGoForward)
            Button { model.goUp() } label: { Image(systemName: "arrow.up") }.disabled(model.url.path == "/")
            AddressBar(model: model)
            TextField("Filter", text: $model.filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .focused($filterFocused)
                .onChange(of: model.filter) { model.recompute() }
                .onExitCommand { model.filter = "" }
            if model.viewMode == .icons {
                Slider(value: Binding(get: { model.zoom }, set: { model.setZoom($0) }), in: 32...256)
                    .frame(width: 110)
            }
            Button { onNewTab() } label: { Image(systemName: "plus.square.on.square") }.help("New tab (\u{2318}T)")
            Button { model.togglePreview() } label: { Image(systemName: "sidebar.right") }
                .help("Preview pane (\u{21E7}\u{2318}P)")
            Picker("View", selection: Binding(get: { model.viewMode }, set: { model.setViewMode($0) })) {
                Image(systemName: "list.bullet").tag(ViewMode.details)
                Image(systemName: "square.grid.2x2").tag(ViewMode.icons)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
        }
        .buttonStyle(.borderless)
        .padding(8)
        .onChange(of: model.filterFocusToken) { filterFocused = true }
    }
}

struct StatusBar: View {
    let model: BrowserModel

    var body: some View {
        HStack {
            Text("\(model.visible.count) items" + (model.selection.isEmpty ? "" : " \u{00B7} \(model.selection.count) selected"))
            Spacer()
            if let s = model.status { Text(s).lineLimit(1) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}
