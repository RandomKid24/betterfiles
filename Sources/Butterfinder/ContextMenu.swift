import AppKit
import FilesCore

/// Right-click menu shared by the details and icon views. Rebuilt on each open so it reflects the selection.
@MainActor
final class ContextMenu: NSObject, NSMenuDelegate {
    let model: BrowserModel
    var rename: () -> Void = {}

    init(_ model: BrowserModel) { self.model = model }

    private static let symbols: [String: String] = [
        "Open": "arrow.up.forward.app", "Open With": "square.grid.2x2", "Open in New Tab": "plus.square.on.square",
        "Open in Other Pane": "rectangle.split.2x1", "Rename": "pencil", "Cut": "scissors", "Copy": "doc.on.doc",
        "Paste": "doc.on.clipboard", "New Folder": "folder.badge.plus", "Extract": "arrow.up.bin", "Compress": "archivebox",
        "Duplicate": "plus.square.on.square", "Make Alias": "link", "Tags": "tag", "Add to Sidebar": "star",
        "Copy Path": "list.clipboard", "Reveal in Finder": "magnifyingglass", "Open in Terminal": "terminal",
        "Get Info": "info.circle", "Move to Trash": "trash", "Share": "square.and.arrow.up", "New File": "doc.badge.plus", "Move to\u{2026}": "arrowshape.turn.up.right", "Copy to\u{2026}": "plus.rectangle.on.folder", "Calculate Size": "chart.pie",
    ]

    static func icon(for title: String) -> NSImage? {
        let key = title.hasPrefix("Rename") ? "Rename" : title
        return symbols[key].flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }

    func build() -> NSMenu { let m = NSMenu(); m.delegate = self; return m }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = Self.icon(for: title)
        }
        let picked = model.selectedItems
        if !picked.isEmpty {
            add("Open", #selector(open))
            if picked.allSatisfy({ !$0.isFolder }) {
                let openWith = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                openWith.image = Self.icon(for: "Open With")
                let sub = NSMenu()
                for app in NSWorkspace.shared.urlsForApplications(toOpen: picked[0].url).prefix(12) {
                    let i = sub.addItem(withTitle: app.deletingPathExtension().lastPathComponent, action: #selector(openWithApp(_:)), keyEquivalent: "")
                    i.target = self
                    i.representedObject = app
                    let icon = NSWorkspace.shared.icon(forFile: app.path)
                    icon.size = NSSize(width: 16, height: 16)
                    i.image = icon
                }
                openWith.submenu = sub
                menu.addItem(openWith)
            }
            if picked.contains(where: \.isFolder) {
                add("Open in New Tab", #selector(newTab))
                add("Open in Other Pane", #selector(otherPane))
            }
            add(picked.count > 1 ? "Rename \(picked.count) Items\u{2026}" : "Rename", #selector(doRename))
            menu.addItem(.separator())
            add("Cut", #selector(cut)); add("Copy", #selector(copyItems))
        }
        add("Paste", #selector(paste)); menu.addItem(.separator()); add("New Folder", #selector(newFolder)); add("New File", #selector(newFile))
        if !picked.isEmpty {
            menu.addItem(.separator())
            if picked.contains(where: { $0.url.pathExtension.lowercased() == "zip" }) { add("Extract", #selector(extract)) }
            let tagsItem = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
            tagsItem.image = Self.icon(for: "Tags")
            let tagsMenu = NSMenu()
            for (name, hex) in Tags.standard {
                let i = tagsMenu.addItem(withTitle: name, action: #selector(toggleTag(_:)), keyEquivalent: "")
                i.target = self
                i.state = picked.allSatisfy({ $0.tags.contains(name) }) ? .on : .off
                let dot = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
                    NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1).setFill()
                    NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1)).fill()
                    return true
                }
                i.image = dot
            }
            tagsItem.submenu = tagsMenu
            menu.addItem(tagsItem)
            add("Move to\u{2026}", #selector(moveTo))
            add("Copy to\u{2026}", #selector(copyTo))
            add("Duplicate", #selector(duplicate))
            add("Make Alias", #selector(alias))
            add("Compress", #selector(compress))
            if picked.contains(where: \.isFolder) { add("Add to Sidebar", #selector(addToSidebar)) }
            menu.addItem(.separator())
        }
        add("Copy Path", #selector(copyPath))
        add("Reveal in Finder", #selector(reveal))
        add("Open in Terminal", #selector(terminal))
        if picked.contains(where: \.isFolder) { add("Calculate Size", #selector(calcSize)) }
        add("Get Info", #selector(info))
        if !picked.isEmpty {
            // AirDrop, Messages, Mail ... whatever macOS offers for these files.
            let urls = picked.map(\.url)
            let services = NSSharingService.sharingServices(forItems: urls)
            if !services.isEmpty {
                let shareItem = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
                shareItem.image = Self.icon(for: "Share")
                let sub = NSMenu()
                for service in services {
                    let i = sub.addItem(withTitle: service.menuItemTitle, action: #selector(share(_:)), keyEquivalent: "")
                    i.target = self
                    i.image = service.image
                    i.representedObject = service
                }
                shareItem.submenu = sub
                menu.addItem(shareItem)
            }
        }
        if !picked.isEmpty { menu.addItem(.separator()); add("Move to Trash", #selector(trash)) }
    }

    @objc private func open() { model.openSelection() }
    @objc private func doRename() { if model.selection.count > 1 { model.beginBatchRename() } else { rename() } }
    @objc private func extract() { model.extract() }
    @objc private func compress() { model.compress() }
    @objc private func addToSidebar() { model.addToSidebar() }
    @objc private func copyPath() { model.copyPath() }
    @objc private func terminal() { model.openTerminal() }
    @objc private func openWithApp(_ i: NSMenuItem) { if let app = i.representedObject as? URL { model.openWith(app) } }
    @objc private func newTab() { model.openFolderInNewTab() }
    @objc private func otherPane() { model.openFolderInOtherPane() }
    @objc private func toggleTag(_ i: NSMenuItem) { model.toggleTag(i.title) }
    @objc private func duplicate() { model.duplicate() }
    @objc private func alias() { model.makeAlias() }
    @objc private func reveal() { model.revealInFinder() }
    @objc private func calcSize() { model.calculateSizes() }
    @objc private func share(_ i: NSMenuItem) {
        (i.representedObject as? NSSharingService)?.perform(withItems: model.selectedItems.map(\.url))
    }
    @objc private func info() { model.getInfo() }
    @objc private func cut() { model.cutSelection() }
    @objc private func copyItems() { model.copySelection() }
    @objc private func paste() { model.paste() }
    @objc private func newFile() { model.newFile() }
    @objc private func moveTo() { model.chooseDestination(copy: false) }
    @objc private func copyTo() { model.chooseDestination(copy: true) }
    @objc private func newFolder() { model.newFolder() }
    @objc private func trash() { model.trashSelection() }
}
