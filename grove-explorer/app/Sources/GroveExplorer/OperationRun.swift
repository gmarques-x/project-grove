import AppKit
import GroveExplorerCore

/// How a file command is done, from the key to the undo stack. Each command
/// is one job of `FileWork.pending`, done whole before the next begins:
///
///     validate → existingNames → the prompt, when any → run → record
///
/// with the same operation value from the first step to the last, and
/// nothing of another command, nor an undo or a redo (jobs of the same
/// queue), in between.
extension AppModel {
    /// Issues `operation`; `side` is the pane whose status bar tells of it.
    /// `field`: the rename field that waits for it; `group`: the command
    /// it is one part of (see `OperationJob`).
    func perform(
        _ operation: GroveExplorerCore.Operation, in side: Side, field: UUID? = nil, thenRename: Bool = false,
        group: UUID? = nil
    ) {
        enqueue(.operation(OperationJob(
            operation: operation, side: side, field: field, thenRename: thenRename, group: group)))
    }

    /// Takes `job` in: started now when nothing is in hand, else it waits
    /// for the ones before it. Nothing is ever done in a render.
    func enqueue(_ job: FileJob) {
        guard live, !work.quitting else { return }
        // Not onto a disk whose eject is already on its way (the eject
        // itself is refused while a command uses the disk: `ejectRefusal`).
        if let refusal = ejectingRefusal(for: job) {
            switch job {
            case let .operation(job):
                // A rename field waiting for it says so itself.
                if job.field != nil, work.rename?.id == job.field {
                    renameRefused(refusal)
                } else {
                    say(refusal, in: job.side)
                }
            case let .undo(side), let .redo(side):
                say(refusal, in: side)
            }
            return
        }
        guard let first = work.pending.add(job) else { return }
        work.busy = true
        Task { await drain(from: first) }
    }

    /// Does the jobs one after the other until none waits.
    private func drain(from first: FileJob) async {
        var job: FileJob? = first
        while let next = job {
            switch next {
            case let .operation(job):
                await run(job)
            case let .undo(side):
                await takeBack(redo: false, in: side)
            case let .redo(side):
                await takeBack(redo: true, in: side)
            }
            work.canUndo = await work.undo.canUndo
            work.canRedo = await work.undo.canRedo
            job = work.pending.finished()
        }
        // No suspension since `finished` said none waits: a command issued
        // from here on starts a drain of its own.
        work.busy = false
        // A disk that was "in use by a copy" no longer is.
        ejectRefusalsAreOver()
        quitIfAsked()
    }

    // MARK: One operation

    private func run(_ job: OperationJob) async {
        let operation = job.operation, side = job.side
        let runner = work.runner
        /// This job's rename field still waits for it (Escape may have
        /// closed it; another row's field is not this one's).
        var field: Bool { job.field != nil && work.rename?.id == job.field && work.rename?.committing == true }

        // 1. Does it make sense at all.
        do {
            try await runner.validate(operation)
        } catch {
            if field { renameRefused(error.sentence) } else { say(error.sentence, in: side) }
            return
        }

        // 2. The names that exist where it goes; 3. what to do about them.
        let existing = await runner.existingNames(for: operation)
        var asking = ConflictAsking(existing: [])
        if !existing.isEmpty {
            if FileCommands.asksAboutNames(operation) {
                // Cancel gives up the whole operation: nothing runs, and
                // nothing of the other operations the same command made.
                guard let asked = await ask(about: existing, for: operation) else {
                    if let group = job.group { work.pending.dropWaiting { $0.group == group } }
                    return
                }
                asking = asked
            } else if field, case let .rename(_, name) = operation {
                renameRefused(OperationStatus.nameTaken(name))
                return
            }
            // Otherwise a rename or a new folder: the runner fails it on
            // the name in use, and the failure is told below.
        }
        let plan = asking.plan, answers = asking.answers
        // Asked to quit meanwhile: what has not begun doesn't begin.
        guard !work.quitting else { return }

        // 4. The run, of the very operation the names were looked up for.
        work.run += 1
        let number = work.run, started = Date()
        work.runInHand = number
        let outcome = await runner.run(
            operation, resolve: { plan.choice(for: $0) ?? .skip },
            progress: { [weak self] progress in
                // Told on the thread doing the work: over to the main actor.
                Task { @MainActor in self?.progressed(progress, of: operation, in: side, run: number, since: started) }
            })
        // 5. Recorded at once: the undo stack reads the items as they are now.
        await work.undo.record(outcome, words: outcome.summary, operation: operation, answers: answers)
        work.runInHand = nil

        finished(operation, outcome, in: side, field: field, thenRename: job.thenRename)
    }

