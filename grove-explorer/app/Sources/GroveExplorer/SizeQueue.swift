import Foundation
import GroveExplorerCore

/// Asks the calculator for the totals of the folders and packages the panes
/// show: a few at a time, the rows in view first, and again for those that
/// were answered with nothing once their folder has been quiet for a second.
@MainActor
final class SizeQueue {
    /// A total arrived.
    var onSize: (URL, Int64) -> Void = { _, _ in }
    /// A total given up by `keep` may be wanted after all (the pane came
    /// back before the cancelled walk had answered), or it is time to try
    /// the unanswered again: the owner calls `want` with what it shows now.
    var onAskAgain: () -> Void = {}

    private let calculator = SizeCalculator()
    /// Wanted and not yet asked for, the next one first.
    private var queue: [URL] = []
    private var inFlight: Set<URL> = []
    /// Asked and answered with nothing (the folder can't be read, or a walk
    /// was cancelled under it by a change): asked again after the next change.
    private var unanswered: Set<URL> = []
    private var retry: Task<Void, Never>?
    /// On their way and given up by `keep`: their answer, a nil from the
    /// cancelled walk, is not a refusal.
    private var givenUp: Set<URL> = []
    /// The calculator walks two at once; two more wait there in order.
    private static let atOnce = 4

    /// `urls` are wanted, in this order; anything else waiting is dropped.
    /// Those on their way or left unanswered are not asked for twice.
    func want(_ urls: [URL]) {
        queue = urls.filter { !inFlight.contains($0) && !unanswered.contains($0) }
        pump()
    }

    /// The rows in view: their totals come before the others'.
    func first(_ visible: [URL]) {
        let first = Set(visible)
        let front = queue.filter(first.contains)
        guard !front.isEmpty else { return }
        queue = front + queue.filter { !first.contains($0) }
        pump()
    }

    /// A pane left its folder: only `wanted` (what the panes still show) is
    /// kept. Walks on their way for anything else are cancelled, one by one,
    /// and give their slots back; a walk for a row still shown, the other
    /// pane's large folder say, goes on undisturbed.
    func keep(_ wanted: Set<URL>) {
        queue.removeAll { !wanted.contains($0) }
        unanswered.formIntersection(wanted)
        for url in inFlight where !wanted.contains(url) && givenUp.insert(url).inserted {
            Task { await calculator.cancel(url) }
        }
    }

    /// `folder` changed: the sizes of the folders it is in are no longer
    /// right. A walk the calculator cancels for it answers nil; those are
    /// asked again once the folder has been quiet for a second, or a busy
    /// folder would never show a size.
    func changed(_ folder: URL) {
        Task { await calculator.invalidate(folder) }
        retry?.cancel()
        retry = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            unanswered = []
            onAskAgain()
        }
    }

    private func pump() {
        while inFlight.count < Self.atOnce, !queue.isEmpty {
            let url = queue.removeFirst()
            inFlight.insert(url)
            Task {
                let size = await calculator.size(of: url)
                inFlight.remove(url)
                if givenUp.remove(url) != nil {
                    // Its row went while it was walked. Should the pane have
                    // come back to it meanwhile, it is asked for afresh.
                    onAskAgain()
                } else if let size {
                    onSize(url, size)
                } else {
                    unanswered.insert(url)
                }
                pump()
            }
        }
    }
}
