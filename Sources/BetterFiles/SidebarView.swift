import AppKit
import SwiftUI
import FilesCore

final class Node: NSObject {
    let url: URL
    let name: String
    private(set) var children: [Node]?   // nil until first expanded

    init(url: URL, name: String) {
        self.url = url
        self.name = name
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
        c.outline = outline

        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.reveal(url)
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        let model: BrowserModel
        weak var outline: NSOutlineView?
        private let roots: [Node]
        private var syncing = false
        private var lastRevealed: String?

        init(_ model: BrowserModel) {
            self.model = model
            let fm = FileManager.default
            let home = fm.homeDirectoryForCurrentUser
            var nodes = [Node(url: home, name: "Home")]
            for (folder, title) in [("Desktop", "Desktop"), ("Documents", "Documents"), ("Downloads", "Downloads")] {
                nodes.append(Node(url: home.appendingPathComponent(folder), name: title))
            }
            nodes.append(Node(url: URL(fileURLWithPath: "/Applications"), name: "Applications"))
            let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
            for v in volumes {
                let name = (try? v.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? v.lastPathComponent
                nodes.append(Node(url: v, name: name))
            }
            roots = nodes
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
            return node.children.map { !$0.isEmpty } ?? true
        }

        // MARK: delegate

        func outlineView(_ ov: NSOutlineView, viewFor column: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? Node else { return nil }
            let id = NSUserInterfaceItemIdentifier("node")
            let cell = (ov.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = id
                let icon = NSImageView(), text = NSTextField(labelWithString: "")
                text.lineBreakMode = .byTruncatingTail
                for sub in [icon, text] { sub.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(sub) }
                c.imageView = icon
                c.textField = text
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    icon.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            cell.textField?.stringValue = node.name
            cell.imageView?.image = NSWorkspace.shared.icon(for: .folder)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let ov = outline, ov.selectedRow >= 0, let node = ov.item(atRow: ov.selectedRow) as? Node else { return }
            lastRevealed = node.url.standardizedFileURL.path // we are already there; no need to re-reveal
            model.navigate(to: node.url)
        }

        func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard let node = item as? Node else { return [] }
            ov.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return dropOperation
        }

        func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let node = item as? Node else { return false }
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
            guard let root = roots.filter(contains).max(by: { $0.url.path.count < $1.url.path.count }) else {
                syncing = true; ov.deselectAll(nil); syncing = false
                return
            }
            var node = root
            syncing = true
            defer { syncing = false }
            ov.expandItem(root)
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
