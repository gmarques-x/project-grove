import Foundation

/// The sidebar's favourites as a list to change (spec §5): a folder dragged
/// onto the sidebar is added. The list is then written with
/// `ExplorerConfig.localText`.
public enum Favourites {
    /// The id of a new favourite for a folder called `name`: its table's
    /// name in the file, so only what a bare TOML key may have. The name in
    /// lower case, accents off, everything else a dash; "folder" when
    /// nothing is left. One of `taken` (in any capitals) gets the first
    /// free number: "photos-2".
    public static func id(forName name: String, taken: Set<String>) -> String {
        let plain = name.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        var id = ""
        for character in plain.unicodeScalars {
            let allowed = ("a"..."z").contains(character) || ("0"..."9").contains(character) || character == "_"
            if allowed {
                id.unicodeScalars.append(character)
            } else if !id.isEmpty, !id.hasSuffix("-") {
                id += "-"
            }
        }
        while id.hasSuffix("-") { id.removeLast() }
        if id.isEmpty { id = "folder" }

        let used = Set(taken.map { $0.lowercased() })
        guard used.contains(id) else { return id }
        var number = 2
        while used.contains("\(id)-\(number)") { number += 1 }
        return "\(id)-\(number)"
    }

    /// `favourites` with each of `folders` added at the end, under its
    /// folder's name. A folder that is a favourite already (by its path,
    /// however spelled) is not added again.
    public static func adding(_ folders: [URL], to favourites: [Favourite]) -> [Favourite] {
        var all = favourites
        var paths = Set(all.map { $0.url.standardizedFileURL.path })
        for folder in folders {
            let standard = folder.standardizedFileURL
            guard paths.insert(standard.path).inserted else { continue }
            let name = standard.lastPathComponent
            all.append(Favourite(
                id: id(forName: name, taken: Set(all.map(\.id))), url: folder,
                title: name.isEmpty ? standard.path : name))
        }
        return all
    }
}
