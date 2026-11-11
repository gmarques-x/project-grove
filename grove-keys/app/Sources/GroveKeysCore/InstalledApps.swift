import Foundation

/// The apps on this Mac, for the Grove Launcher and the key editor's app
/// picker: `.app` bundles one level down in each folder.
public enum InstalledApps {
    public struct App: Equatable, Sendable, Identifiable {
        public var name: String
        public var bundleID: String
        /// Where the bundle is.
        public var path: String
        public var id: String { bundleID }
    }

    /// Where macOS keeps apps: /Applications, ~/Applications and
    /// /System/Applications, each with its Utilities; the web apps Chrome
    /// installs; and the system's own (Finder, and the few in CoreServices).
    public static func standardFolders(home: URL) -> [URL] {
        let user = home.appendingPathComponent("Applications")
        return [
            URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Applications/Utilities"),
            user, user.appendingPathComponent("Utilities"), user.appendingPathComponent("Chrome Apps.localized"),
            URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
        ]
    }

    /// Sorted by name (case-insensitive); each bundle ID once (the first folder
    /// wins). A "folder" that is itself an app is that one app.
    public static func scan(folders: [URL]) -> [App] {
        var seen: Set<String> = []
        var apps: [App] = []
        for folder in folders {
            let items = folder.pathExtension == "app" ? [folder]
                : (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
                      seen.insert(id).inserted else { continue }
                apps.append(App(name: url.deletingPathExtension().lastPathComponent, bundleID: id, path: url.path))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
