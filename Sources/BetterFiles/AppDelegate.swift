import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tabs = Tabs()
    private var model: BrowserModel { tabs.current }
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let hosting = NSHostingController(rootView: BrowserView(tabs: tabs))
        hosting.sizingOptions = [] // the window decides its size, not the SwiftUI content
        window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.title = "BetterFiles"
        window.setFrameAutosaveName("BetterFilesMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // Paths from the launcher: as an argument when we were started for it, as a notification when already running.
        let args = CommandLine.arguments.dropFirst()
        if let first = args.first {
            if first == "--select", args.count > 1 { model.show(path: args[args.startIndex + 1], select: true) }
            else { model.show(path: first, select: false) }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.betterfiles.open"), object: nil, queue: .main) { [weak self] n in
            guard let path = n.userInfo?["path"] as? String else { return }
            let select = n.userInfo?["select"] as? Bool ?? false
            MainActor.assumeIsolated {
                self?.model.show(path: path, select: select)
                self?.window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }

    // "Open With > BetterFiles" on a folder.
    func application(_ app: NSApplication, open urls: [URL]) {
        if let url = urls.first { model.show(path: url.path, select: false) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: actions (menu items that need the model; cut/copy/paste/select-all use the responder chain instead)

    @objc private func trash() {
        if NSApp.keyWindow?.firstResponder is NSText { return } // Cmd+Delete belongs to the text field while editing
        model.trashSelection()
    }
    // Changes the system-wide default for opening folders; the other item hands it back to Finder.
    @objc private func makeDefault() { setFolderHandler("com.betterfiles.files") }
    @objc private func restoreFinder() { setFolderHandler("com.apple.finder") }

    private func setFolderHandler(_ bundleID: String) {
        let status = LSSetDefaultRoleHandlerForContentType("public.folder" as CFString, .all, bundleID as CFString)
        let alert = NSAlert()
        alert.messageText = status == noErr ? "Done" : "Couldn\u{2019}t change the default (error \(status))"
        alert.informativeText = status == noErr
            ? "Folders opened from other apps now use \(bundleID == "com.apple.finder" ? "Finder" : "BetterFiles"). Finder\u{2019}s own windows are unchanged."
            : "BetterFiles must be running from ~/Applications (run package.sh)."
        alert.runModal()
    }

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

        add("BetterFiles", [
            item("About BetterFiles", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide BetterFiles", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Make BetterFiles the Default for Folders", #selector(makeDefault), target: self),
            item("Restore Finder as Default for Folders", #selector(restoreFinder), target: self),
            .separator(),
            item("Quit BetterFiles", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
            item("New Tab", #selector(newTab), "t", target: self),
            item("Close Tab", #selector(closeTab), "w", target: self),
            item("Next Tab", #selector(nextTab), "]", mods: [.command, .shift], target: self),
            item("Previous Tab", #selector(prevTab), "[", mods: [.command, .shift], target: self),
            .separator(),
            item("New Folder", #selector(newFolder), "n", mods: [.command, .shift], target: self),
            item("Move to Trash", #selector(trash), "\u{8}", target: self),
            item("Reload", #selector(reload), "r", target: self),
        ])
        add("Edit", [
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("View", [
            item("Details", #selector(showDetails), "1", target: self),
            item("Icons", #selector(showIcons), "2", target: self),
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
        add("Window", [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")])
        NSApp.mainMenu = main
    }
}
