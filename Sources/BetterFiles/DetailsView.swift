import AppKit
import SwiftUI
import FilesCore

final class FileTableView: NSTableView {
    var onOpen: (() -> Void)?
    var onRename: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?
    var onTrash: (() -> Void)?
    var onQuickLook: (() -> Void)?
    var onActivate: (() -> Void)?

    override func mouseDown(with event: NSEvent) { onActivate?(); super.mouseDown(with: event) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()   // Return, keypad Enter
        case 120: onRename?()    // F2
        case 49: onQuickLook?()  // Space
        case 51, 117: onTrash?() // Delete / forward delete; the Trash is recoverable
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
    let style: Int   // Settings.revision: read by the parent so SwiftUI calls updateNSView when a setting changes

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = FileTableView()
        table.style = .fullWidth
        table.rowHeight = 28
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.autosaveName = "BetterFilesDetails"
        table.autosaveTableColumns = true

        for (column, title, width) in [(Column.name, "Name", 380.0), (.modified, "Date modified", 170),
                                       (.created, "Date created", 170), (.size, "Size", 90), (.kind, "Kind", 160)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            col.title = title
            col.width = width
            col.minWidth = 60
            col.isHidden = column == .created   // off until chosen from the header menu
            col.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            table.addTableColumn(col)
        }
        table.headerView?.menu = c.headerMenu()
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.onOpen = { [weak model] in model?.openSelection() }
        table.onRename = { [weak c, weak table] in if let table { c?.beginRename(table) } }
        table.onCopy = { [weak model] in model?.copySelection() }
        table.onCut = { [weak model] in model?.cutSelection() }
        table.onPaste = { [weak model] in model?.paste() }
        table.onTrash = { [weak model] in model?.trashSelection() }
        table.onActivate = { [weak model] in model?.onActivate() }
        table.onQuickLook = { [weak model] in model?.quickLook() }
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        c.ctx.rename = { [weak c, weak table] in if let table { c?.beginRename(table) } }
        table.menu = c.ctx.build()
        c.table = table

        let scroll = NSScrollView()
        scroll.wantsLayer = true
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let table = scroll.documentView as? FileTableView else { return }
        context.coordinator.applyStyle(table)
        context.coordinator.update(table, version: version, selection: selection, sort: sort, ascending: ascending)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
        let model: BrowserModel
        weak var table: FileTableView?
        private var items: [FileItem] = []
        private var lastVersion = -1
        private var lastURL: URL?
        private var syncing = false

        let ctx: ContextMenu
        init(_ model: BrowserModel) { self.model = model; ctx = ContextMenu(model) }

        private var appliedStyle = -1

        // Right-click the column header to choose which columns show.
        func headerMenu() -> NSMenu { let m = NSMenu(); m.delegate = self; return m }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            for col in table.tableColumns where col.identifier.rawValue != Column.name.rawValue {
                let i = menu.addItem(withTitle: col.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                i.target = self
                i.representedObject = col
                i.state = col.isHidden ? .off : .on
            }
        }

        @objc private func toggleColumn(_ i: NSMenuItem) { (i.representedObject as? NSTableColumn)?.isHidden.toggle() }

        func applyStyle(_ table: FileTableView) {
            let st = Settings.shared
            guard st.revision != appliedStyle else { return }
            appliedStyle = st.revision
            table.rowHeight = st.density.rowHeight
            table.usesAlternatingRowBackgroundColors = st.stripedRows
            table.backgroundColor = st.theme.surfaceNS ?? .controlBackgroundColor
            table.reloadData()
        }

        func tableView(_ tv: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let id = NSUserInterfaceItemIdentifier("themedRow")
            if let reused = tv.makeView(withIdentifier: id, owner: nil) as? ThemedRowView { return reused }
            let v = ThemedRowView()
            v.identifier = id
            return v
        }

        func update(_ table: FileTableView, version: Int, selection: Set<URL>, sort: Column, ascending: Bool) {
            syncing = true
            defer { syncing = false }
            if version != lastVersion && (items.isEmpty || model.url != lastURL) {
                lastURL = model.url
                let t = CATransition(); t.type = .fade; t.duration = 0.18
                table.enclosingScrollView?.layer?.add(t, forKey: "fade")
            }
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
            // New Folder: start renaming it as soon as the listing shows it.
            if let url = model.pendingRename, let row = items.firstIndex(where: { $0.url == url }) {
                model.pendingRename = nil
                table.scrollRowToVisible(row)
                DispatchQueue.main.async { [weak self, weak table] in if let table { self?.beginRename(table) } }
            }
        }

        // MARK: data source / delegate

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
            guard let id = column?.identifier, let kind = Column(rawValue: id.rawValue), row < items.count else { return nil }
            let item = items[row]
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? (kind == .name ? makeNameCell(id) : makeCell(id, withIcon: false))
            switch kind {
            case .name:
                cell.imageView?.image = Icons.icon(for: item)
                cell.textField?.stringValue = item.name
                cell.textField?.delegate = self
                cell.textField?.alphaValue = item.isHidden ? 0.55 : 1
                (cell as? NameCell)?.dots.attributedStringValue = TagDots.string(item.tags)
            case .created:
                cell.textField?.stringValue = item.created?.formatted(date: .abbreviated, time: .shortened) ?? ""
                cell.textField?.textColor = .secondaryLabelColor
            case .modified:
                cell.textField?.stringValue = item.modified?.formatted(date: .abbreviated, time: .shortened) ?? ""
                cell.textField?.textColor = .secondaryLabelColor
            case .size:
                cell.textField?.stringValue = item.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "\u{2014}"
                cell.textField?.textColor = .secondaryLabelColor
                cell.textField?.alignment = .right
            case .kind:
                cell.textField?.stringValue = item.kind
                cell.textField?.textColor = .secondaryLabelColor
            }
            return cell
        }

