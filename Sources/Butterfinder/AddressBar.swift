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
                // Shows as much of the path as fits: the whole thing, else "…" plus the last few folders.
                let all = AddressPath.breadcrumbs(model.url)
                ViewThatFits(in: .horizontal) {
                    ForEach(Array(Set([all.count, 3, 2, 1].filter { $0 <= all.count && $0 > 0 })).sorted(by: >), id: \.self) { n in
                        crumbs(all, last: n)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .clipped()
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

    private func crumbs(_ all: [Crumb], last n: Int) -> some View {
        HStack(spacing: 2) {
            if n < all.count {
                Button("\u{2026}") { model.navigate(to: all[all.count - n - 1].url) }.buttonStyle(.plain).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(Array(all.suffix(n))) { crumb in
                Button(crumb.name) { model.navigate(to: crumb.url) }.buttonStyle(.plain).lineLimit(1)
                if crumb.url.path != model.url.path {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize()
    }

    private func beginEditing() {
        text = model.url.path
        editing = true
        DispatchQueue.main.async {
            focused = true
            // Focus lands a turn later; only select-all once the field editor is first responder,
            // otherwise the action would reach the file list and select every file.
            DispatchQueue.main.async {
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
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
