import AppKit
import GroveExplorerCore

/// Quitting while files are being worked on. The engine never leaves half
/// an item under its name, but a process that ends in the middle of a file
/// leaves the hidden partial copy behind, and in the middle of a replace
/// the replaced item in the Trash with nothing at its name and no undo. So
/// the quit waits for the command in hand to come to its own end.
extension AppModel {
    static let finishingToQuit = "Finishing the current file before quitting…"

    /// The app is asked to quit. False: nothing is in hand, quit now.
    /// True: the quit must wait (`.terminateLater`). The commands still
    /// queued are dropped, the run in hand is cancelled (it stops after the
    /// file it is on and removes its partial copy), an open prompt is
    /// answered with Cancel, and `quitIfAsked` lets the app go once the
    /// command in hand has ended. However long that takes: after ten
    /// seconds the status bar says what the wait is for.
    func quitMustWait() -> Bool {
        let plan = work.pending.quit(promptIsUp: work.prompt != nil, runIsGoing: work.runInHand != nil)
        guard plan.waits else { return false }
        guard !work.quitting else { return true }
        work.quitting = true
        if plan.answersPrompt { answerPrompt(.cancel) }
        if plan.cancelsRun { Task { await work.runner.cancel() } }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.quitIsSlow()
        }
        return true
    }

    /// Ten seconds on, one large file is still being written.
    private func quitIsSlow() {
        guard work.quitting, work.busy else { return }
        work.quitIsSlow = true
        // The pane telling of the run says it now; the next progress keeps it.
        for (side, status) in work.statuses {
            guard case let .running(run, _, fraction, percent) = status else { continue }
            work.statuses[side] = .running(run: run, words: Self.finishingToQuit, fraction: fraction, percent: percent)
        }
        if !work.statuses.values.contains(where: { if case .running = $0 { true } else { false } }) {
            say(Self.finishingToQuit, in: browser.active)
        }
    }

    /// The last command has ended: the quit that waited for it goes on
    /// (`applicationWillTerminate` then saves the session as ever).
    func quitIfAsked() {
        guard work.quitting else { return }
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}
