import AppKit
import SwiftUI
import FilesCore

final class Node: NSObject {
    let url: URL
    let name: String
    let symbol: String
    let isHeader: Bool
    var isFavorite = false
    private(set) var children: [Node]?   // nil until first expanded (headers get theirs up front)

    init(url: URL, name: String, symbol: String = "folder") {
        self.url = url
        self.name = name
        self.symbol = symbol
        isHeader = false
    }

    init(header: String, children: [Node]) {
        url = URL(fileURLWithPath: "/")
        name = header
        symbol = ""
        isHeader = true
        self.children = children
    }

    /// Non-hidden sub-folders, loaded on first use.
    func loadChildren() -> [Node] {
        if let children { return children }
        let folders = ((try? FolderListing.list(url)) ?? []).filter { $0.isFolder && !$0.isHidden }
        let nodes = Sorter.sort(folders, by: .name, ascending: true).map { Node(url: $0.url, name: $0.name) }
        children = nodes
        return nodes
    }
}

struct SidebarView: NSViewRepresentable {
    let model: BrowserModel
    let url: URL
    let favorites: [URL]   // read by the parent's body so SwiftUI calls updateNSView when they change
    let style: Int         // Settings.revision, same idea

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let outline = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.style = .sourceList
        outline.rowSizeStyle = .default
        outline.dataSource = c
        outline.delegate = c
        outline.registerForDraggedTypes([.fileURL])
        outline.menu = c.removeMenu()
        c.outline = outline
        c.rebuild()

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model   // the active pane can change
        if c.favoritesInTree != favorites || c.appliedStyle != style { c.rebuild() }
        c.reveal(url)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var model: BrowserModel
        weak var outline: NSOutlineView?
        private var roots: [Node] = []   // section headers
        private(set) var favoritesInTree: [URL] = []
        private(set) var appliedStyle = -1
        private var syncing = false
        private var lastRevealed: String?

        private var places: [Node] { roots.flatMap { $0.children ?? [] } }

