import AppKit
import LauncherCore
import Shared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController!
    private var item: NSStatusItem!
    private let hotkey = Hotkey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Butterlight")
        let old = support.appendingPathComponent("BetterLauncher")   // pre-rename name: keep the history
        if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.moveItem(at: old, to: dir)
        }
        let model = Model(usage: Usage(url: dir.appendingPathComponent("usage.json")))
        controller = PanelController(model: model)
        LoginItem.enableOnFirstRun()
        // Developer option: `--demo-query "text"` opens the launcher with that text typed (used for README screenshots).
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--demo-query"), args.indices.contains(i + 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.controller.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { model.text = args[i + 1] }
            }
        }

        // RegisterEventHotKey succeeds even while Spotlight owns Cmd+Space, so check Spotlight's setting too.
        let symbolic = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        let registered = hotkey.register { [weak self] in
            MainActor.assumeIsolated { self?.controller.toggle() }
        }
        let ok = registered && !SpotlightShortcut.isEnabled(symbolic)

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Butterlight")
        let menu = NSMenu()
        // action: nil makes this a disabled, informational line.
        menu.addItem(withTitle: ok
            ? "Cmd+Space opens the launcher"
            : "Cmd+Space is taken: turn off Spotlight's shortcut in System Settings > Keyboard > Keyboard Shortcuts > Spotlight",
            action: nil, keyEquivalent: "")
        let prefs = NSMenuItem(title: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let show = NSMenuItem(title: "Show launcher", action: #selector(showLauncher), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        if LoginItem.available {
            let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
            login.target = self
            login.state = LoginItem.isEnabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        LoginItem.set(!LoginItem.isEnabled)
        sender.state = LoginItem.isEnabled ? .on : .off
    }

    @objc private func openSettings() { LauncherSettingsWindow.show() }

    @objc private func showLauncher() { controller.show() }
}
