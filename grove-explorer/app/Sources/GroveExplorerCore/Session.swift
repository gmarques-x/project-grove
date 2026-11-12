import Foundation

/// What the window was like when it was last used, kept in a file.
public struct Session: Equatable, Codable, Sendable {
    public var browser: Browser
    /// In points.
    public var sidebarWidth: Double
    /// The left pane's share of the two panes' width: 0.5 is even.
    public var split: Double
    public var sidebarHidden: Bool

    public init(browser: Browser, sidebarWidth: Double, split: Double, sidebarHidden: Bool) {
        self.browser = browser
        self.sidebarWidth = sidebarWidth
        self.split = split
        self.sidebarHidden = sidebarHidden
    }

    /// The session in `file`; nil when there is none, when it can't be read,
    /// or when it describes a window that can't be (no tab to show). Keys a
    /// later version added are passed over.
    public static func load(from file: URL) -> Session? {
        guard let data = try? Data(contentsOf: file),
              let session = try? JSONDecoder().decode(Session.self, from: data),
              session.browser.isWhole
        else { return nil }
        return session
    }

    /// Writes the session to `file` in one step (a reader sees the old file
    /// or the new one, never half of it), making its folder when missing.
    public func save(to file: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }
}

private extension Browser {
    /// One or two panes, the active one among them, and in each a current
    /// tab that is there: what the rest of `Browser` takes for granted.
    var isWhole: Bool {
        (1...2).contains(panes.count)
            && panes.indices.contains(active.rawValue)
            && panes.allSatisfy { $0.tabs.indices.contains($0.current) }
    }
}
