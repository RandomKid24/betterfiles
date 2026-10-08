import SwiftUI
import LauncherCore

struct LauncherView: View {
    @Bindable var model: Model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps, files, folders", text: $model.text)
                .textFieldStyle(.plain)
                .font(.system(size: 24))
                .padding(16)
                .focused($focused)
                .onSubmit { model.openSelected() }
                .onChange(of: model.text) { model.textChanged() }

            if !model.results.isEmpty {
                Divider()
                ForEach(Array(model.results.enumerated()), id: \.element.path) { i, c in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: c.path))
                            .resizable()
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(c.name).lineLimit(1)
                            Text(c.parent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .background(i == model.selected ? Color.accentColor.opacity(0.25) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selected = i; model.openSelected() }
                }
            }
        }
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        // Panel is a fixed height; keep the content pinned to its top edge.
        .frame(maxHeight: .infinity, alignment: .top)
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.escape) { model.onDismiss(); return .handled }
        .onAppear { focused = true }
        .onChange(of: model.showCount) { focused = true }
    }
}
