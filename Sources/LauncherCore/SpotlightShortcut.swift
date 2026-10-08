import Foundation

public enum SpotlightShortcut {
    /// `hotkeys` is the `AppleSymbolicHotKeys` dictionary from `com.apple.symbolichotkeys`.
    /// Entry "64" is Spotlight's Cmd+Space; no entry means the factory default, which is on.
    public static func isEnabled(_ hotkeys: [String: Any]?) -> Bool {
        guard let entry = hotkeys?["64"] as? [String: Any], let enabled = entry["enabled"] else { return true }
        if let b = enabled as? Bool { return b }
        if let n = enabled as? Int { return n != 0 }
        return true
    }
}
