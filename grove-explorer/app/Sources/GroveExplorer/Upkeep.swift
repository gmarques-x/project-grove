import AppKit
import GroveExplorerCore
import GroveThemesCore
import GroveUI
import SwiftUI

/// What keeps the window current beside the folders themselves: the folder
/// totals and the scheme's colours.
extension AppModel {
    // MARK: Sizes

    /// Asks for the total of every folder and package the panes show whose
    /// total isn't known, in the order shown (so the top of the list first),
    /// and forgets the totals of what is no longer shown.
    func wantSizes() {
        guard live else { return }
        // Totals are kept for every row on screen. (A pane between two
        // folders has none: `entries(for:)`.)
        let shown = Set(sides.flatMap { entries(for: $0) }.map(\.url))
        if sizes.keys.contains(where: { !shown.contains($0) }) { sizes = sizes.filter { shown.contains($0.key) } }
        sizeQueue.want(wantedSizes().filter { sizes[$0] == nil })
    }

    /// The folders and packages whose totals are wanted: the rows of each
    /// pane that shows the folder its tab is on. A pane between two folders
    /// (navigated, the new one not yet read) wants none of its old rows.
    func wantedSizes() -> [URL] {
        SizeWanted.urls(in: sides.compactMap { side in
            browser.tab(side).map {
                SizeWanted.Pane(tabFolder: $0.folder, listedFolder: listing(for: side)?.folder, shown: entries(for: side))
            }
        })
        // Nothing is walked on a disk that is being ejected: a walk would hold it.
        .filter { !isBeingEjected($0) }
    }

    /// Whether a total may still come for the folder or package at `url`:
    /// not when the walk came back with nothing (it can't be read), nor on
    /// a disk being ejected, where nothing is walked.
    func awaitsTotal(_ url: URL) -> Bool {
        !sizeQueue.hasGivenUp(on: url) && !isBeingEjected(url)
    }

    /// The rows in view: their totals come before the others'.
    func wantSizesFirst(for visible: [URL]) {
        sizeQueue.first(visible)
    }

    func measured(_ url: URL, _ size: Int64) {
        sizes[url] = size
        for side in sides where browser.tab(side)?.sort.column == .size { arrangeSoon(side) }
    }

    /// Sorted by size, totals arrive one after the other: one sort once
    /// they have paused, not one for each.
    private func arrangeSoon(_ side: Side) {
        sizeSorts[side]?.cancel()
        sizeSorts[side] = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            arrange(side)
        }
    }

    // MARK: Theme

    /// The scheme's colours now, and again whenever grove-themes' state file
    /// changes (its folder is what can be watched).
    func followTheme() {
        let environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser
        let state = StatePath.url(environment: environment, home: home)
        let cli = environment["GROVE_THEMES_CLI"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/bin/grove-themes")
        let themes = GroveThemesClient(runner: ProcessRunner(path: cli))
        let refresh: @MainActor (AppModel) -> Void = { model in
            // Other files change in that folder too: only the scheme's own counts.
            let now = try? Data(contentsOf: state)
            guard model.themeWatcher == nil || now != model.themeState else { return }
            model.themeState = now
            Task {
                guard let list = try? await themes.list() else { return }
                model.colors = list.palettes[list.current].flatMap(ThemeColors.init(palette:)) ?? .fallback
            }
        }
        refresh(self)
        themeWatcher = FolderWatcher(folder: state.deletingLastPathComponent()) { [weak self] in
            Task { @MainActor in
                if let self { refresh(self) }
            }
        }
    }
}