    /// Progress of the run numbered `run`. Shown once the run has taken a
    /// moment: a rename or a move within a disk is over before anyone
    /// could read a meter.
    private func progressed(
        _ progress: GroveExplorerCore.Progress, of operation: GroveExplorerCore.Operation, in side: Side, run: Int,
        since started: Date
    ) {
        guard work.runInHand == run else { return }
        // A quit asked for before the run had begun: its cancel found
        // nothing to stop then.
        if work.quitting { Task { await work.runner.cancel() } }
        guard Date().timeIntervalSince(started) >= 0.2 || work.quitting else { return }
        show(
            .running(
                run: run, words: work.quitting ? Self.finishingToQuit : OperationStatus.running(operation, progress),
                fraction: OperationStatus.fraction(progress), percent: OperationStatus.percent(progress)),
            in: side, for: nil)
    }

    /// The Cancel button of a status bar, drawn for the run numbered `run`:
    /// that run stops after the file it is on. A click that comes when it
    /// has ended stops nothing (not the run after it).
    func cancelRun(_ run: Int) {
        guard work.runInHand == run else { return }
        Task { await work.runner.cancel() }
    }

    private func finished(
        _ operation: GroveExplorerCore.Operation, _ outcome: Outcome, in side: Side, field: Bool, thenRename: Bool
    ) {
        let touched = AfterOperation.touchedFolders(by: operation, outcome: outcome)
        for folder in touched { work.touched[folder.standardizedFileURL.path] = folder }
        // An open folder renamed or moved here stays open where it went.
        openFoldersFollow(outcome.changes)
        filesChanged(in: touched)

        // What it left is selected once the panes list it (the watcher has
        // them read their folders); what is listed already, now.
        let new = AfterOperation.newItems(of: outcome)
        work.arrivals = new.isEmpty
            ? nil
            : Arrivals(items: new, renameIn: thenRename && new.count == 1 ? side : nil, until: Date().addingTimeInterval(3))
        for side in sides { arrived(in: side) }

        let changed = !outcome.changes.isEmpty
        if field {
            if let failure = outcome.failures.first {
                // Said under the field, not here: a meter shown meanwhile goes.
                meterGoes(except: nil)
                renameRefused(OperationStatus.renameReason(for: failure))
                return
            }
            endRename()
        }
        if outcome.failures.isEmpty {
            show(.done(outcome.summary, changed: changed, hint: changed), in: side, for: 5)
        } else {
            // It stays until the next thing the pane has to say.
            show(
                .failed(
                    line: OperationStatus.couldNot(operation, failed: outcome.failures.count), summary: outcome.summary,
                    items: outcome.failures.map(OperationStatus.line(for:)), changed: changed),
                in: side, for: nil)
        }
    }

    // MARK: Undo and redo

    private func takeBack(redo: Bool, in side: Side) async {
        do {
            let sentence: String
            if redo { sentence = try await work.undo.redo() } else { sentence = try await work.undo.undo() }
            show(.done(sentence, changed: true, hint: redo), in: side, for: 5)
        } catch {
            // Refused: the sentence says why, and whether the entry is gone.
            say(error.sentence, in: side)
        }
        // What it put back or made again is selected, as after a run.
        let restored = await work.undo.restored
        work.arrivals = restored.isEmpty
            ? nil : Arrivals(items: restored, renameIn: nil, until: Date().addingTimeInterval(3))
        for side in sides { arrived(in: side) }
        // The stack doesn't tell which folders it changed: any a run of
        // this window touched may be among them.
        filesChanged(in: Array(work.touched.values))
    }

    // MARK: The prompt

    /// Asks about each of `existing` in turn, unless an answer is for all
    /// the rest. Nil when the answer was Cancel.
    private func ask(about existing: [URL], for operation: GroveExplorerCore.Operation) async -> ConflictAsking? {
        var asking = ConflictAsking(existing: existing)
        watchPromptKeys()
        defer {
            stopWatchingPromptKeys()
            work.prompt = nil
        }
        while let current = asking.current {
            let incoming = FileCommands.incoming(for: current, in: operation) ?? current
            let remaining = asking.remaining
            // Two looks at the disk, off the main thread.
            let question = await Task.detached {
                Conflict.Question(incoming: incoming, existing: current, remaining: remaining)
            }.value
            // Asked to quit while the disk was read: as Cancel.
            guard !work.quitting else { return nil }
            let reply = await withCheckedContinuation { continuation in
                work.reply = continuation
                work.prompt = ConflictPromptState(
                    question: question, comingLabel: ConflictWords.comingLabel(for: operation))
            }
            guard let choice = reply.button.choice else { return nil }
            asking.answer(choice, applyToAll: reply.applyToAll)
        }
        return asking
    }

