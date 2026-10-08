import SwiftUI
import FilesCore

struct BrowserView: View {
    @Bindable var model: BrowserModel

    var body: some View {
        // TEMPORARY (Task 9 replaces this with SidebarView in a NavigationSplitView)
        VStack(spacing: 0) {
            TopBar(model: model)
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
                }
            }
            Divider()
            StatusBar(model: model)
        }
        .frame(minWidth: 640, minHeight: 360)
    }
}

struct TopBar: View {
    @Bindable var model: BrowserModel
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
