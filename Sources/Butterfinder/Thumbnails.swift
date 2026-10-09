import AppKit
import QuickLookThumbnailing

@MainActor
enum Thumbnails {
    // Bounded: ~48 MB of pixels at most, so browsing huge photo folders can't balloon memory.
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 48 * 1024 * 1024
        c.countLimit = 600
        return c
    }()

    /// Thumbnails are requested, cached and matched to cells in steps: 32 pt for small icons, 64 pt once they are large
    /// (fewer sizes means far fewer thumbnail requests while the zoom slider moves).
    static func bucket(for size: CGFloat) -> Int {
        let step: CGFloat = size < 128 ? 32 : 64
        return Int(size / step) * Int(step)
    }

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
                    cache.setObject(image, forKey: key as NSString, cost: rep.cgImage.bytesPerRow * rep.cgImage.height)
                    completion(image)
                }
            }
        }
    }
}
