/// The app the Global Menu is for: the last one in front that isn't Grove
/// Keys itself (its window or a menu can be in front when the pine is clicked).
public struct FrontAppTracker: Sendable {
    public static let ownBundleID = "com.projectgrove.keys"

    public struct App: Equatable, Sendable {
        public var bundleID: String?
        public var pid: Int32
    }

    public private(set) var current: App?

    public init() {}

    public mutating func update(bundleID: String?, pid: Int32) {
        guard bundleID != Self.ownBundleID else { return }
        current = App(bundleID: bundleID, pid: pid)
    }
}
