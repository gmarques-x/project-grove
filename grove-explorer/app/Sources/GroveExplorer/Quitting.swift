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
    /// command in hand has ended. However long that takes: the status bar
    /// says at once what the wait is for, and goes on saying it.
    func quitMustWait() -> Bool {
        let plan = work.pending.quit(promptIsUp: work.prompt != nil, runIsGoing: work.runInHand != nil)
        guard plan.waits else { return false }
        guard !work.quitting else { return true }
        work.quitting = true
        if plan.answersPrompt { answerPrompt(.cancel) }
        if plan.cancelsRun { Task { await work.runner.cancel() } }
        sayQuitWaits()
        return true
    }

    /// The quit waits: the pane telling of the run says so in its meter's
    /// words (the next progress keeps them) and, like the pane that has
    /// the keys when no meter shows, in a notice that stays: not one of
    /// the few seconds `say` gives, since the wait can be longer.
    private func sayQuitWaits() {
        var tellers: [Side] = []
        for side in sides {
            guard case let .running(run, _, fraction, percent)? = work.statuses[side] else { continue }
            work.statuses[side] = .running(run: run, words: Self.finishingToQuit, fraction: fraction, percent: percent)
            tellers.append(side)
        }
        if tellers.isEmpty { tellers = [teller(for: browser.active)] }
        for side in tellers {
            noticeTimers[side]?.cancel()
            noticeTimers[side] = nil
            notices[side] = Self.finishingToQuit
        }
    }

    // MARK: The red button

    /// The window's red button is the model's from here on (`window` is
    /// the Explorer's, handed over by `WindowView`). Closing the window
    /// quits the app (`applicationShouldTerminateAfterLastWindowClosed`),
    /// but by then the window is gone: a quit that has to wait for a file
    /// would have nowhere to say so. So the button closes the window only
    /// when nothing is in hand; otherwise it asks the app to quit, and the
    /// window stays while the quit waits. SwiftUI's window delegate is
    /// left as it is.
    func takeCloseButton(of window: NSWindow) {
        guard live, let button = window.standardWindowButton(.closeButton) else { return }
        let target = closeButton ?? CloseButton(model: self)
        closeButton = target
        button.target = target
        button.action = #selector(CloseButton.pressed(_:))
    }

    /// The red button was pressed in `window`.
    fileprivate func closeOrQuit(_ window: NSWindow?) {
        if work.pending.isIdle { window?.close() } else { NSApp.terminate(nil) }
    }

    /// The last command has ended: the quit that waited for it goes on
    /// (`applicationWillTerminate` then saves the session as ever).
    func quitIfAsked() {
        guard work.quitting else { return }
        NSApp.reply(toApplicationShouldTerminate: true)
    }
}

/// What the window's red button calls (a control keeps no hold on its
/// target: the model does).
@MainActor
final class CloseButton: NSObject {
    private weak var model: AppModel?

    init(model: AppModel) { self.model = model }

    @objc func pressed(_ sender: Any?) {
        model?.closeOrQuit((sender as? NSView)?.window)
    }
}