        private func makeNameCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cell = NameCell()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingMiddle
            let icon = NSImageView()
            for v in [text, icon, cell.dots] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
            cell.textField = text
            cell.imageView = icon
            cell.dots.setContentHuggingPriority(.required, for: .horizontal)
            cell.dots.setContentCompressionResistancePriority(.required, for: .horizontal)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: cell.dots.leadingAnchor, constant: -4),
                cell.dots.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                cell.dots.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
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

        func tableView(_ tv: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            row < items.count ? items[row].url as NSURL : nil
        }

        func tableView(_ tv: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            // Only folders accept drops; aim at the row under the cursor even when the table proposes "between rows".
            let hovered = tv.row(at: tv.convert(info.draggingLocation, from: nil))
            guard hovered >= 0, hovered < items.count, items[hovered].isFolder, !items[hovered].isPackage else { return [] }
            tv.setDropRow(hovered, dropOperation: .on)
            return dropOperation
        }

        func tableView(_ tv: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
            guard row >= 0, row < items.count else { return false }
            model.drop(droppedURLs(info), onto: items[row].url, copy: NSEvent.modifierFlags.contains(.option))
            return true
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            model.open(items[table.clickedRow])
        }

        // MARK: in-place rename (F2)

        private var renaming: FileItem?

        func beginRename(_ table: NSTableView) {
            let row = table.selectedRow
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier(Column.name.rawValue))
            guard row >= 0, col >= 0, let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            renaming = row < items.count ? items[row] : nil
            guard renaming != nil else { return }
            field.isEditable = true
            table.window?.makeFirstResponder(field)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let table else { return }
            field.isEditable = false
            let item = renaming
            renaming = nil
            table.window?.makeFirstResponder(table)
            guard let item else { return }
            if field.stringValue != item.name { model.rename(item, to: field.stringValue) } else { field.stringValue = item.name }
        }
    }
}

/// Name column cell with a spot on the right for coloured tag dots.
final class NameCell: NSTableCellView {
    let dots = NSTextField(labelWithString: "")
}

enum TagDots {
    /// "●●" in each tag's colour (grey for tags without a standard colour).
    static func string(_ tags: [String]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for t in tags {
            let color = Tags.hex(for: t).map { NSColor(red: CGFloat(($0 >> 16) & 255) / 255, green: CGFloat(($0 >> 8) & 255) / 255, blue: CGFloat($0 & 255) / 255, alpha: 1) } ?? .tertiaryLabelColor
            out.append(NSAttributedString(string: "\u{25CF}", attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 11)]))
        }
        return out
    }
}
