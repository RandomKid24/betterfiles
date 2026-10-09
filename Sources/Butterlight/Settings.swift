import AppKit
import ServiceManagement
import SwiftUI
import Observation
import Shared

@MainActor @Observable
final class LSettings {
    static let shared = LSettings()
    private let d = UserDefaults.standard

    var themeID: String { didSet { d.set(themeID, forKey: "theme") } }
    var searchFiles: Bool { didSet { d.set(searchFiles, forKey: "searchFiles") } }
    var calculator: Bool { didSet { d.set(calculator, forKey: "calculator") } }
    var clipboard: Bool { didSet { d.set(clipboard, forKey: "clipboard") } }
    var webFallback: Bool { didSet { d.set(webFallback, forKey: "webFallback") } }
    var maxResults: Int { didSet { d.set(maxResults, forKey: "maxResults") } }
    var glass: Bool { didSet { d.set(glass, forKey: "glass") } }

    var theme: Theme { Theme.named(themeID) }

    private init() {
        func b(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) as? Bool ?? true }
        themeID = UserDefaults.standard.string(forKey: "theme") ?? "system"
        searchFiles = b("searchFiles"); calculator = b("calculator"); clipboard = b("clipboard"); webFallback = b("webFallback"); glass = b("glass")
        let m = UserDefaults.standard.integer(forKey: "maxResults")
        maxResults = m == 0 ? 8 : m
    }
}

enum LauncherSettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: LauncherSettingsView()))
            w.title = "Butterlight Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct LauncherSettingsView: View {
    @Bindable private var s = LSettings.shared
    @State private var login = SMAppService.mainApp.status == .enabled
    private let installed = Bundle.main.bundlePath.hasSuffix(".app")

    var body: some View {
        Form {
            Section("Search") {
                Toggle("Search files and folders", isOn: $s.searchFiles)
                Picker("Results shown", selection: $s.maxResults) {
                    ForEach([5, 8, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Extras") {
                Toggle("Calculator and unit conversion", isOn: $s.calculator)
                Toggle("Clipboard history (type \u{201C}clip\u{201D})", isOn: $s.clipboard)
                Toggle("Web search when nothing matches", isOn: $s.webFallback)
            }
            Section("Look") {
                ThemePicker(selection: $s.themeID)
                Toggle("Glass background", isOn: $s.glass)
            }
            Section("System") {
                Toggle("Open at login", isOn: Binding(get: { login }, set: { on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    login = SMAppService.mainApp.status == .enabled
                }))
                .disabled(!installed)
                if !installed { Text("Install the app with package.sh to enable this.").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}
