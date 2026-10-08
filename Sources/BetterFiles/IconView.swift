import AppKit
import SwiftUI
import FilesCore

final class ZoomableCollectionView: NSCollectionView {
    var onZoom: ((Double) -> Void)?
    var onOpen: (() -> Void)?
    var onRename: (() -> Void)?
    var onCopy: (() -> Void)?
    var onCut: (() -> Void)?
    var onPaste: (() -> Void)?
    var onSelectionChanged: (() -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { onZoom?(event.scrollingDeltaY * 2) } else { super.scrollWheel(with: event) }
    }

    override func magnify(with event: NSEvent) { onZoom?(event.magnification * 200) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onOpen?()
        case 120: onRename?()
        default: super.keyDown(with: event)
        }
    }

    // NSCollectionView's own selectAll doesn't tell the delegate, so push the new selection ourselves.
    override func selectAll(_ sender: Any?) {
        super.selectAll(sender)
        onSelectionChanged?()
    }

    @objc func copy(_ sender: Any?) { onCopy?() }
    @objc func cut(_ sender: Any?) { onCut?() }
    @objc func paste(_ sender: Any?) { onPaste?() }
}

final class IconCell: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("IconCell")
    private(set) var representedURL: URL?
    private var requestedBucket = 0
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    override func loadView() {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.cornerRadius = 10
        icon.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingMiddle
        label.cell?.wraps = true
        for sub in [icon, label] { sub.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(sub) }
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: v.topAnchor, constant: 6),
            icon.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 6),
            icon.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -6),
            icon.bottomAnchor.constraint(equalTo: label.topAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -4),
            label.heightAnchor.constraint(lessThanOrEqualToConstant: 34),
        ])
        view = v
        imageView = icon
        textField = label
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : nil
        }
    }

    @MainActor
    func configure(_ item: FileItem, size: CGFloat, keepImage: Bool = false) {
        representedURL = item.url
        label.stringValue = item.name
        label.alphaValue = item.isHidden ? 0.55 : 1
        if !keepImage { icon.image = Icons.icon(for: item) }
        guard !item.isFolder else { return }
        let bucket = Thumbnails.bucket(for: size)
        requestedBucket = bucket
        Thumbnails.load(url: item.url, size: size) { [weak self] image in
            // The cell may have been reused for another file, or asked for a newer size, while the thumbnail loaded.
            if self?.representedURL == item.url, self?.requestedBucket == bucket { self?.icon.image = image }
        }
    }
}

struct IconView: NSViewRepresentable {
    let model: BrowserModel
    let version: Int
    let selection: Set<URL>
    let zoom: Double

    func makeCoordinator() -> Coordinator { Coordinator(model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        let cv = ZoomableCollectionView()
        cv.collectionViewLayout = layout
        cv.isSelectable = true
        cv.allowsMultipleSelection = true
        cv.register(IconCell.self, forItemWithIdentifier: IconCell.id)
        cv.dataSource = c
        cv.delegate = c
        cv.onZoom = { [weak model] delta in if let model { model.setZoom(model.zoom + delta) } }
        cv.onOpen = { [weak model] in model?.openSelection() }
        cv.onRename = { [weak c, weak cv] in if let cv { c?.beginRename(cv) } }
        cv.onCopy = { [weak model] in model?.copySelection() }
        cv.onCut = { [weak model] in model?.cutSelection() }
        cv.onPaste = { [weak model] in model?.paste() }
        cv.onSelectionChanged = { [weak c, weak cv] in if let c, let cv { c.pushSelection(cv) } }
        let double = NSClickGestureRecognizer(target: c, action: #selector(Coordinator.doubleClicked(_:)))
        double.numberOfClicksRequired = 2
        double.delaysPrimaryMouseButtonEvents = false
        cv.addGestureRecognizer(double)
        c.collection = cv

        let scroll = NSScrollView()
        scroll.documentView = cv
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let cv = scroll.documentView as? ZoomableCollectionView else { return }
        context.coordinator.update(cv, version: version, selection: selection, zoom: zoom)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate, NSTextFieldDelegate {
        let model: BrowserModel
        weak var collection: ZoomableCollectionView?
        private var items: [FileItem] = []
        private var lastVersion = -1
        private var lastZoom = 0.0
        private var lastBucket = 0
        private var syncing = false

        init(_ model: BrowserModel) { self.model = model }

        func update(_ cv: ZoomableCollectionView, version: Int, selection: Set<URL>, zoom: Double) {
            syncing = true
            defer { syncing = false }
            var needsReload = false
            if version != lastVersion { items = model.visible; lastVersion = version; needsReload = true }
            if zoom != lastZoom {
                lastZoom = zoom
                let layout = cv.collectionViewLayout as? NSCollectionViewFlowLayout
                layout?.itemSize = NSSize(width: zoom + 36, height: zoom + 48)
                if !needsReload {
                    // Zoom only: resize in place. Visible cells keep their image and ask for a new thumbnail only
                    // when the size bucket changes.
                    layout?.invalidateLayout()
                    let bucket = Thumbnails.bucket(for: CGFloat(zoom))
                    if bucket != lastBucket {
                        for case let cell as IconCell in cv.visibleItems() {
                            if let path = cv.indexPath(for: cell), path.item < items.count {
                                cell.configure(items[path.item], size: CGFloat(zoom), keepImage: true)
                            }
                        }
                    }
                }
                lastBucket = Thumbnails.bucket(for: CGFloat(zoom))
            }
            if needsReload { cv.reloadData() }
            let wanted = Set(items.indices.filter { selection.contains(items[$0].url) }.map { IndexPath(item: $0, section: 0) })
            if cv.selectionIndexPaths != wanted { cv.selectionIndexPaths = wanted }
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = cv.makeItem(withIdentifier: IconCell.id, for: indexPath) as! IconCell
            cell.configure(items[indexPath.item], size: CGFloat(lastZoom))
            cell.textField?.delegate = self
            return cell
        }

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }
        func collectionView(_ cv: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { pushSelection(cv) }

        func pushSelection(_ cv: NSCollectionView) {
            guard !syncing else { return }
            model.selection = Set(cv.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].url : nil })
        }

        @objc func doubleClicked(_ g: NSClickGestureRecognizer) {
            guard let cv = collection, let path = cv.indexPathForItem(at: g.location(in: cv)), path.item < items.count else { return }
            model.open(items[path.item])
        }

        func beginRename(_ cv: NSCollectionView) {
            guard let path = cv.selectionIndexPaths.first, let cell = cv.item(at: path) as? IconCell,
                  let field = cell.textField else { return }
            field.isEditable = true
            cv.window?.makeFirstResponder(field)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let cv = collection else { return }
            field.isEditable = false
            cv.window?.makeFirstResponder(cv)
            // Resolve the item from the field's own cell, not the selection: a click elsewhere can change the selection first.
            guard let url = cv.visibleItems().compactMap({ $0 as? IconCell }).first(where: { $0.textField === field })?.representedURL,
                  let item = items.first(where: { $0.url == url }) else { return }
            if field.stringValue != item.name { model.rename(item, to: field.stringValue) } else { field.stringValue = item.name }
        }
    }
}
