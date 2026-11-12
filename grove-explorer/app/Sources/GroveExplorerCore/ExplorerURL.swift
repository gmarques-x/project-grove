import Foundation

/// The app's links: `groveexplorer://open?path=<percent-encoded path>` names
/// a folder to show, or a file to select in its folder.
public enum ExplorerURL: Equatable {
    case open(URL)

    /// Nil for anything but an `open` link with a path from the root: a link
    /// comes from outside the app, so it is never read as relative to
    /// anything.
    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "groveexplorer", url.host?.lowercased() == "open",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value,
              path.hasPrefix("/")
        else { return nil }
        self = .open(URL(fileURLWithPath: path))
    }
}
