import Foundation
import GroveExplorerCore
import Testing

@Suite struct RowsStateTests {
    private typealias Order = GroveExplorerCore.SortOrder
    private static let folder = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
    private static let big = 50_000, small = 212

    private static func arrangement(
        sort: Order = .byName, filter: String = "", showHidden: Bool = false, open: Set<URL> = []
    ) -> Arrangement {
        Arrangement(folder: folder, sort: sort, filter: filter, showHidden: showHidden, open: open)
    }

    /// Tab A filters by "s", tab B shows the whole folder, tab C is B sorted by size.
    private let a = arrangement(filter: "s")
    private let b = arrangement()
    private let c = arrangement(sort: Order(column: .size, ascending: true))

    // MARK: What a pane may reuse for a tab

    @Test func rowsArrangedAsTheTabAsksAreShownAsTheyAre() {
        #expect(RowsState.arranged(by: b).reuse(for: b, entries: Self.big) == .asItIs)
        #expect(RowsState.arranged(by: b).after(.asItIs, for: b) == .arranged(by: b))
    }

    @Test func aSmallFolderIsArrangedAtOnce() {
        #expect(RowsState.arranged(by: b).reuse(for: c, entries: Self.small) == .arrangeNow)
        #expect(RowsState.arranged(by: a).reuse(for: b, entries: RowsState.arrangeNowLimit) == .arrangeNow)
        #expect(RowsState.arrangeNowLimit == 10_000)
        #expect(RowsState.arranged(by: a).after(.arrangeNow, for: b) == .arranged(by: b))
        // Whatever the rows shown: the folder's entries are all there to arrange.
        #expect(RowsState.awaiting(a).reuse(for: b, entries: Self.small) == .arrangeNow)
        #expect(RowsState.oldOrder(of: b, awaiting: c).reuse(for: a, entries: Self.small) == .arrangeNow)
    }

    @Test func aBigFolderInAnotherSortKeepsItsOrderMeanwhile() {
        #expect(RowsState.arranged(by: b).reuse(for: c, entries: 10_001) == .oldOrder)
        #expect(RowsState.arranged(by: b).after(.oldOrder, for: c) == .oldOrder(of: b, awaiting: c))
    }

    @Test func aBigFolderUnderAnotherFilterOrHiddenFlagIsBlankMeanwhile() {
        #expect(RowsState.arranged(by: a).reuse(for: b, entries: 10_001) == .blank)
        #expect(RowsState.arranged(by: b).reuse(for: a, entries: Self.big) == .blank)
        #expect(RowsState.arranged(by: Self.arrangement(showHidden: true)).reuse(for: b, entries: Self.big) == .blank)
        #expect(RowsState.arranged(by: a).after(.blank, for: b) == .awaiting(b))
    }

    @Test func rowsStillAwaitedAreNeverReusedAsRows() {
        // No rows: not "as they are", not "in their old order", whatever they await.
        for wanted in [a, b, c] {
            let reuse = RowsState.awaiting(b).reuse(for: wanted, entries: Self.big)
            #expect(reuse == (wanted == b ? .keepWaiting : .blank))
        }
        #expect(RowsState.awaiting(b).after(.blank, for: c) == .awaiting(c))
        #expect(RowsState.awaiting(b).after(.keepWaiting, for: b) == .awaiting(b))
    }

    @Test func rowsInAnOldOrderWaitOnForTheSameArrangement() {
        let state = RowsState.oldOrder(of: b, awaiting: c)
        #expect(state.reuse(for: c, entries: Self.big) == .keepWaiting)
        #expect(state.after(.keepWaiting, for: c) == state)
    }

    @Test func rowsInAnOldOrderAreTheirOldArrangementsRows() {
        let state = RowsState.oldOrder(of: b, awaiting: c)
        // Back to the tab whose order they have: they are right as they are.
        #expect(state.reuse(for: b, entries: Self.big) == .asItIs)
        #expect(state.after(.asItIs, for: b) == .arranged(by: b))
        // A third sort: still the right set, in the old order.
        let byDate = Self.arrangement(sort: Order(column: .modified, ascending: false))
        #expect(state.reuse(for: byDate, entries: Self.big) == .oldOrder)
        #expect(state.after(.oldOrder, for: byDate) == .oldOrder(of: b, awaiting: byDate))
        // A filter: another set.
        #expect(state.reuse(for: a, entries: Self.big) == .blank)
    }

