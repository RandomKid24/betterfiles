import Foundation

/// Undo for move / rename / trash / paste / new folder. Every undo is itself non-destructive:
/// moves go back only if the original spot is free, and created items go to the Trash.
public final class UndoStack {
    public enum Entry {
        case moved([(from: URL, to: URL)])   // also rename and trash: undone by moving `to` back to `from`
        case created([URL])                  // copy, new folder, archive: undone by trashing
        /// sync: files copied over (undone by trashing them) and files replaced (undone by trashing the new copy
        /// and moving the old one back from the Trash).
        case sync(created: [URL], replaced: [(dest: URL, trashed: URL)])
    }

    private var stack: [(label: String, entry: Entry)] = []
    public init() {}

    public var canUndo: Bool { !stack.isEmpty }

    private func push(_ label: String, _ entry: Entry) {
        stack.append((label, entry))
        if stack.count > 50 { stack.removeFirst() }
    }

    public func recordMoves(_ label: String, _ outcomes: [OpOutcome]) {
        let pairs = outcomes.compactMap { o -> (from: URL, to: URL)? in
            guard o.succeeded, let to = o.destination, to != o.source else { return nil }
            return (o.source, to)
        }
        if !pairs.isEmpty { push(label, .moved(pairs)) }
    }

    public func recordCreated(_ label: String, _ outcomes: [OpOutcome]) {
        let urls = outcomes.compactMap { $0.succeeded ? $0.destination : nil }
        if !urls.isEmpty { push(label, .created(urls)) }
    }

    public func recordSync(_ label: String, created: [OpOutcome], replaced: [FolderCompare.Replacement]) {
        let made = created.compactMap { $0.succeeded ? $0.destination : nil }
        let pairs = replaced.compactMap { r -> (dest: URL, trashed: URL)? in r.trashed.map { (r.dest, $0) } }
        if !made.isEmpty || !pairs.isEmpty { push(label, .sync(created: made, replaced: pairs)) }
    }

    public func recordReplaced(_ label: String, _ items: [FolderCompare.Replacement]) { recordSync(label, created: [], replaced: items) }

    /// Undoes the latest action. Returns a message for the status bar, or nil when there is nothing to undo.
    public func undo() -> String? {
        guard let last = stack.popLast() else { return nil }
        var failed = 0
        switch last.entry {
        case .moved(let pairs):
            for (from, to) in pairs.reversed() {
                if FileManager.default.fileExists(atPath: from.path) || (try? FileManager.default.moveItem(at: to, to: from)) == nil {
                    failed += 1
                }
            }
        case .created(let urls):
            failed = FileOps.trash(urls).filter { !$0.succeeded }.count
        case .sync(let created, let pairs):
            failed += created.isEmpty ? 0 : FileOps.trash(created).filter { !$0.succeeded }.count
            for (dest, trashed) in pairs.reversed() {
                guard FileOps.trash([dest]).first?.succeeded == true, (try? FileManager.default.moveItem(at: trashed, to: dest)) != nil else { failed += 1; continue }
            }
        }
        return failed == 0 ? "Undid \(last.label)" : "Couldn\u{2019}t fully undo \(last.label) (\(failed) failed)"
    }
}
