import AppKit
import LauncherCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController!
    private var item: NSStatusItem!
    private let hotkey = Hotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterLauncher")
        let model = Model(usage: Usage(url: dir.appendingPathComponent("usage.json")))
        controller = PanelController(model: model)

        // RegisterEventHotKey succeeds even while Spotlight owns Cmd+Space, so check Spotlight's setting too.
        let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let registered = hotkey.register { [weak self] in
            MainActor.assumeIsolated { self?.controller.toggle() }
        }
        let ok = registered && !SpotlightShortcut.isEnabled(symbolic)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "BetterLauncher")
        let menu = NSMenu()
        // action: nil makes this a disabled, informational line.
        menu.addItem(withTitle: ok
            ? "Cmd+Space opens the launcher"
            : "Cmd+Space is taken: turn off Spotlight's shortcut in System Settings > Keyboard > Keyboard Shortcuts > Spotlight",
            action: nil, keyEquivalent: "")
        let show = NSMenuItem(title: "Show launcher", action: #selector(showLauncher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func showLauncher() { controller.show() }
}
