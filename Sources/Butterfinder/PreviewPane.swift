import SwiftUI
import Quartz
import FilesCore

/// Real Quick Look content (images, PDF, video, text, ...) for the selected file.
struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        if (v.previewItem as? NSURL) as URL? != url { v.previewItem = url as NSURL }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}

struct PreviewPane: View {
    let items: [FileItem]
    let onClose: () -> Void

    var body: some View {
        content
            .animation(.smooth(duration: 0.18), value: items.first?.url)
            .animation(.smooth(duration: 0.18), value: items.count)
            .overlay(alignment: .topTrailing) {
            Button(action: onClose) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
                .help("Hide preview (\u{21E7}\u{2318}P)")
                .padding(6)
        }
    }

    @ViewBuilder private var content: some View {
        if items.count == 1, let item = items.first {
            VStack(spacing: 0) {
                QuickLookView(url: item.url).frame(maxHeight: .infinity)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name).font(.headline).lineLimit(2).truncationMode(.middle)
                    Text(item.kind).foregroundStyle(.secondary)
                    if let size = item.size { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary) }
                    if let m = item.modified { Text(m.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                }
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .id(item.url)
            .transition(.opacity)
        } else {
            Text(items.isEmpty ? "Select a file to preview it" : "\(items.count) items selected")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
