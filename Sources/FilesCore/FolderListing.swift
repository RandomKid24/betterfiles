import Foundation

public enum FolderListing {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
        .contentModificationDateKey, .localizedTypeDescriptionKey, .creationDateKey, .tagNamesKey,
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
                kind: v?.localizedTypeDescription ?? (isDir ? "Folder" : "Document"),
                created: v?.creationDate,
                tags: v?.tagNames ?? [])
        }
    }

    /// Just the sub-folders of `url` (no dates, sizes, kinds or tags), for the sidebar tree. Much cheaper than `list`.
    public static func subfolders(_ url: URL) -> [FileItem] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { u in
            let v = try? u.resourceValues(forKeys: Set(keys))
            return v?.isDirectory == true && v?.isPackage != true ? FileItem(url: u, isFolder: true) : nil
        }
    }
}
