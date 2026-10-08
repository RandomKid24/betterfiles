import AppKit
import FilesCore
import UniformTypeIdentifiers

/// Icon lookups are slow, so each distinct icon (one per file type, one for folders) is fetched once.
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: FileItem) -> NSImage {
        if item.isFolder { return cached("folder") { NSWorkspace.shared.icon(for: .folder) } }
        if item.isPackage { return cached(item.url.path) { NSWorkspace.shared.icon(forFile: item.url.path) } }
        let ext = item.url.pathExtension.lowercased()
        return cached("ext:" + ext) { NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data) }
    }

    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }
}
