import Foundation

/// What the window calls a folder, the one rule for every place that names
/// one: a tab's title, the path bar's first part, VoiceOver's labels, the
/// status bar's words and a read problem's sentence. Home is "Home"; iCloud
/// Drive's folder (`com~apple~CloudDocs`) is "iCloud Drive"; a cloud
/// provider's folder in `~/Library/CloudStorage` is the provider and its
/// account ("OneDrive", "OneDrive - Contoso"); any other folder is its name.
///
/// The system's own display name was checked (2026-11-13, macOS 27):
/// `FileManager.displayName(atPath:)` and `URLResourceValues.localizedName`
/// both say "iCloud Drive" for iCloud Drive but "OneDrive-Personal" for
/// OneDrive's folder, so the names are worked out here, from the path alone.
public enum FolderName {
    /// iCloud Drive's folder, below home.
    public static let iCloudDrive = "Library/Mobile Documents/com~apple~CloudDocs"
    /// Where the providers that use Apple's File Provider keep their folders, below home.
    public static let cloudStorage = "Library/CloudStorage"

    /// A cloud provider, from its folder's name in CloudStorage: `name` is
    /// the provider (a sidebar header), `title` the folder's own words.
    public struct Provider: Equatable, Sendable {
        public let name: String
        public let title: String

        public init(name: String, title: String) {
            self.name = name
            self.title = title
        }
    }

    /// A folder at the top of a cloud: iCloud Drive or a provider's.
    public struct CloudPlace: Equatable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable {
            case iCloudDrive
            /// The provider's name, the header its folders are listed under.
            case provider(String)
        }

        public let url: URL
        public let title: String
        public let kind: Kind
    }

    /// The providers' own spelling, where the folder's name runs the words together.
    private static let spelled = ["GoogleDrive": "Google Drive"]

    /// "OneDrive-Personal" is OneDrive's own account: "OneDrive". After the
    /// first dash is the account ("OneDrive-Contoso": "OneDrive - Contoso");
    /// an account that is "Personal" or the provider's name again ("Box-Box")
    /// is said not at all. Nil for a hidden name or one without a provider.
    public static func provider(folderName: String) -> Provider? {
        guard !folderName.hasPrefix(".") else { return nil }
        let dash = folderName.firstIndex(of: "-")
        let head = String(folderName[..<(dash ?? folderName.endIndex)])
        guard !head.isEmpty else { return nil }
        let account = dash.map { String(folderName[folderName.index(after: $0)...]) } ?? ""
        let name = spelled[head] ?? head
        let plain = account.isEmpty || account == "Personal" || account == head
        return Provider(name: name, title: plain ? name : name + " - " + account)
    }

    /// The cloud place `folder` is, or is inside; nil outside every one.
    /// Only the path is looked at (`.` and `..` worked out): nothing is read.
    public static func cloudPlace(containing folder: URL, home: URL) -> CloudPlace? {
        let path = folder.standardizedFileURL.pathComponents
        let homeParts = home.standardizedFileURL.pathComponents
        guard path.count > homeParts.count, Array(path.prefix(homeParts.count)) == homeParts else { return nil }
        let below = Array(path.dropFirst(homeParts.count))
        let drive = iCloudDrive.split(separator: "/").map(String.init)
        if below.count >= drive.count, Array(below.prefix(drive.count)) == drive {
            return CloudPlace(
                url: home.appendingPathComponent(iCloudDrive, isDirectory: true), title: "iCloud Drive",
                kind: .iCloudDrive)
        }
        let storage = cloudStorage.split(separator: "/").map(String.init)
        if below.count > storage.count, Array(below.prefix(storage.count)) == storage,
            let provider = provider(folderName: below[storage.count])
        {
            return place(below[storage.count], provider, home: home)
        }
        return nil
    }

    /// The cloud providers the sidebar lists, from the names of the folders
    /// in CloudStorage: by provider, its own account first, then by title.
    public static func providers(in folderNames: [String], home: URL) -> [CloudPlace] {
        let found = folderNames.compactMap { name in provider(folderName: name).map { (name, $0) } }
        return found
            .sorted { a, b in
                if a.1.name != b.1.name { return a.1.name.localizedStandardCompare(b.1.name) == .orderedAscending }
                if (a.1.title == a.1.name) != (b.1.title == b.1.name) { return a.1.title == a.1.name }
                return a.1.title.localizedStandardCompare(b.1.title) == .orderedAscending
            }
            .map { place($0.0, $0.1, home: home) }
    }

    /// What the window calls `folder`.
    public static func title(of folder: URL, home: URL) -> String {
        if folder.isSameFolder(as: home) { return "Home" }
        if let place = cloudPlace(containing: folder, home: home), place.url.isSameFolder(as: folder) {
            return place.title
        }
        return folder.standardizedFileURL.lastPathComponent
    }

    private static func place(_ folderName: String, _ provider: Provider, home: URL) -> CloudPlace {
        CloudPlace(
            url: home.appendingPathComponent(cloudStorage, isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true),
            title: provider.title, kind: .provider(provider.name))
    }
}
