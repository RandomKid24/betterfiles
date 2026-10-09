import Foundation

public enum BatchRename {
    /// "Photo 1.jpg", "Photo 2.jpg", ... (zero-padded once there are 10 or more). Keeps each file's extension.
    public static func plan(_ urls: [URL], base: String, start: Int) -> [(url: URL, newName: String)] {
        let width = String(start + urls.count - 1).count
        return urls.enumerated().map { i, url in
            let n = String(format: "%0\(width)d", start + i)
            let ext = url.pathExtension
            return (url, ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
        }
    }
}
