import Foundation

/// What the Grove apps call the clouds, the one rule for Grove Explorer's
/// sidebar and Grove Keys' cloud pill: iCloud Drive's folder
/// (`com~apple~CloudDocs`) is "iCloud Drive"; a cloud provider's folder in
/// `~/Library/CloudStorage` is the provider and its account ("OneDrive",
/// "OneDrive - Contoso").
///
/// The system's own display name was checked (2026-11-13, macOS 27):
/// `FileManager.displayName(atPath:)` and `URLResourceValues.localizedName`
/// both say "iCloud Drive" for iCloud Drive but "OneDrive-Personal" for
/// OneDrive's folder, so the names are worked out here, from the path alone.
public enum CloudProviders {
    /// iCloud Drive's folder, below home.
    public static let iCloudDrive = "Library/Mobile Documents/com~apple~CloudDocs"
    /// What iCloud Drive's folder is called.
    public static let iCloudDriveName = "iCloud Drive"
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

        public init(url: URL, title: String, kind: Kind) {
            self.url = url
            self.title = title
            self.kind = kind
        }
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

    /// The cloud providers a list shows, from the names of the folders in
    /// CloudStorage: by provider, its own account first, then by title.
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

    /// iCloud Drive's folder in `home`.
    public static func iCloudDrivePlace(home: URL) -> CloudPlace {
        CloudPlace(
            url: home.appendingPathComponent(iCloudDrive, isDirectory: true), title: iCloudDriveName,
            kind: .iCloudDrive)
    }

    /// The provider's folder called `folderName` in `home`'s CloudStorage.
    public static func place(_ folderName: String, _ provider: Provider, home: URL) -> CloudPlace {
        CloudPlace(
            url: home.appendingPathComponent(cloudStorage, isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true),
            title: provider.title, kind: .provider(provider.name))
    }
}
