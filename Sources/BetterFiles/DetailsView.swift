import AppKit
import SwiftUI
import FilesCore

final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onRename: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()   // Return, keypad Enter
        case 120: onRename?()    // F2
        default: super.keyDown(with: event)
        }
    }

    // Found through the responder chain by the Edit menu.
    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func cut(_ sender: Any?) { onCut?() }
    @objc func paste(_ sender: Any?) { onPaste?() }
}

struct DetailsView: NSViewRepresentable {
    let model: BrowserModel
    // These are read by the parent's body so SwiftUI calls updateNSView when any of them change.
    let version: Int
    let selection: Set<URL>
    let sort: Column
    let ascending: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = FileTableView()
        table.style = .fullWidth
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.usesAlternatingRowBackgroundColors = true
        table.autosaveName = "BetterFilesDetails"
        table.autosaveTableColumns = true

        for (column, title, width) in [(Column.name, "Name", 380.0), (.modified, "Date modified", 170),
                                       (.size, "Size", 90), (.kind, "Kind", 160)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            col.title = title
            col.width = width
            col.minWidth = 60
            col.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            table.addTableColumn(col)
        }
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.onOpen = { [weak model] in model?.openSelection() }
        table.onRename = { [weak c, weak table] in if let table { c?.beginRename(table) } }
        table.onCopy = { [weak model] in model?.copySelection() }
        table.onCut = { [weak model] in model?.cutSelection() }
        table.onPaste = { [weak model] in model?.paste() }
        c.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? FileTableView else { return }
        context.coordinator.update(table, version: version, selection: selection, sort: sort, ascending: ascending)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        let model: BrowserModel
        weak var table: FileTableView?
        private var items: [FileItem] = []
        private var lastVersion = -1
        private var syncing = false

        init(_ model: BrowserModel) { self.model = model }

        func update(_ table: FileTableView, version: Int, selection: Set<URL>, sort: Column, ascending: Bool) {
            syncing = true
            defer { syncing = false }
            if version != lastVersion {
                items = model.visible
                lastVersion = version
                table.reloadData()
            }
            let wanted = NSSortDescriptor(key: sort.rawValue, ascending: ascending)
            if table.sortDescriptors.first?.key != wanted.key || table.sortDescriptors.first?.ascending != ascending {
                table.sortDescriptors = [wanted]
            }
            let rows = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
            if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
        }

        // MARK: data source / delegate

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard let id = column?.identifier, let kind = Column(rawValue: id.rawValue), row < items.count else { return nil }
            let item = items[row]
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? makeCell(id, withIcon: kind == .name)
            switch kind {
            case .name:
                cell.imageView?.image = Icons.icon(for: item)
                cell.textField?.stringValue = item.name
                cell.textField?.delegate = self
                cell.textField?.alphaValue = item.isHidden ? 0.55 : 1
            case .modified:
                cell.textField?.stringValue = item.modified?.formatted(date: .abbreviated, time: .shortened) ?? ""
            case .size:
                cell.textField?.stringValue = item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
                cell.textField?.alignment = .right
            case .kind:
                cell.textField?.stringValue = item.kind
            }
            return cell
        }

        private func makeCell(_ id: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            if withIcon {
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                cell.imageView = icon
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                ])
            } else {
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4).isActive = true
            }
            NSLayoutConstraint.activate([
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url : nil })
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !syncing, let d = tableView.sortDescriptors.first, let key = d.key, let column = Column(rawValue: key) else { return }
            model.setSort(column, ascending: d.ascending)
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            row < items.count ? items[row].name : nil
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            model.open(items[table.clickedRow])
        }

        // MARK: in-place rename (F2)

        func beginRename(_ table: NSTableView) {
            let row = table.selectedRow
            guard row >= 0, let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            field.isEditable = true
            table.window?.makeFirstResponder(field)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let table else { return }
            field.isEditable = false
            let row = table.row(for: field)
            table.window?.makeFirstResponder(table)
            guard row >= 0, row < items.count else { return }
            let item = items[row]
            if field.stringValue != item.name { model.rename(item, to: field.stringValue) } else { field.stringValue = item.name }
        }
    }
}
