import AppKit
import Observation

/// Watches one folder and calls `onChange` (debounced, on the main queue) when entries are added, removed or renamed.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit { source?.cancel() }
}

/// Folders the user pinned to the sidebar. Shared by every tab and pane.
@MainActor @Observable
final class Favorites {
    static let shared = Favorites()
    private(set) var urls: [URL]

    private init() {
        urls = (UserDefaults.standard.stringArray(forKey: "favorites") ?? []).map { URL(fileURLWithPath: $0) }
    }

    func add(_ url: URL) {
        guard !urls.contains(url) else { return }
        urls.append(url)
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    private func save() { UserDefaults.standard.set(urls.map(\.path), forKey: "favorites") }
}

/// View preferences that are the same in every tab and pane.
@MainActor @Observable
final class Prefs {
    static let shared = Prefs()
    var showPreview = UserDefaults.standard.object(forKey: "showPreview") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showPreview, forKey: "showPreview") }
    }
}
