import AppKit
import Observation
import Shared

enum Density: String, CaseIterable { case compact, comfortable, spacious
    var rowHeight: CGFloat { switch self { case .compact: 22; case .comfortable: 28; case .spacious: 34 } }
}

/// Everything the user can switch on or off. Each change is saved at once and bumps `revision`, which the views watch.
@MainActor @Observable
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard
    private(set) var revision = 0

    var showHidden: Bool { didSet { save("showHidden", showHidden) } }
    var foldersFirst: Bool { didSet { save("foldersFirst", foldersFirst) } }
    var confirmTrash: Bool { didSet { save("confirmTrash", confirmTrash) } }
    var showStatusBar: Bool { didSet { save("showStatusBar", showStatusBar) } }
    var perFolderView: Bool { didSet { save("perFolderView", perFolderView) } }
    var showLocations: Bool { didSet { save("showLocations", showLocations) } }
    var stripedRows: Bool { didSet { save("stripedRows", stripedRows) } }
    var density: Density { didSet { save("density", density.rawValue) } }
    var dateStyle: String { didSet { save("dateStyle", dateStyle) } }          // abbreviated, numeric, relative
    var showTagDots: Bool { didSet { save("showTagDots", showTagDots) } }
    var colorFolders: Bool { didSet { save("colorFolders", colorFolders) } }
    var singleClickOpen: Bool { didSet { save("singleClickOpen", singleClickOpen) } }
    var startAtLast: Bool { didSet { save("startAtLast", startAtLast) } }
    var themeID: String { didSet { save("theme", themeID) } }
    var appearance: String { didSet { save("appearance", appearance); applyAppearance() } }   // system, light, dark

    var theme: Theme { Theme.named(themeID) }

    private init() {
        func b(_ k: String, _ def: Bool) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? def }
        showHidden = b("showHidden", false)
        foldersFirst = b("foldersFirst", true)
        confirmTrash = b("confirmTrash", false)
        showStatusBar = b("showStatusBar", true)
        showLocations = b("showLocations", true)
        perFolderView = b("perFolderView", true)
        stripedRows = b("stripedRows", false)
        density = Density(rawValue: UserDefaults.standard.string(forKey: "density") ?? "") ?? .comfortable
        dateStyle = UserDefaults.standard.string(forKey: "dateStyle") ?? "abbreviated"
        showTagDots = b("showTagDots", true)
        colorFolders = b("colorFolders", true)
        singleClickOpen = b("singleClickOpen", false)
        startAtLast = b("startAtLast", false)
        themeID = UserDefaults.standard.string(forKey: "theme") ?? "system"
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
    }

    private func save(_ key: String, _ value: Any) {
        d.set(value, forKey: key)
        revision += 1
    }

    /// Where a new window starts: Home, or the folder you were last in.
    var startFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard startAtLast, let path = d.string(forKey: "lastFolder"), FileManager.default.fileExists(atPath: path) else { return home }
        return URL(fileURLWithPath: path)
    }

    func rememberFolder(_ url: URL) { d.set(url.path, forKey: "lastFolder") }

    func format(_ date: Date) -> String {
        switch dateStyle {
        case "numeric": return date.formatted(date: .numeric, time: .shortened)
        case "relative": return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        default: return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// Puts every option back to its default (favorites, tags and per-folder views are kept).
    func resetToDefaults() {
        showHidden = false; foldersFirst = true; confirmTrash = false; showStatusBar = true; showLocations = true
        perFolderView = true; stripedRows = false; density = .comfortable; themeID = "system"; appearance = "system"
        dateStyle = "abbreviated"; showTagDots = true; colorFolders = true; singleClickOpen = false; startAtLast = false
        Prefs.shared.showPreview = true
        Prefs.shared.previewWidth = 280; Prefs.shared.savePreviewWidth()
    }

    func applyAppearance() {
        NSApp.appearance = appearance == "light" ? NSAppearance(named: .aqua) : appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
    }
}

/// Selection drawn as a rounded pill in the theme's accent colour, instead of the stock system highlight.
final class ThemedRowView: NSTableRowView {
    override var isEmphasized: Bool { get { true } set {} }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .emphasized : .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        MainActor.assumeIsolated { Settings.shared.theme.accentNS }.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 1), xRadius: 7, yRadius: 7).fill()
    }
}
