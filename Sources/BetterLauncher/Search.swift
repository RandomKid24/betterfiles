import AppKit
import LauncherCore

final class Search: NSObject {
    var onResults: (([Candidate]) -> Void)?

    private let query = NSMetadataQuery()
    private let home = NSHomeDirectory()

    override init() {
        super.init()
        query.searchScopes = [NSMetadataQueryUserHomeScope, "/Applications", "/System/Applications"]
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(publish), name: .NSMetadataQueryDidFinishGathering, object: query)
        nc.addObserver(self, selector: #selector(publish), name: .NSMetadataQueryDidUpdate, object: query)
    }

    func update(_ text: String) {
        query.stop()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { onResults?([]); return }
        // %@ argument: user text is a value, never parsed as predicate syntax.
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemDisplayNameKey, t)
        query.start()
    }

    @objc private func publish() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var out: [Candidate] = []
        // ponytail: first 1000 hits only; one-letter queries can miss the best match. Add a sort or own index if it bites.
        for case let item as NSMetadataItem in query.results.prefix(1000) {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  let name = item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String,
                  !path.contains("/."),
                  !path.hasPrefix(home + "/Library/")
            else { continue }
            let tree = item.value(forAttribute: NSMetadataItemContentTypeTreeKey) as? [String] ?? []
            out.append(Candidate(name: name, path: path, isApp: tree.contains("com.apple.application-bundle")))
        }
        onResults?(out)
    }
}
