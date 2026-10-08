import AppKit
import QuickLookThumbnailing

@MainActor
enum Thumbnails {
    private static let cache = NSCache<NSString, NSImage>()

    /// Thumbnails are requested, cached and matched to cells at this 32 pt granularity.
    static func bucket(for size: CGFloat) -> Int { Int(size / 32) * 32 }

    /// Calls `completion` on the main actor with a real thumbnail if the file has one. Files without a
    /// thumbnail never call back, so the caller's file-type icon stays.
    static func load(url: URL, size: CGFloat, completion: @escaping @MainActor (NSImage) -> Void) {
        guard size >= 48 else { return } // tiny icons: the file-type icon is enough
        let bucket = bucket(for: size)
        let key = "\(url.path)@\(bucket)"
        if let hit = cache.object(forKey: key as NSString) { completion(hit); return }

        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: bucket, height: bucket),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let rep else { return }
            let image = NSImage(cgImage: rep.cgImage, size: .zero)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    cache.setObject(image, forKey: key as NSString)
                    completion(image)
                }
            }
        }
    }
}
