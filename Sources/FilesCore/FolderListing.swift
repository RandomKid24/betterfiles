import Foundation

public enum FolderListing {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
        .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    /// Lists a folder including hidden files, with every attribute prefetched in one pass. Safe to call off the main thread.
    public static func list(_ url: URL) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])
        return urls.map { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            let isPackage = v?.isPackage ?? false
            let isDir = v?.isDirectory ?? false
            return FileItem(
                url: u,
                isFolder: isDir && !isPackage,
                isHidden: v?.isHidden ?? u.lastPathComponent.hasPrefix("."),
                isPackage: isPackage,
                size: isDir ? nil : v?.fileSize.map(Int64.init),
                modified: v?.contentModificationDate,
                kind: v?.localizedTypeDescription ?? (isDir ? "Folder" : "Document"))
        }
    }
}
