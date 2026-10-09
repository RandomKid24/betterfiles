import AppKit

/// Right-click menu shared by the details and icon views. Rebuilt on each open so it reflects the selection.
@MainActor
final class ContextMenu: NSObject, NSMenuDelegate {
    let model: BrowserModel
    var rename: () -> Void = {}

    init(_ model: BrowserModel) { self.model = model }

    func build() -> NSMenu { let m = NSMenu(); m.delegate = self; return m }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector) { menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self }
        let picked = model.selectedItems
        if !picked.isEmpty {
            add("Open", #selector(open))
            add(picked.count > 1 ? "Rename \(picked.count) Items\u{2026}" : "Rename", #selector(doRename))
            menu.addItem(.separator())
            add("Cut", #selector(cut)); add("Copy", #selector(copyItems))
        }
        add("Paste", #selector(paste)); menu.addItem(.separator()); add("New Folder", #selector(newFolder))
        if !picked.isEmpty {
            menu.addItem(.separator())
            if picked.contains(where: { $0.url.pathExtension.lowercased() == "zip" }) { add("Extract", #selector(extract)) }
            add("Compress", #selector(compress))
            if picked.contains(where: \.isFolder) { add("Add to Sidebar", #selector(addToSidebar)) }
            menu.addItem(.separator())
        }
        add("Copy Path", #selector(copyPath))
        add("Open in Terminal", #selector(terminal))
        add("Get Info", #selector(info))
        if !picked.isEmpty { menu.addItem(.separator()); add("Move to Trash", #selector(trash)) }
    }

    @objc private func open() { model.openSelection() }
    @objc private func doRename() { if model.selection.count > 1 { model.beginBatchRename() } else { rename() } }
    @objc private func extract() { model.extract() }
    @objc private func compress() { model.compress() }
    @objc private func addToSidebar() { model.addToSidebar() }
    @objc private func copyPath() { model.copyPath() }
    @objc private func terminal() { model.openTerminal() }
    @objc private func info() { model.getInfo() }
    @objc private func cut() { model.cutSelection() }
    @objc private func copyItems() { model.copySelection() }
    @objc private func paste() { model.paste() }
    @objc private func newFolder() { model.newFolder() }
    @objc private func trash() { model.trashSelection() }
}
