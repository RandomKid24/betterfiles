import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = BrowserModel()
    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        let hosting = NSHostingController(rootView: BrowserView(model: model))
        hosting.sizingOptions = [] // the window decides its size, not the SwiftUI content
        window = NSWindow(contentViewController: hosting)
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.title = "BetterFiles"
        window.setFrameAutosaveName("BetterFilesMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: actions (menu items that need the model; cut/copy/paste/select-all use the responder chain instead)

    @objc private func trash() {
        if NSApp.keyWindow?.firstResponder is NSText { return } // Cmd+Delete belongs to the text field while editing
        model.trashSelection()
    }
    @objc private func reload() { model.reload() }
    @objc private func showDetails() { model.setViewMode(.details) }
    @objc private func showIcons() { model.setViewMode(.icons) }
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
            item("Quit BetterFiles", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("File", [
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
