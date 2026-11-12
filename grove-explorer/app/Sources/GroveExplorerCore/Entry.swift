import Foundation

/// One item of a folder, as the list shows it.
public struct Entry: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: Equatable, Hashable, Sendable {
        case folder
        case file
        /// A folder macOS shows as one item (an app, a bundle).
        case package
        /// A symbolic link, listed as a link and never as what it points at.
        /// `toFolder` is false for a link to a file, a broken link and a loop.
        case symlink(toFolder: Bool)
        /// A Finder alias (a bookmark file).
        case alias
        case volume
    }

    public var id: URL { url }
    public let url: URL
    /// As shown: the file name, extension included.
    public let name: String
    public let kind: Kind
    /// In bytes; nil for folders (packages and volumes too) and for what
    /// can't be read. A symlink's is the link's own, not its target's.
    public let size: Int64?
    public let modified: Date?
    /// A dot-file, or one with the hidden flag.
    public let isHidden: Bool
    /// "Folder", "PNG Image", "Markdown": what macOS calls the type.
    public let typeDescription: String

    public init(
        url: URL, name: String, kind: Kind, size: Int64?, modified: Date?,
        isHidden: Bool, typeDescription: String
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.isHidden = isHidden
        self.typeDescription = typeDescription
    }
}
