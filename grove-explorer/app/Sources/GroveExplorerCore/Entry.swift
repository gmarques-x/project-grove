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

    /// Where a symbolic link points, read with the listing.
    public struct Link: Equatable, Hashable, Sendable {
        /// What the link says, as `readlink` gives it (`ls -l` shows the
        /// same): relative or absolute, never resolved.
        public let target: String
        /// Following it fails: what it points at is missing, or it loops.
        public let isBroken: Bool

        public init(target: String, isBroken: Bool) {
            self.target = target
            self.isBroken = isBroken
        }
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
    /// A symbolic link's target; nil for anything else (and for a link
    /// whose text couldn't be read).
    public let link: Link?

    public init(
        url: URL, name: String, kind: Kind, size: Int64?, modified: Date?,
        isHidden: Bool, typeDescription: String, link: Link? = nil
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.size = size
        self.modified = modified
        self.isHidden = isHidden
        self.typeDescription = typeDescription
        self.link = link
    }
}
