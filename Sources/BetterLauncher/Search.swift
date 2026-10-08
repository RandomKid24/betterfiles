import AppKit
import LauncherCore

/// Streams file results from Spotlight's index. Apps and history are handled separately (see Model), so this only
/// needs to be fast for 2+ character word-prefix queries.
final class Search: NSObject {
    var onResults: (([Candidate]) -> Void)?

    private let query = NSMetadataQuery()
    private let home = NSHomeDirectory()

    override init() {
        super.init()
        query.searchScopes = [NSMetadataQueryUserHomeScope, "/Applications", "/System/Applications"]
        // Default batching is 1s, which is what made typing feel laggy.
        query.notificationBatchingInterval = 0.05
        let nc = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            nc.addObserver(self, selector: #selector(publish), name: name, object: query)
        }
    }

    func update(_ text: String) {
        query.stop()
        guard let md = SpotlightQuery.mdString(for: text), let predicate = NSPredicate(fromMetadataQueryString: md) else {
            onResults?([])
            return
        }
        query.predicate = predicate
        query.start()
    }

    func stop() { query.stop() }

    @objc private func publish() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var out: [Candidate] = []
        // ponytail: first 300 hits only (arbitrary order); apps and history are merged in separately so the
        // usual suspects are never lost. Add a sort or own index if file search misses things.
        for case let item as NSMetadataItem in query.results.prefix(300) {
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
