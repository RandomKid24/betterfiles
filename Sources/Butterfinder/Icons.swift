import AppKit
import FilesCore
import UniformTypeIdentifiers
import CoreImage

/// Icon lookups are slow, so each distinct icon (one per file type, one for folders) is fetched once.
@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: FileItem) -> NSImage {
        if item.isFolder {
            // A tagged folder takes its tag's colour, like Finder's coloured folders.
            if let hex = item.tags.lazy.compactMap({ Tags.hex(for: $0) }).first { return tintedFolder(hex) }
            return cached("folder") { NSWorkspace.shared.icon(for: .folder) }
        }
        if item.isPackage { return cached(item.url.path) { NSWorkspace.shared.icon(forFile: item.url.path) } }
        let ext = item.url.pathExtension.lowercased()
        return cached("ext:" + ext) { NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data) }
    }

    /// The system folder icon with its hue rotated from Apple's blue to `hex` (greys are desaturated).
    private static func tintedFolder(_ hex: UInt32) -> NSImage {
        cached("folder:\(hex)") {
            let base = NSWorkspace.shared.icon(for: .folder)
            var rect = NSRect(x: 0, y: 0, width: 256, height: 256)
            guard let cg = base.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return base }
            let target = NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
            var image = CIImage(cgImage: cg)
            if target.saturationComponent < 0.2 {
                image = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0, kCIInputBrightnessKey: 0.05])
            } else {
                let blueHue: CGFloat = 0.575   // hue of the stock folder icon
                image = image.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: (target.hueComponent - blueHue) * 2 * .pi])
                    .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.35, kCIInputBrightnessKey: 0.02])   // rotating hue alone looks muddy
            }
            guard let out = CIContext().createCGImage(image, from: image.extent) else { return base }
            return NSImage(cgImage: out, size: NSSize(width: 128, height: 128))
        }
    }

    private static func cached(_ key: String, _ make: () -> NSImage) -> NSImage {
        if let hit = cache[key] { return hit }
        let image = make()
        cache[key] = image
        return image
    }
}
