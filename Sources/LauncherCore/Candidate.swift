import Foundation

public struct Candidate: Equatable, Sendable {
    public let name: String
    public let path: String
    public let isApp: Bool

    public init(name: String, path: String, isApp: Bool) {
        self.name = name
        self.path = path
        self.isApp = isApp
    }

    public var parent: String { (path as NSString).deletingLastPathComponent }
}
