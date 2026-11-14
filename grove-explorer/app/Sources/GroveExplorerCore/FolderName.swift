import Foundation
import GroveThemesCore

/// What the window calls a folder, the one rule for every place that names
/// one: a tab's title, the path bar's first part, VoiceOver's labels, the
/// status bar's words and a read problem's sentence. Home is "Home"; a
/// cloud's folder is called as `CloudProviders` (GroveThemesCore) says,
/// the rule Grove Keys' cloud pill shares; any other folder is its name.
public enum FolderName {
    /// iCloud Drive's folder, below home.
    public static let iCloudDrive = CloudProviders.iCloudDrive
    /// Where the providers that use Apple's File Provider keep their folders, below home.
    public static let cloudStorage = CloudProviders.cloudStorage

    public typealias Provider = CloudProviders.Provider
    public typealias CloudPlace = CloudProviders.CloudPlace

    /// The cloud place `folder` is, or is inside; nil outside every one.
    /// Only the path is looked at (`.` and `..` worked out): nothing is read.
    public static func cloudPlace(containing folder: URL, home: URL) -> CloudPlace? {
        let path = folder.standardizedFileURL.pathComponents
        let homeParts = home.standardizedFileURL.pathComponents
        guard path.count > homeParts.count, Array(path.prefix(homeParts.count)) == homeParts else { return nil }
        let below = Array(path.dropFirst(homeParts.count))
        let drive = iCloudDrive.split(separator: "/").map(String.init)
        if below.count >= drive.count, Array(below.prefix(drive.count)) == drive {
            return CloudProviders.iCloudDrivePlace(home: home)
        }
        let storage = cloudStorage.split(separator: "/").map(String.init)
        if below.count > storage.count, Array(below.prefix(storage.count)) == storage,
            let provider = CloudProviders.provider(folderName: below[storage.count])
        {
            return CloudProviders.place(below[storage.count], provider, home: home)
        }
        return nil
    }

    /// What the window calls `folder`.
    public static func title(of folder: URL, home: URL) -> String {
        if folder.isSameFolder(as: home) { return "Home" }
        if let place = cloudPlace(containing: folder, home: home), place.url.isSameFolder(as: folder) {
            return place.title
        }
        return folder.standardizedFileURL.lastPathComponent
    }
}
