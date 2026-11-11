import Foundation

/// The launcher's app picker: `.app` bundles one level down in each folder.
public enum InstalledApps {
    public struct App: Equatable, Sendable, Identifiable {
        public var name: String
        public var bundleID: String
        public var id: String { bundleID }
    }

    /// /Applications, ~/Applications, /System/Applications.
    public static func standardFolders(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/System/Applications")]
    }

    /// Sorted by name (case-insensitive); each bundle ID once (the first folder wins).
    public static func scan(folders: [URL]) -> [App] {
        var seen: Set<String> = []
        var apps: [App] = []
        for folder in folders {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for url in items where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: plist),
                      let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String, !id.isEmpty,
                      seen.insert(id).inserted else { continue }
                apps.append(App(name: url.deletingPathExtension().lastPathComponent, bundleID: id))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
