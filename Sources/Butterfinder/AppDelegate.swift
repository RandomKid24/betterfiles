import AppKit
import SwiftUI
import FilesCore
import Shared

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let tabs = Tabs()
    private var model: BrowserModel { tabs.current.active }
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.shared.applyAppearance()
        buildMenu()
        let hosting = NSHostingController(rootView: BrowserView(tabs: tabs))
        hosting.sizingOptions = [] // the window decides its size, not the SwiftUI content
        window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.title = "Butterfinder"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.setFrameAutosaveName("ButterfinderWindow")
        LoginItem.enableOnFirstRun()
        // Started by macOS at login: stay quiet in the background until a window is wanted (Dock click or the launcher).
        if LoginItem.launchedAtLogin {
            NSApp.setActivationPolicy(.regular)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }

        // Paths from the launcher: as an argument when we were started for it, as a notification when already running.
        // Only real paths count: anything starting with "-" is a flag (ours or macOS's), never a folder.
        let args = Array(CommandLine.arguments.dropFirst())
        if let i = args.firstIndex(of: "--select"), args.indices.contains(i + 1) {
            model.show(path: args[i + 1], select: true)
        } else if let path = args.first(where: { !$0.hasPrefix("-") && $0.hasPrefix("/") }) {
            model.show(path: path, select: false)
        }
        // Developer options (used for README screenshots): `--split <folder>` opens the second pane there,
        // `--open-settings [general|appearance|shortcuts]` opens Settings.
        let cli = CommandLine.arguments
        if let i = cli.firstIndex(of: "--split"), cli.indices.contains(i + 1) {
            tabs.current.toggleSplit()
            tabs.current.secondary?.navigate(to: URL(fileURLWithPath: cli[i + 1]))
        }
        if cli.contains("--open-settings") { SettingsWindow.show() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.butterfinder.open"), object: nil, queue: .main) { [weak self] n in
            guard let path = n.userInfo?["path"] as? String else { return }
            let select = n.userInfo?["select"] as? Bool ?? false
            MainActor.assumeIsolated {
                self?.model.show(path: path, select: select)
                self?.window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }

    // "Open With > Butterfinder" on a folder.
    func application(_ app: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.show(path: url.path, select: false) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: actions (menu items that need the model; cut/copy/paste/select-all use the responder chain instead)

    @objc private func trash() {
        if NSApp.keyWindow?.firstResponder is NSText { return } // Cmd+Delete belongs to the text field while editing
        model.trashSelection()
    }
    @objc private func duplicate() { model.duplicate() }
    @objc private func makeAlias() { model.makeAlias() }
    @objc private func sortBy(_ i: NSMenuItem) { if let c = Column(rawValue: i.representedObject as? String ?? "") { model.setSort(c, ascending: model.ascending) } }
    @objc private func toggleOrder() { model.setSort(model.sortColumn, ascending: !model.ascending) }
    @objc private func goRecent(_ i: NSMenuItem) { if let u = i.representedObject as? URL { model.navigate(to: u) } }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in Recents.shared.urls {
            let i = menu.addItem(withTitle: url.path == "/" ? "/" : url.lastPathComponent, action: #selector(goRecent(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = url
            i.toolTip = url.path
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "No recent folders", action: nil, keyEquivalent: "").isEnabled = false }
    }

    @objc private func openSettings() { SettingsWindow.show() }
    @objc private func toggleHidden() { Settings.shared.showHidden.toggle() }
    @objc private func undo() {
        // Text fields keep their own Cmd+Z while editing.
        if NSApp.keyWindow?.firstResponder is NSText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { model.undo() }
    }
    @objc private func comparePanes() { tabs.current.comparePanes() }
    @objc private func split() { tabs.current.toggleSplit() }
    @objc private func copyToOther() { tabs.current.sendToOther(move: false) }
    @objc private func moveToOther() { tabs.current.sendToOther(move: true) }
    @objc private func compress() { model.compress() }
    @objc private func getInfo() { model.getInfo() }
    @objc private func copyPath() { model.copyPath() }
    @objc private func terminal() { model.openTerminal() }
    @objc private func newTab() { tabs.new() }
    @objc private func closeTab() { if !tabs.close() { window.performClose(nil) } }
    @objc private func nextTab() { tabs.step(1) }
    @objc private func prevTab() { tabs.step(-1) }
    @objc private func newFolder() { model.newFolder() }
    @objc private func reload() { model.reload() }
    @objc private func showDetails() { model.setViewMode(.details) }
    @objc private func showIcons() { model.setViewMode(.icons) }
    @objc private func togglePreview() { model.togglePreview() }
    @objc private func back() { model.goBack() }
    @objc private func forward() { model.goForward() }
    @objc private func up() { model.goUp() }
    @objc private func focusAddress() { model.addressFocusToken += 1 }
    @objc private func focusFilter() { model.filterFocusToken += 1 }

    // MARK: menu

    private func buildMenu() {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let top = NSMenuItem(); main.addItem(top)
            let menu = NSMenu(title: title); items.forEach(menu.addItem); top.submenu = menu
        }
        func item(_ title: String, _ action: Selector, _ key: String = "", mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            i.target = target
            return i
        }
        let upKey = String(UnicodeScalar(NSUpArrowFunctionKey)!)

        add("Butterfinder", [
            item("About Butterfinder", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings\u{2026}", #selector(openSettings), ",", target: self),
            .separator(),
            item("Hide Butterfinder", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit Butterfinder", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            item("New Tab", #selector(newTab), "t", target: self),
            item("Close Tab", #selector(closeTab), "w", target: self),
            item("Next Tab", #selector(nextTab), "]", mods: [.command, .shift], target: self),
            item("Previous Tab", #selector(prevTab), "[", mods: [.command, .shift], target: self),
            .separator(),
            item("New Folder", #selector(newFolder), "n", mods: [.command, .shift], target: self),
            item("Move to Trash", #selector(trash), "\u{8}", target: self),
            item("Get Info", #selector(getInfo), "i", target: self),
            item("Duplicate", #selector(duplicate), "d", target: self),
            item("Make Alias", #selector(makeAlias), "a", mods: [.command, .control], target: self),
            item("Compress", #selector(compress), target: self),
            .separator(),
            item("Copy Path", #selector(copyPath), "c", mods: [.command, .option], target: self),
            item("Open Terminal Here", #selector(terminal), "t", mods: [.command, .option], target: self),
            .separator(),
            item("Reload", #selector(reload), "r", target: self),
        ])
        add("Edit", [
            item("Undo", #selector(undo), "z", target: self),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("View", [
            item("Details", #selector(showDetails), "1", target: self),
            item("Icons", #selector(showIcons), "2", target: self),
            item("Show Hidden Files", #selector(toggleHidden), ".", mods: [.command, .shift], target: self),
            item("Compare Panes\u{2026}", #selector(comparePanes), "k", mods: [.command, .option], target: self),
            item("Split View", #selector(split), "\\", target: self),
            item("Copy to Other Pane", #selector(copyToOther), String(UnicodeScalar(NSF5FunctionKey)!), mods: [], target: self),
            item("Move to Other Pane", #selector(moveToOther), String(UnicodeScalar(NSF6FunctionKey)!), mods: [], target: self),
            item("Preview Pane", #selector(togglePreview), "p", mods: [.command, .shift], target: self),
        ])
        add("Go", [
            item("Back", #selector(back), "[", target: self),
            item("Forward", #selector(forward), "]", target: self),
            item("Enclosing Folder", #selector(up), upKey, target: self),
            .separator(),
            item("Address Bar", #selector(focusAddress), "l", target: self),
            item("Filter", #selector(focusFilter), "f", target: self),
        ])
        // Sort By (View menu) and Recent Folders (Go menu) are submenus.
        if let view = main.items.first(where: { $0.submenu?.title == "View" })?.submenu {
            let sort = NSMenuItem(title: "Sort By", action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Sort By")
            for (title, col) in [("Name", Column.name), ("Date Modified", .modified), ("Size", .size), ("Kind", .kind)] {
                let i = sub.addItem(withTitle: title, action: #selector(sortBy(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = col.rawValue
            }
            sub.addItem(.separator())
            sub.addItem(withTitle: "Reverse Order", action: #selector(toggleOrder), keyEquivalent: "").target = self
            sort.submenu = sub
            view.insertItem(sort, at: 2)
        }
        if let go = main.items.first(where: { $0.submenu?.title == "Go" })?.submenu {
            let recent = NSMenuItem(title: "Recent Folders", action: nil, keyEquivalent: "")
            let sub = NSMenu(title: "Recent Folders")
            sub.delegate = self
            recent.submenu = sub
            go.insertItem(recent, at: 3)
        }
        add("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = main
    }
}