        init(_ model: BrowserModel) {
            self.model = model
            super.init()
            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.rebuild() }
                }
            }
        }

        private func makeRoots() -> [Node] {
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var places = [Node(url: home, name: "Home", symbol: "house")]
            for (folder, symbol) in [("Desktop", "menubar.dock.rectangle"), ("Documents", "doc.text"), ("Downloads", "arrow.down.circle")] {
                places.append(Node(url: home.appendingPathComponent(folder), name: folder, symbol: symbol))
            }
            places.append(Node(url: URL(fileURLWithPath: "/Applications"), name: "Applications", symbol: "square.grid.2x2"))
            favoritesInTree = Favorites.shared.urls
            for f in favoritesInTree {
                let n = Node(url: f, name: f.lastPathComponent, symbol: "star")
                n.isFavorite = true
                places.append(n)
            }
            var out = [Node(header: "Favorites", children: places)]
            if Settings.shared.showLocations {
                let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
                let nodes = volumes.map { v in
                    Node(url: v, name: (try? v.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? v.lastPathComponent, symbol: "externaldrive")
                }
                if !nodes.isEmpty { out.append(Node(header: "Locations", children: nodes)) }
            }
            return out
        }

        /// Favorites, drives or settings changed.
        func rebuild() {
            roots = makeRoots()
            appliedStyle = Settings.shared.revision
            lastRevealed = nil
            guard let ov = outline else { return }
            ov.reloadData()
            roots.forEach { ov.expandItem($0) }
        }

        // Right-click a favorite to unpin it.
        func removeMenu() -> NSMenu { let m = NSMenu(); m.delegate = self; return m }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let ov = outline, ov.clickedRow >= 0, let node = ov.item(atRow: ov.clickedRow) as? Node, node.isFavorite else { return }
            let item = menu.addItem(withTitle: "Remove from Sidebar", action: #selector(removeFavorite(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = node.url
        }

        @objc private func removeFavorite(_ sender: NSMenuItem) {
            if let url = sender.representedObject as? URL { Favorites.shared.remove(url) }
        }

        // MARK: data source

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let node = item as? Node else { return roots.count }
            return node.loadChildren().count
        }

        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let node = item as? Node else { return roots[index] }
            return node.loadChildren()[index]
        }

        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? Node else { return false }
            return node.isHeader || (node.children.map { !$0.isEmpty } ?? true)
        }

        // MARK: delegate

        func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool { (item as? Node)?.isHeader ?? false }
        func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { !((item as? Node)?.isHeader ?? false) }
        func outlineView(_ ov: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool { !((item as? Node)?.isHeader ?? false) }
        func outlineView(_ ov: NSOutlineView, shouldCollapseItem item: Any) -> Bool { !((item as? Node)?.isHeader ?? false) }

        func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            if (item as? Node)?.isHeader == true { return nil }
            return ThemedRowView()
        }

        func outlineView(_ ov: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let id = NSUserInterfaceItemIdentifier(node.isHeader ? "header" : "node")
            let cell = (ov.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = id
                let text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingTail
                text.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(text)
                c.textField = text
                if node.isHeader {
                    text.font = .systemFont(ofSize: 11, weight: .semibold)
                    text.textColor = .tertiaryLabelColor
                    NSLayoutConstraint.activate([
                        text.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                        text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    ])
                } else {
                    let icon = NSImageView()
                    icon.translatesAutoresizingMaskIntoConstraints = false
                    c.addSubview(icon)
                    c.imageView = icon
                    text.font = .systemFont(ofSize: 13)
                    NSLayoutConstraint.activate([
                        icon.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                        icon.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                        icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                        text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7),
                        text.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                        text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    ])
                }
                return c
            }()
            cell.textField?.stringValue = node.isHeader ? node.name.uppercased() : node.name
            if !node.isHeader {
                cell.imageView?.image = NSImage(systemSymbolName: node.symbol, accessibilityDescription: nil)
                cell.imageView?.symbolConfiguration = .init(pointSize: 14, weight: .regular)
                cell.imageView?.contentTintColor = Settings.shared.theme.accentNS
            }
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let ov = outline, ov.selectedRow >= 0, let node = ov.item(atRow: ov.selectedRow) as? Node, !node.isHeader else { return }
            lastRevealed = node.url.standardizedFileURL.path // we are already there; no need to re-reveal
            model.navigate(to: node.url)
        }

        func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let node = item as? Node, !node.isHeader else { return [] }
            ov.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return dropOperation
        }

        func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let node = item as? Node, !node.isHeader else { return false }
            model.drop(droppedURLs(info), onto: node.url, copy: NSEvent.modifierFlags.contains(.option))
            return true
        }

        // MARK: follow the current folder

        func reveal(_ target: URL) {
            guard let ov = outline else { return }
            let path = target.standardizedFileURL.path
            guard path != lastRevealed else { return }
            lastRevealed = path

            func contains(_ root: Node) -> Bool {
                let r = root.url.standardizedFileURL.path
                return path == r || path.hasPrefix(r == "/" ? "/" : r + "/")
            }
            guard let root = places.filter(contains).max(by: { $0.url.path.count < $1.url.path.count }) else {
                syncing = true; ov.deselectAll(nil); syncing = false
                return
            }
            var node = root
            syncing = true
            defer { syncing = false }
            // Only open a place when the target is inside it; selecting Home itself shouldn't unfold every sub-folder.
            if path != root.url.standardizedFileURL.path { ov.expandItem(root) }
            let relative = path.dropFirst(root.url.standardizedFileURL.path == "/" ? 1 : root.url.standardizedFileURL.path.count)
            for part in relative.split(separator: "/") {
                guard let next = node.loadChildren().first(where: { $0.name == String(part) }) else { break }
                ov.expandItem(next)
                node = next
            }
            let row = ov.row(forItem: node)
            if node.url.standardizedFileURL.path != path {
                // Target isn't in the tree: keep the ancestor visible but unselected so clicking it navigates.
                if row >= 0 { ov.scrollRowToVisible(row) }
                ov.deselectAll(nil)
            } else if row >= 0 {
                ov.selectRowIndexes([row], byExtendingSelection: false)
                ov.scrollRowToVisible(row)
            }
        }
    }
}
