import Foundation

/// Finder tags. Colour tags are matched by name, like Finder's built-in set.
public enum Tags {
    public static let standard: [(name: String, hex: UInt32)] = [
        ("Red", 0xFF3B30), ("Orange", 0xFF9500), ("Yellow", 0xFFCC00), ("Green", 0x34C759),
        ("Blue", 0x007AFF), ("Purple", 0xAF52DE), ("Gray", 0x8E8E93),
    ]

    public static func hex(for tag: String) -> UInt32? {
        standard.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }?.hex
    }

    /// Adds `tag` to every item, or removes it from all if they all have it already.
    @discardableResult
    public static func toggle(_ tag: String, on items: [FileItem]) -> [OpOutcome] {
        let remove = !items.isEmpty && items.allSatisfy { $0.tags.contains(tag) }
        return items.map { item in
            var names = item.tags
            if remove { names.removeAll { $0 == tag } } else if !names.contains(tag) { names.append(tag) }
            do {
                try (item.url as NSURL).setResourceValue(names, forKey: .tagNamesKey)
                return OpOutcome(source: item.url, destination: item.url, error: nil)
            } catch {
                return OpOutcome(source: item.url, destination: nil, error: error)
            }
        }
    }
}