    /// Another set of open folders is other rows, as another filter is:
    /// never "as it is" and never "the same items in another order".
    @Test func anotherSetOfOpenFoldersIsArrangedAgainOrBlank() {
        let opened = Self.arrangement(open: [Self.folder.appendingPathComponent("Sources", isDirectory: true)])
        #expect(RowsState.arranged(by: b).reuse(for: opened, entries: Self.small) == .arrangeNow)
        #expect(RowsState.arranged(by: b).reuse(for: opened, entries: Self.big) == .blank)
        #expect(RowsState.arranged(by: opened).reuse(for: b, entries: Self.big) == .blank)
        let openedBySize = Self.arrangement(
            sort: Order(column: .size, ascending: true), open: opened.open)
        #expect(RowsState.arranged(by: opened).reuse(for: openedBySize, entries: Self.big) == .oldOrder)
        #expect(RowsState.arranged(by: opened).reuse(for: opened, entries: Self.big) == .asItIs)
    }

    @Test func theBestListingOfAFolderIsTheOneThatNeedsLeast() {
        #expect(RowsState.Reuse.asItIs < .arrangeNow)
        #expect(RowsState.Reuse.arrangeNow < .oldOrder)
        #expect(RowsState.Reuse.oldOrder < .keepWaiting)
        #expect(RowsState.Reuse.keepWaiting < .blank)
    }

    // MARK: Rows that arrive, and a read that completes

    @Test func arrivedRowsAreShownOnlyForWhatTheTabAsksNow() {
        #expect(RowsState.awaiting(b).arrival(of: b, tabWants: b) == .arranged(by: b))
        #expect(RowsState.oldOrder(of: b, awaiting: c).arrival(of: c, tabWants: c) == .arranged(by: c))
        #expect(RowsState.arranged(by: b).arrival(of: c, tabWants: c) == .arranged(by: c))
        // For the tab the pane showed before, or with no tab: dropped.
        #expect(RowsState.awaiting(b).arrival(of: a, tabWants: b) == nil)
        #expect(RowsState.arranged(by: b).arrival(of: a, tabWants: b) == nil)
        #expect(RowsState.awaiting(b).arrival(of: b, tabWants: nil) == nil)
    }

    @Test func aReadIsNothingChangedOnlyAgainstRowsArrangedAsItAsked() {
        #expect(RowsState.arranged(by: b).isUnchanged(byReadFor: b))
        #expect(!RowsState.arranged(by: a).isUnchanged(byReadFor: b))
        #expect(!RowsState.awaiting(b).isUnchanged(byReadFor: b))
        #expect(!RowsState.oldOrder(of: b, awaiting: c).isUnchanged(byReadFor: c))
        #expect(!RowsState.oldOrder(of: b, awaiting: c).isUnchanged(byReadFor: b))
    }

    @Test func onlyAwaitedRowsAreBlank() {
        #expect(RowsState.awaiting(b).isAwaitingRows)
        #expect(!RowsState.arranged(by: b).isAwaitingRows)
        #expect(!RowsState.oldOrder(of: b, awaiting: c).isAwaitingRows)
    }

    // MARK: Sequences

    /// A pane as the app drives it: the state of its rows, whether rows
    /// show, and the one arrange on its way (a tab change gives it up).
    private struct Pane {
        var state: RowsState
        var hasRows = true
        var onItsWay: Arrangement?
        var wanted: Arrangement

        init(showing arrangement: Arrangement) {
            state = .arranged(by: arrangement)
            wanted = arrangement
        }

        /// The pane comes to show a tab asking for `tab`, of the same big
        /// folder; `listing` is the rows it reuses (its own unless given).
        mutating func show(_ tab: Arrangement, reusing other: Pane? = nil) {
            let known = other ?? self
            let reuse = known.state.reuse(for: tab, entries: RowsStateTests.big)
            wanted = tab
            state = known.state.after(reuse, for: tab)
            switch reuse {
            case .asItIs, .arrangeNow: hasRows = reuse == .arrangeNow || known.hasRows; onItsWay = nil
            case .oldOrder: hasRows = known.hasRows; onItsWay = tab
            case .blank: hasRows = false; onItsWay = tab
            case .keepWaiting:
                hasRows = known.hasRows
                // Begun again, its own as much as another pane's.
                onItsWay = tab
            }
        }

        /// The arrange on its way returns.
        mutating func arrangeReturns() {
            guard let arrived = onItsWay else { return }
            onItsWay = nil
            guard let next = state.arrival(of: arrived, tabWants: wanted) else { return }
            state = next
            hasRows = true
        }

        /// A read of the folder (its contents unchanged) completes.
        mutating func readCompletes() {
            guard !state.isUnchanged(byReadFor: wanted) else { return }
            state = .arranged(by: wanted)
            hasRows = true
            onItsWay = nil
        }

        /// What the user must never see: no rows while the pane claims to have them.
        var isRight: Bool {
            switch state {
            case let .arranged(by): by.serves(wanted) && hasRows
            case let .oldOrder(_, awaiting): awaiting.serves(wanted) && hasRows && onItsWay != nil
            case let .awaiting(awaited): awaited.serves(wanted) && !hasRows && onItsWay != nil
            }
        }
    }

