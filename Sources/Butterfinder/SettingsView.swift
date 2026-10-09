import AppKit
import SwiftUI
import Shared

enum SettingsWindow {
    private static var window: NSWindow?

    @MainActor static func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            w.title = "Butterfinder Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct SettingsView: View {
    @Bindable private var s = Settings.shared
    @Bindable private var prefs = Prefs.shared
    @State private var login = LoginItem.isEnabled
    @State private var tab = CommandLine.arguments.drop { $0 != "--open-settings" }.dropFirst().first(where: { !$0.hasPrefix("-") }) ?? "general"

    var body: some View {
        TabView(selection: $tab) {
            Form {
                Section("Files") {
                    Toggle("Show hidden files", isOn: $s.showHidden)
                    Toggle("Keep folders above files", isOn: $s.foldersFirst)
                    Toggle("Remember view, sort and zoom for each folder", isOn: $s.perFolderView)
                    Toggle("Ask before moving to the Trash", isOn: $s.confirmTrash)
                }
                Section("Startup") {
                    Toggle("Open at login (runs quietly in the background)", isOn: Binding(get: { login }, set: { on in
                        LoginItem.set(on)
                        login = LoginItem.isEnabled
                    }))
                    .disabled(!LoginItem.available)
                }
                Section("Window") {
                    Toggle("Show preview pane", isOn: $prefs.showPreview)
                    Toggle("Show status bar", isOn: $s.showStatusBar)
                    Toggle("Show drives in the sidebar", isOn: $s.showLocations)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }.tag("general")

            Form {
                Section("Theme") { ThemePicker(selection: $s.themeID) }
                Section("Look") {
                    Picker("Appearance", selection: $s.appearance) {
                        Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Picker("Row size", selection: $s.density) {
                        ForEach(Density.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Striped rows in the list", isOn: $s.stripedRows)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Appearance", systemImage: "paintpalette") }.tag("appearance")

            Form {
                Section("Navigation") {
                    shortcut("Back / Forward", "\u{2318}[  \u{2318}]")
                    shortcut("Enclosing folder", "\u{2318}\u{2191}")
                    shortcut("Address bar", "\u{2318}L")
                    shortcut("Filter", "\u{2318}F")
                    shortcut("New / close tab", "\u{2318}T  \u{2318}W")
                    shortcut("Split view", "\u{2318}\\")
                }
                Section("Files") {
                    shortcut("Quick Look", "Space")
                    shortcut("Rename", "F2 or Return on a name")
                    shortcut("New folder", "\u{21E7}\u{2318}N")
                    shortcut("Cut / Copy / Paste", "\u{2318}X  \u{2318}C  \u{2318}V")
                    shortcut("Undo", "\u{2318}Z")
                    shortcut("Move to Trash", "Delete or \u{2318}Delete")
                    shortcut("Copy / move to other pane", "F5  F6")
                    shortcut("Show hidden files", "\u{21E7}\u{2318}.")
                    shortcut("Get Info", "\u{2318}I")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag("shortcuts")
        }
        .frame(width: 520, height: 480)
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack { Text(name); Spacer(); Text(keys).foregroundStyle(.secondary).monospaced() }
    }
}
