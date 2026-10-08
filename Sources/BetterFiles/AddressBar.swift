import SwiftUI
import FilesCore

struct AddressBar: View {
    @Bindable var model: BrowserModel
    @State private var editing = false
    @State private var text = ""
    @State private var shakes = 0.0
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            if editing {
                TextField("Path", text: $text)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { if !focused { editing = false } }
            } else {
                HStack(spacing: 2) {
                    ForEach(AddressPath.breadcrumbs(model.url)) { crumb in
                        Button(crumb.name) { model.navigate(to: crumb.url) }.buttonStyle(.plain)
                        if crumb.url.path != model.url.path {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: beginEditing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .modifier(Shake(amount: shakes))
        .onChange(of: model.addressFocusToken) { beginEditing() }
    }

    private func beginEditing() {
        text = model.url.path
        editing = true
        DispatchQueue.main.async {
            focused = true
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func commit() {
        if let target = AddressPath.resolve(text, from: model.url) {
            editing = false
            model.navigate(to: target)
        } else {
            withAnimation(.linear(duration: 0.3)) { shakes += 1 } // invalid path: shake and keep what was typed
        }
    }
}

private struct Shake: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(amount * .pi * 4), y: 0))
    }
}