    @Test func fromAToBAndBackQuicklyOnABigFolder() {
        var pane = Pane(showing: a)
        pane.show(b)
        #expect(pane.state == .awaiting(b) && pane.isRight)
        pane.show(a)  // Before B's rows arrived.
        // Not "as it is" over no rows: A's rows are awaited afresh.
        #expect(pane.state == .awaiting(a) && pane.isRight)
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: a) && pane.hasRows)
        pane.readCompletes()
        #expect(pane.state == .arranged(by: a) && pane.hasRows)
    }

    @Test func fromAToBAndBackWithTheReadLandingFirst() {
        var pane = Pane(showing: a)
        pane.show(b)
        pane.show(a)
        // Blank rows are never "nothing changed": the read puts A's rows in.
        pane.readCompletes()
        #expect(pane.state == .arranged(by: a) && pane.hasRows)
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: a) && pane.hasRows)
    }

    @Test func theOtherPaneOpeningTheFolderDuringTheBlank() {
        var left = Pane(showing: a)
        left.show(b)
        // The right pane takes the left's listing, for a tab asking as B does.
        var right = Pane(showing: c)
        right.show(b, reusing: left)
        #expect(right.state == .awaiting(b) && right.isRight)
        // Its own arrange, not the left pane's, brings its rows.
        right.arrangeReturns()
        #expect(right.state == .arranged(by: b) && right.hasRows)

        // And when the read lands first.
        var other = Pane(showing: c)
        other.show(a, reusing: left)
        #expect(other.state == .awaiting(a) && other.isRight)
        other.readCompletes()
        #expect(other.state == .arranged(by: a) && other.hasRows)
        other.arrangeReturns()
        #expect(other.state == .arranged(by: a) && other.hasRows)
    }

    @Test func aThirdTabDifferingBySortDuringTheBlank() {
        var pane = Pane(showing: a)
        pane.show(b)
        pane.show(c)
        // No rows to show in an old order: blank, not an "empty folder".
        #expect(pane.state == .awaiting(c) && pane.isRight)
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: c) && pane.hasRows)

        var again = Pane(showing: a)
        again.show(b)
        again.show(c)
        again.readCompletes()
        #expect(again.state == .arranged(by: c) && again.hasRows)
    }

    @Test func sortOnlySwitchesKeepRowsAllTheWay() {
        var pane = Pane(showing: b)
        pane.show(c)
        #expect(pane.state == .oldOrder(of: b, awaiting: c) && pane.isRight)
        pane.show(b)  // Back before C's order arrived: B's rows are there.
        #expect(pane.state == .arranged(by: b) && pane.hasRows)
        pane.show(c)
        pane.readCompletes()
        #expect(pane.state == .arranged(by: c) && pane.hasRows)
    }

    /// Tab A has a folder open, tab B of the same folder has none: each
    /// shows its own tree, all the way there and back.
    @Test func twoTabsOfOneFolderWithDifferentFoldersOpenEachShowTheirOwn() {
        let tabA = Self.arrangement(open: [Self.folder.appendingPathComponent("Sources", isDirectory: true)])
        let tabB = b
        var pane = Pane(showing: tabB)
        pane.show(tabA)  // A folder opened in place: other rows.
        #expect(pane.state == .awaiting(tabA) && pane.isRight)
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: tabA) && pane.isRight)
        pane.show(tabB)  // To tab B, nothing open there.
        #expect(pane.state == .awaiting(tabB) && pane.isRight)
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: tabB) && pane.isRight)
        pane.show(tabA)  // And back: A's tree, not B's rows.
        #expect(pane.state == .awaiting(tabA) && pane.isRight)
        pane.readCompletes()
        #expect(pane.state == .arranged(by: tabA) && pane.isRight)
        // A's arrange, begun before the read landed, arrives: still A's.
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: tabA) && pane.isRight)

        // Back to B before A's rows arrived: B's are awaited afresh, and A's late arrange is dropped.
        var quick = Pane(showing: tabA)
        quick.show(tabB)
        quick.show(tabA)
        quick.show(tabB)
        #expect(quick.state == .awaiting(tabB) && quick.isRight)
        #expect(quick.state.arrival(of: tabA, tabWants: tabB) == nil)
        quick.arrangeReturns()
        #expect(quick.state == .arranged(by: tabB) && quick.isRight)
    }

    @Test func aLateArrangeOfTheTabBeforeIsDropped() {
        var pane = Pane(showing: b)
        pane.onItsWay = a  // As if A's filter were still being arranged.
        pane.wanted = b
        pane.arrangeReturns()
        #expect(pane.state == .arranged(by: b))
    }
}
