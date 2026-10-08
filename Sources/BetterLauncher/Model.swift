import AppKit
import LauncherCore
import Observation

@MainActor @Observable
final class Model {
    var text = ""
    var results: [Candidate] = []
    var selected = 0
    var showCount = 0
    var onDismiss: () -> Void = {}

    @ObservationIgnored private let search = Search()
    @ObservationIgnored private let usage: Usage
    @ObservationIgnored private var raw: [Candidate] = []

    init(usage: Usage) {
        self.usage = usage
        search.onResults = { [weak self] candidates in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.raw = candidates
                self.rerank()
            }
        }
    }

    func textChanged() {
        search.update(text)
        rerank(keepSelection: false)
    }

    func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selected = (selected + delta + results.count) % results.count
    }

    func openSelected() {
        guard results.indices.contains(selected) else { return }
        let c = results[selected]
        // Only record and hide when the open succeeded (file may have moved since indexing).
        if NSWorkspace.shared.open(URL(fileURLWithPath: c.path)) {
            usage.record(path: c.path)
            onDismiss()
        }
    }

    func reset() {
        text = ""
        raw = []
        results = []
        selected = 0
    }

    // Live Spotlight updates keep the user's highlighted row; a new query starts at the top.
    private func rerank(keepSelection: Bool = true) {
        let previous = keepSelection && results.indices.contains(selected) ? results[selected].path : nil
        results = Ranker.rank(query: text, candidates: raw, usage: usage.get)
        selected = Selection.index(of: previous, in: results)
    }
}
