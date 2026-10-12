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
    /// Width of the preview pane; dragged with the divider and remembered.
    var previewWidth = min(520, max(220, UserDefaults.standard.object(forKey: "previewWidth") as? Double ?? 280))
    func savePreviewWidth() { UserDefaults.standard.set(previewWidth, forKey: "previewWidth") }
}

/// Folders visited recently, for Go > Recent Folders.
@MainActor
final class Recents {
    static let shared = Recents()
    private(set) var urls: [URL] = (UserDefaults.standard.stringArray(forKey: "recents") ?? []).map { URL(fileURLWithPath: $0) }

    func add(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        if urls.count > 12 { urls.removeLast() }
        UserDefaults.standard.set(urls.map(\.path), forKey: "recents")
    }
}

/// A saved search: where to look, what to look for, and whether to include subfolders.
struct SmartFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var query: String
    var root: String
    var subfolders: Bool
}

@MainActor @Observable
final class SmartFolders {
    static let shared = SmartFolders()
    private(set) var all: [SmartFolder]

    private init() {
        all = (UserDefaults.standard.data(forKey: "smartFolders").flatMap { try? JSONDecoder().decode([SmartFolder].self, from: $0) }) ?? []
    }

    func add(_ folder: SmartFolder) { all.append(folder); save() }
    func remove(_ id: UUID) { all.removeAll { $0.id == id }; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: "smartFolders") }
    }
}

extension Notification.Name {
    /// Posted whenever a pane moves to another folder, so the open tabs can be remembered.
    static let butterfinderNavigated = Notification.Name("com.butterfinder.navigated")
}
