/// ↑ and ↓ in a card whose list is longer than the card (the items an
/// operation could not do): each press brings one more item into view.
public enum CardScroll {
    /// The item to bring into view, at the card's top or at its bottom.
    public struct Step: Equatable, Sendable {
        public let item: Int
        public let toTop: Bool

        public init(item: Int, toTop: Bool) {
            self.item = item
            self.toTop = toTop
        }
    }

    /// The step a press makes: ↓ (`down`) brings the first item below
    /// those in view to the bottom, ↑ the first one above to the top; nil
    /// at an end. `visible`: the items wholly in view as the card says
    /// (so a wheel's scroll counts, and an item of several lines is one
    /// item); nil before it has said, when it shows its top.
    public static func step(down: Bool, visible: ClosedRange<Int>?, count: Int) -> Step? {
        guard count > 0 else { return nil }
        let visible = visible ?? 0...0
        if down {
            return visible.upperBound < count - 1 ? Step(item: visible.upperBound + 1, toTop: false) : nil
        }
        return visible.lowerBound > 0 ? Step(item: min(visible.lowerBound, count) - 1, toTop: true) : nil
    }
}
