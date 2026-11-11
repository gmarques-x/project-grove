import Foundation

/// The `grovethemes://` links Grove Themes answers: `gallery` opens and brings
/// forward its window (the Grove bar's Themes… item). Anything else is ignored.
public enum ThemesURL: Equatable, Sendable {
    case gallery

    public init?(_ url: URL) {
        guard url.scheme?.lowercased() == "grovethemes",
              url.host?.lowercased() == "gallery",
              url.path.isEmpty || url.path == "/"
        else { return nil }
        self = .gallery
    }
}
