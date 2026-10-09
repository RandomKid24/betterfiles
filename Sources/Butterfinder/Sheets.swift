import SwiftUI
import FilesCore

/// Get Info: sizes (folders are summed in the background), dates and permissions.
struct InfoView: View {
    let urls: [URL]
    let onClose: () -> Void
    @State private var bytes: Int64?
    @State private var count = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if urls.count == 1 { Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable().frame(width: 48, height: 48) }
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items").font(.title3.bold()).lineLimit(2)
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                if urls.count == 1, let a = attributes {
                    row("Kind", (try? urls[0].resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription ?? "")
                    row("Where", urls[0].deletingLastPathComponent().path)
                    row("Created", (a[.creationDate] as? Date)?.formatted(date: .long, time: .shortened) ?? "")
                    row("Modified", (a[.modificationDate] as? Date)?.formatted(date: .long, time: .shortened) ?? "")
                    row("Permissions", permissions(a))
                    row("Owner", a[.ownerAccountName] as? String ?? "")
                }
                row("Size", bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + (count > 1 ? " (\(count) items)" : "") } ?? "Calculating\u{2026}")
            }
            .font(.callout)
            .textSelection(.enabled)
            HStack { Spacer(); Button("Done", action: onClose).keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 420)
        .task { (bytes, count) = await Self.measure(urls) }
    }

    private var attributes: [FileAttributeKey: Any]? { try? FileManager.default.attributesOfItem(atPath: urls[0].path) }

    private func row(_ k: String, _ v: String) -> some View {
        GridRow { Text(k).foregroundStyle(.secondary).gridColumnAlignment(.trailing); Text(v).lineLimit(2).truncationMode(.middle) }
    }

    private func permissions(_ a: [FileAttributeKey: Any]) -> String {
        let mode = (a[.posixPermissions] as? Int) ?? 0
        return stride(from: 6, through: 0, by: -3).map { shift in
            let bits = (mode >> shift) & 7
            return (bits & 4 != 0 ? "r" : "-") + (bits & 2 != 0 ? "w" : "-") + (bits & 1 != 0 ? "x" : "-")
        }.joined()
    }

    private static func measure(_ urls: [URL]) async -> (Int64, Int) {
        await Task.detached { sum(urls) }.value
    }

    private nonisolated static func sum(_ urls: [URL]) -> (Int64, Int) {
        do {
            var total: Int64 = 0, n = 0
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
            for url in urls {
                if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) {
                    for case let f as URL in e {
                        let v = try? f.resourceValues(forKeys: Set(keys))
                        if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0); n += 1 }
                    }
                }
                let v = try? url.resourceValues(forKeys: Set(keys))
                if v?.isRegularFile == true { total += Int64(v?.totalFileAllocatedSize ?? 0); n += 1 }
            }
            return (total, n)
        }
    }
}

struct BatchRenameView: View {
    let items: [FileItem]
    let onApply: (String, Int) -> Void
    let onClose: () -> Void
    @State private var base = ""
    @State private var start = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(items.count) items").font(.title3.bold())
            TextField("Name", text: $base).textFieldStyle(.roundedBorder)
            Stepper("Start numbering at \(start)", value: $start, in: 0...9999)
            Divider()
            ForEach(Array(BatchRename.plan(items.map(\.url), base: base.isEmpty ? "Name" : base, start: start).prefix(5)), id: \.url) { p in
                Text(p.newName).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            if items.count > 5 { Text("\u{2026} and \(items.count - 5) more").font(.caption).foregroundStyle(.tertiary) }
            HStack {
                Spacer()
                Button("Cancel", action: onClose).keyboardShortcut(.cancelAction)
                Button("Rename") { onApply(base, start); onClose() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(base.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct CompareView: View {
    let tab: Tab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare folders").font(.title3.bold())
            if let c = tab.compared {
                Text("\(c.left.path)\n\(c.right.path)").font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            if tab.comparing || tab.comparison == nil {
                ProgressView("Comparing\u{2026}").frame(maxWidth: .infinity, minHeight: 160)
            } else if let r = tab.comparison {
                Text("\(r.sameCount) identical").foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        group("Only in left", r.onlyLeft, "arrow.right.circle", tab.copyMissingButton(toRight: true))
                        group("Only in right", r.onlyRight, "arrow.left.circle", tab.copyMissingButton(toRight: false))
                        group("Different (not touched)", r.different, "exclamationmark.triangle", nil)
                    }
                }
                .frame(height: 260)
            }
            HStack {
                Text("Copying never overwrites or deletes anything.").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Done") { tab.showCompare = false }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    @ViewBuilder
    private func group(_ title: String, _ paths: [String], _ symbol: String, _ action: (() -> Void)?) -> some View {
        if !paths.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("\(title) (\(paths.count))", systemImage: symbol).font(.headline)
                    Spacer()
                    if let action { Button("Copy \(paths.count) across", action: action).controlSize(.small) }
                }
                ForEach(paths.prefix(40), id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                if paths.count > 40 { Text("\u{2026} and \(paths.count - 40) more").font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }
}

extension Tab {
    func copyMissingButton(toRight: Bool) -> () -> Void { { self.copyMissing(toRight: toRight) } }
}
