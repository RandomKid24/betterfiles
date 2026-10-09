import Foundation

public struct FileItem: Equatable, Hashable, Sendable {
    public let url: URL
    public let isFolder: Bool
    public let isHidden: Bool
    public let isPackage: Bool
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    public let tags: [String]
    public let kind: String
    /// File name including its extension (stored: sorting reads it per comparison).
    public let name: String

    public init(url: URL, isFolder: Bool = false, isHidden: Bool = false, isPackage: Bool = false,
                size: Int64? = nil, modified: Date? = nil, kind: String = "",
                created: Date? = nil, tags: [String] = []) {
        self.url = url
        self.name = url.lastPathComponent
        self.isFolder = isFolder
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.size = size
        self.modified = modified
        self.created = created
        self.tags = tags
        self.kind = kind
    }
}
