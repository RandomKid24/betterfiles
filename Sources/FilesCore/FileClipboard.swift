import Foundation

/// The slice of NSPasteboard that FileClipboard needs, so tests can use a fake.
public protocol PasteboardProtocol: AnyObject {
    var changeCount: Int { get }
    var urls: [URL] { get }
    /// An empty array clears the pasteboard.
    func write(urls: [URL])
}

/// Explorer-style Cut / Copy / Paste. A cut is only honoured as a move if nothing else
/// has been put on the pasteboard since; otherwise Paste copies whatever is there now.
public final class FileClipboard {
    private let pasteboard: PasteboardProtocol
    private var pendingCutChangeCount: Int?

    public init(pasteboard: PasteboardProtocol) {
        self.pasteboard = pasteboard
    }

    public var canPaste: Bool { !pasteboard.urls.isEmpty }

    public func copy(_ urls: [URL]) {
        pasteboard.write(urls: urls)
        pendingCutChangeCount = nil
    }

    public func cut(_ urls: [URL]) {
        pasteboard.write(urls: urls)
        pendingCutChangeCount = pasteboard.changeCount
    }

    @discardableResult
    public func paste(into folder: URL) -> [OpOutcome] {
        let urls = pasteboard.urls
        guard !urls.isEmpty else { return [] }
        if pendingCutChangeCount == pasteboard.changeCount {
            let outcomes = FileOps.move(urls, to: folder)
            pendingCutChangeCount = nil
            pasteboard.write(urls: []) // like Explorer: a completed cut-paste empties the clipboard
            return outcomes
        }
        return FileOps.copy(urls, to: folder)
    }
}
