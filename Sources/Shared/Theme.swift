import AppKit
import SwiftUI

/// A colour theme shared by Butterfinder and Butterlight: an accent plus an optional tinted surface.
public struct Theme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    let accent: UInt32?          // nil = the system accent colour
    let surfaceLight: UInt32?
    let surfaceDark: UInt32?

    public static let all: [Theme] = [
        Theme(id: "system",   name: "System",   accent: nil,      surfaceLight: nil,      surfaceDark: nil),
        Theme(id: "ocean",    name: "Ocean",    accent: 0x14B8A6, surfaceLight: 0xEFF9F8, surfaceDark: 0x0D1B1C),
        Theme(id: "midnight", name: "Midnight", accent: 0x6366F1, surfaceLight: 0xF0F0FF, surfaceDark: 0x0F1224),
        Theme(id: "violet",   name: "Violet",   accent: 0xA855F7, surfaceLight: 0xF7F0FF, surfaceDark: 0x171024),
        Theme(id: "rose",     name: "Rose",     accent: 0xEC4899, surfaceLight: 0xFFF0F7, surfaceDark: 0x1D1019),
        Theme(id: "sunset",   name: "Sunset",   accent: 0xF97316, surfaceLight: 0xFFF4EC, surfaceDark: 0x1E1310),
        Theme(id: "forest",   name: "Forest",   accent: 0x22C55E, surfaceLight: 0xEFF8F2, surfaceDark: 0x0E1B14),
        Theme(id: "graphite", name: "Graphite", accent: 0x8E8E93, surfaceLight: 0xF2F2F4, surfaceDark: 0x161618),
    ]

    public static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }

    public var accentNS: NSColor { accent.map(Self.color) ?? .controlAccentColor }
    public var accentColor: Color { Color(nsColor: accentNS) }

    /// Background tint that adapts to light and dark, or nil to keep the system background.
    public var surfaceNS: NSColor? {
        guard let l = surfaceLight, let d = surfaceDark else { return nil }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? Self.color(d) : Self.color(l)
        }
    }
    public var surfaceColor: Color? { surfaceNS.map { Color(nsColor: $0) } }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

/// A row of colour swatches for picking a theme.
public struct ThemePicker: View {
    @Binding var selection: String
    public init(selection: Binding<String>) { _selection = selection }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 10)], spacing: 10) {
            ForEach(Theme.all) { theme in
                Button { selection = theme.id } label: {
                    VStack(spacing: 6) {
                        Circle().fill(theme.accentColor).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: selection == theme.id ? 2 : 0))
                            .shadow(color: theme.accentColor.opacity(selection == theme.id ? 0.6 : 0), radius: 6)
                        Text(theme.name).font(.caption)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(selection == theme.id ? theme.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
