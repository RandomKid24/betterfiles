import Foundation

public struct FileItem: Equatable, Hashable, Sendable {
    public let url: URL
    public let isFolder: Bool
    public let isHidden: Bool
    public let isPackage: Bool
    public let size: Int64?
    public let modified: Date?
    public let kind: String

    public init(url: URL, isFolder: Bool = false, isHidden: Bool = false, isPackage: Bool = false,
                size: Int64? = nil, modified: Date? = nil, kind: String = "") {
        self.url = url
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.size = size
        self.modified = modified
        self.kind = kind
    }

    /// File name including its extension.
    public var name: String { url.lastPathComponent }
}
