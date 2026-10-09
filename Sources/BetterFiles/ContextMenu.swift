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
        if !model.selection.isEmpty {
            add("Open", #selector(open)); add("Rename", #selector(doRename)); menu.addItem(.separator())
            add("Cut", #selector(cut)); add("Copy", #selector(copyItems))
        }
        add("Paste", #selector(paste)); menu.addItem(.separator()); add("New Folder", #selector(newFolder))
        if !model.selection.isEmpty { menu.addItem(.separator()); add("Move to Trash", #selector(trash)) }
    }

    @objc private func open() { model.openSelection() }
    @objc private func doRename() { rename() }
    @objc private func cut() { model.cutSelection() }
    @objc private func copyItems() { model.copySelection() }
    @objc private func paste() { model.paste() }
    @objc private func newFolder() { model.newFolder() }
    @objc private func trash() { model.trashSelection() }
}
