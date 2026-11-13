import Foundation
import UniformTypeIdentifiers

/// Why a folder couldn't be read.
public enum FolderReadError: Error, Equatable {
    /// macOS won't let the app read it (its mode, or a privacy permission).
    case noPermission
    case missing
    case notAFolder
    case other(String)
}

/// Reads a folder's items, one level deep, in no promised order. Each
/// entry's URL is the folder's, as it was given, plus the item's name: a
/// folder reached through a link keeps the path the user took to it.
public struct FolderReader: Sendable {
    public init() {}

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .isPackageKey, .isVolumeKey,
        .fileSizeKey, .contentModificationDateKey, .isHiddenKey, .contentTypeKey,
    ]
    private static let keySet = Set(keys)

    public func read(_ folder: URL) throws(FolderReadError) -> [Entry] {
        let urls: [URL]
        do {
            // The keys are fetched with the listing, so the call per item
            // below is answered from what the listing already brought.
            // Resolved first: the listing refuses a link to a folder.
            urls = try FileManager.default.contentsOfDirectory(
                at: folder.resolvingSymlinksInPath(), includingPropertiesForKeys: Self.keys, options: []
            )
        } catch {
            throw Self.readError(error, folder: folder)
        }
        var descriptions = TypeDescriptions()
        return urls.map { Self.entry($0, in: folder, &descriptions) }
    }

    /// What macOS calls each type, asked once per type in a read rather than
    /// once per item: asking for every item is most of the time a large
    /// folder takes (1.1 s of 1.3 s for 50,000). That the description
    /// depends only on the content type is an assumption Apple doesn't
    /// document; 5,000 system items of 58 types gave one description per type.
    struct TypeDescriptions {
        private var byType: [String: String] = [:]
        private let ask: (URL) -> String?

        /// `ask` is the question put to macOS; tests put their own.
        init(ask: @escaping (URL) -> String? = TypeDescriptions.askSystem) {
            self.ask = ask
        }

        static func askSystem(_ url: URL) -> String? {
            (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        }

        mutating func description(of url: URL, type: UTType?) -> String {
            if let type, let known = byType[type.identifier] { return known }
            // Only an answer is kept: an item that went away since the
            // listing must not leave the rest of its type without words.
            guard let description = ask(url) else { return "" }
            if let type { byType[type.identifier] = description }
            return description
        }
    }

    private static func entry(_ listed: URL, in folder: URL, _ descriptions: inout TypeDescriptions) -> Entry {
        let name = listed.lastPathComponent
        // An item that went away since the listing is still listed, with
        // nothing known about it.
        let values = try? listed.resourceValues(forKeys: keySet)
        // Saying whether it is a directory keeps URL from asking the disk.
        let url = folder.appendingPathComponent(name, isDirectory: values?.isDirectory == true)
        let link = values?.isSymbolicLink == true ? Self.link(listed) : nil
        let kind = kind(of: listed, values, link: link)
        let hasOwnSize = switch kind {
        case .file, .alias, .symlink: true
        case .folder, .package, .volume: false
        }
        return Entry(
            url: url,
            name: name,
            kind: kind,
            size: hasOwnSize ? values?.fileSize.map(Int64.init) : nil,
            modified: values?.contentModificationDate,
            isHidden: name.hasPrefix(".") || values?.isHidden == true,
            // macOS calls a link "Alias": a link says it is one, and whether it is broken.
            typeDescription: link.map { LinkText.kind(isBroken: $0.isBroken) }
                ?? descriptions.description(of: listed, type: values?.contentType),
            link: link.map { Entry.Link(target: $0.target, isBroken: $0.isBroken) }
        )
    }

    private static func kind(of url: URL, _ values: URLResourceValues?, link: Followed?) -> Entry.Kind {
        guard let values else { return .file }
        // A link first: macOS also calls a symlink an alias file, and every
        // other value here is the link's own, not its target's.
        if values.isSymbolicLink == true { return .symlink(toFolder: link?.toFolder ?? false) }
        if values.isVolume == true { return .volume }
        if values.isAliasFile == true { return .alias }
        if values.isDirectory == true { return values.isPackage == true ? .package : .folder }
        return .file
    }

    /// A link, read once with the listing: what it says, whether that
    /// leads anywhere, and whether it ends at a folder.
    private struct Followed {
        let target: String
        let isBroken: Bool
        let toFolder: Bool
    }

    /// `readlink` for the text, then `stat`, which follows the whole chain:
    /// a broken link or a loop fails, which is no folder.
    private static func link(_ url: URL) -> Followed {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlink(url.path, &buffer, buffer.count - 1)
        let target = count > 0 ? String(decoding: buffer[..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        var info = stat()
        let followed = stat(url.path, &info) == 0
        return Followed(
            target: target,
            isBroken: LinkText.isBroken(followError: followed ? nil : errno),
            toFolder: followed && info.st_mode & S_IFMT == S_IFDIR)
    }

    private static func readError(_ error: any Error, folder: URL) -> FolderReadError {
        let error = error as NSError
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        let posix = [error, underlying].compactMap { $0 }.first { $0.domain == NSPOSIXErrorDomain }?.code
        switch posix.map(Int32.init) {
        case ENOENT: return .missing
        // A link that leads nowhere is refused as "not a folder" too.
        case ENOTDIR: return FileManager.default.fileExists(atPath: folder.path) ? .notAFolder : .missing
        // EPERM is what a refused privacy permission (Desktop, Documents…) gives.
        case EACCES, EPERM: return .noPermission
        default: break
        }
        if error.domain == NSCocoaErrorDomain {
            switch CocoaError.Code(rawValue: error.code) {
            case .fileReadNoSuchFile, .fileNoSuchFile: return .missing
            case .fileReadNoPermission: return .noPermission
            default: break
            }
        }
        return .other(error.localizedDescription)
    }
}
