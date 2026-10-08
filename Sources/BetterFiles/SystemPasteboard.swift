import AppKit
import FilesCore

final class SystemPasteboard: PasteboardProtocol {
    private let pb = NSPasteboard.general

    var changeCount: Int { pb.changeCount }

    var urls: [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    func write(urls: [URL]) {
        pb.clearContents()
        if !urls.isEmpty { pb.writeObjects(urls as [NSURL]) }
    }
}