    /// A button of the prompt. Nothing when no answer is awaited (the next
    /// question is being read).
    func answerPrompt(_ button: ConflictButton) {
        guard let reply = work.reply, let prompt = work.prompt else { return }
        work.reply = nil
        reply.resume(returning: (button, prompt.applyToAll && prompt.question.remaining > 0))
    }

    // MARK: After a run

    /// The status bar of `side` says `status`, for `seconds` or until the
    /// next thing it has to say.
    func show(_ status: PaneStatus, in side: Side, for seconds: Int?) {
        let side = teller(for: side)
        meterGoes(except: side)
        work.statusTimers[side]?.cancel()
        work.statusTimers[side] = nil
        work.statuses[side] = status
        if case .failed = status {} else if work.failuresShown == side { work.failuresShown = nil }
        // What the pane said before about its folder is over; not for a
        // meter's next step, which would take every notice away unread.
        if case .running = status {} else if notices[side] != nil { notices[side] = nil }
        guard let seconds else { return }
        work.statusTimers[side] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.work.statuses[side] = nil
        }
    }

    /// There is one run, so one meter: a pane other than `side` that
    /// still shows one (it told for a pane that was closed then and is
    /// open again) shows it no more.
    private func meterGoes(except side: Side?) {
        for other in [Side.left, .right] where other != side {
            if case .running = work.statuses[other] { work.statuses[other] = nil }
        }
    }

    /// ⌘\ closed the pane `closed`; `kept` is the one pane now, at the left.
    /// What the status bars said goes where it can still be read: the kept
    /// pane's own status and notice go with it, and a meter or a failure
    /// (with its list) of the pane that closed is said at the left
    /// instead. A meter comes before anything else: there is one run.
    func statusFollows(closed: Side, kept: Side) {
        let own = work.statuses[kept], theirs = work.statuses[closed], notice = notices[kept]
        var from = kept
        switch (own, theirs) {
        case (.running?, _): break
        case (_, .running?), (_, .failed?): from = closed
        default: break
        }
        // Nothing moves: the left pane stays and the right had nothing to keep.
        if kept == .left, from == .left {
            if work.failuresShown == .right { work.failuresShown = nil }
            work.statusTimers[.right]?.cancel()
            work.statusTimers[.right] = nil
            work.statuses[.right] = nil
            noticeTimers[.right]?.cancel()
            noticeTimers[.right] = nil
            notices[.right] = nil
            return
        }
        let status = from == kept ? own : theirs
        let listShown = work.failuresShown == from
        work.failuresShown = nil
        for side in [Side.left, .right] {
            work.statusTimers[side]?.cancel()
            work.statusTimers[side] = nil
            work.statuses[side] = nil
            noticeTimers[side]?.cancel()
            noticeTimers[side] = nil
            notices[side] = nil
        }
        if let status {
            // A summary goes after its few seconds, counted again from here.
            if case .done = status { show(status, in: .left, for: 5) } else { show(status, in: .left, for: nil) }
            if listShown, case .failed = status { work.failuresShown = .left }
        }
        if let notice { say(notice, in: .left) }
    }

    /// The contents of `folders` changed: the totals of each and of the
    /// folders it is in are worked out again. (The lists themselves follow
    /// their watchers.)
    private func filesChanged(in folders: [URL]) {
        guard live, !folders.isEmpty else { return }
        for folder in folders { sizeQueue.changed(folder) }
        let stale = AfterOperation.staleTotals(among: Array(sizes.keys), touched: folders)
        if !stale.isEmpty {
            var kept = sizes
            for url in stale { kept[url] = nil }
            sizes = kept
        }
        wantSizes()
    }

    /// The pane has read its folder (or a run just ended): the items the
    /// last run left there are selected, and a new folder is renamed in place.
    func arrived(in side: Side) {
        guard let arrivals = work.arrivals, !arrivals.done.contains(side) else { return }
        guard arrivals.until > Date() else {
            work.arrivals = nil
            return
        }
        guard let tab = browser.tab(side), let listing = listing(for: side),
            listing.folder.standardizedFileURL.path == tab.folder.standardizedFileURL.path
        else { return }
        // In the tab's folder or in a folder open in it, at any depth;
        // selected only where it is a row (`select`).
        let listed = listing.all.map(\.url) + listing.children.values.flatMap { $0.map(\.url) }
        let here = AfterOperation.arrivals(
            arrivals.items, in: [tab.folder] + Array(listing.children.keys), listed: listed)
        guard !here.found.isEmpty else { return }
        select(Set(here.found), in: side)
        reveal(here.found[0], in: side)
        // A listing read while the run was going has only some: the next has all.
        guard here.complete else { return }
        // Done for this pane: a later read leaves the selection to the user.
        work.arrivals?.done.insert(side)
        if arrivals.renameIn == side, let made = here.found.first { beginRename(of: made, in: side) }
    }
}
