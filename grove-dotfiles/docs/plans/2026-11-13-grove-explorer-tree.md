# Grove Explorer: Folders That Open In Place — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Folders in Grove Explorer's list open in place, as in Finder's list view: a chevron on every folder that has something in it, its contents indented beneath.

**Architecture:** The rows a tab shows become the result of one pure Core function over the tab folder's listing, the listings of the folders that are open, the set of open folders, the sort, the filter and the hidden flag. The app keeps one listing per open folder (read, watched and sized exactly as the tab's own folder is) and draws depth and the chevron in the existing table. The rows-state machine and every safety rule stay as they are, deciding over the tree's rows.

**Tech Stack:** Swift 6 (Command Line Tools), SwiftUI + AppKit (`NSTableView`), Swift Testing. No new dependency.

**Spec:** `grove-dotfiles/docs/specs/2026-11-12-grove-explorer-design.md`, §16 "Folders that open in place" (read it whole, and §6–§8). Mock-ups the owner chose from: private images (look, never copy). The mock program that drew them, whose tree drawing may be adapted: `$TMPDIR/tree-mock/` if it still exists.

## Global Constraints

- UI rules: `~/.claude/skills/grove-ui/SKILL.md`, binding. Tokens only; mono type; icons through `GroveIcon`.
- Chevron: `chevron.right` closed, `chevron.down` open, 12 pt, quiet colour; text colour while the pointer is on it. Gutter 16 pt (12 pt box + 4 pt) on every row. Indent 16 pt per level, never capped. Rows 24 pt. Hit area: the gutter cell, 16 × 24 pt.
- A chevron only on a folder with at least one item that would show (hidden items count only while shown). None on files, packages, links to folders, unreadable folders (size "--").
- ⌥→ stops when the tab would show more than 10,000 rows.
- The safety rules of the first build hold unchanged: commands act only on rows the user can see; a pane, and an opened folder, whose contents have not arrived has no rows; operations are values captured at the keypress; every change to files goes through the single run path (`perform`/`enqueue`); the app target has no file-moving code of its own; nothing `@Published` is written during a view update.
- A row's state is one value: no flag beside the rows that can disagree with them (three defects in the first build came from that).
- Build: Command Line Tools only; the `@State` macro is unavailable. Tests: Swift Testing. Core logic is tested; the app target has no tests, so decisions live in Core.
- Commits: `area: summary` plus a short body; each ends with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Branch `grove-explorer`. Never stage `grove-dotfiles/config/grove-keys/keys.toml`. Nothing from the private working folders is committed.
- Live machine: Grove Explorer is installed and may be open. Workers never install, launch, quit or kill it; the built binary runs only with the offscreen one-shots (`--render`, `--time-list`, `--audit-accessibility`).

## Review Focus

1. **A selection that holds a folder and items inside it:** an operation takes the folder once; nothing is copied twice, and a move never moves a child out from under its parent mid-run. → Task 1.
2. **Rows of an opened folder whose read has not landed, or that vanished:** no rows, no selection, no command can reach them; when the folder goes away its rows and any selection in them go. → Tasks 1 and 3.
3. **A folder that changes while open** (items added, removed, renamed; the folder itself renamed or moved by another program): the tree stays true within a second, the open state follows a rename made in the app and is dropped for one made elsewhere, and the selection never slides onto another item. → Task 3.
4. **Very large trees:** ⌥→ on a huge folder stops at 10,000 rows; 50,000 rows across open folders sort, filter and scroll without a visible pause; watchers and size walks stay bounded (one watcher per open folder: cap the number of open folders watched and say what happens beyond it). → Tasks 1, 3 and 5.
5. **Looking into folders for the chevron** must not walk trees, must not block the main thread, must stop when the tab leaves, and must not ask macOS for permission more often than the size calculation already does. → Task 2.

---

## File structure

```
grove-explorer/app/Sources/GroveExplorerCore/
  Tree.swift            the rows of a tab: TreeRow, Tree.rows(...), limits, selection rules, status
  FolderPeek.swift      "does this folder have something that would show": the answer type and its cache rules
  (Arrangement.swift, Session.swift, Browser.swift, CommandList.swift, Spoken.swift, StatusText.swift: extended)
grove-explorer/app/Sources/GroveExplorer/
  TreeModel.swift       AppModel extension: open folders, their listings, reads, watchers, expand/collapse
  TreeCells.swift       the gutter, the chevron, the indent, the "···" row in the list's cells
  (Reading.swift, Listing.swift, FileList.swift, FileListCells.swift, FileListActions.swift, ListDragDrop.swift,
   Commands.swift, KeyboardReach.swift, ListAccessibility.swift, PaneText.swift, Render.swift, RenderSamples.swift: extended)
grove-themes/app/Sources/GroveUI/GroveIcon.swift     two cases: closed (chevron.right) exists as `forward`? add `open`/`closed` only if no existing case fits
docs/manual/09-files.md, the spec's §7
```

---

### Task 1: The tree's rows, in Core

**Files:** Create `Sources/GroveExplorerCore/Tree.swift`; Test `Tests/GroveExplorerCoreTests/TreeTests.swift`

**Interfaces:**
- Consumes: `Entry`, `Sorting.sorted`, `Filter`, `SortOrder`.
- Produces:
  ```swift
  public struct TreeRow: Equatable, Sendable, Identifiable {
      public var id: URL { entry.url }
      public let entry: Entry
      public let depth: Int                 // 0 for the tab folder's own items
      public let fold: Fold                 // what the chevron shows
      public let isContext: Bool            // kept only because a descendant matches the filter
      public enum Fold: Equatable, Sendable { case none, closed, open, loading }
  }
  public enum TreeItem: Equatable, Sendable, Identifiable {   // what the table draws, row by row
      case row(TreeRow)
      case loading(under: URL, depth: Int)                    // the "···" line
  }
  public struct TreeInput: Sendable {
      public var root: [Entry]                         // the tab folder's entries, unsorted
      public var children: [URL: [Entry]]              // entries of each OPEN folder whose read has landed (standardized URL keys)
      public var open: Set<URL>                        // folders the user opened
      public var hasContents: [URL: Bool]              // FolderPeek's answers; a missing key means "not known yet"
      public var sort: SortOrder
      public var folderSizes: [URL: Int64]
      public var filter: String                        // "" = none
      public var showHidden: Bool
  }
  public enum Tree {
      public static let rowLimit = 10_000
      public static func items(_ input: TreeInput) -> [TreeItem]
      public static func counts(_ items: [TreeItem]) -> (rows: Int, foldersOpen: Int)
      /// The URLs an operation should take: the selection minus anything whose ancestor is also selected.
      public static func operands(of selection: Set<URL>, in items: [TreeItem]) -> [URL]
      /// The folders to open for ⌥→ on `folder`, breadth first, stopping before `items` would pass `rowLimit`.
      public static func openAll(under folder: URL, known children: [URL: [Entry]], showing: Int) -> (open: [URL], stoppedAtLimit: Bool)
      /// The row ← goes to from `url`: its parent row, or nil at depth 0.
      public static func parentRow(of url: URL, in items: [TreeItem]) -> URL?
      /// Open folders that are no longer reachable (their ancestor closed or gone): to be dropped from `open`.
      public static func orphans(open: Set<URL>, root: URL, children: [URL: [Entry]]) -> Set<URL>
  }
  ```
- [ ] **Step 1: tests for `items`.** A fixture tree in memory (no disk): root with folders `a` (open, read: file `a1`, folder `a2` closed), `b` (open, not read → a `.loading` item beneath), `c` (closed, `hasContents[c] == true` → `.closed`), `d` (closed, `hasContents[d] == false` → `.none`), `e` (not in `hasContents` → `.none`), a package, a link to a folder (`.none` both), files. Assert the exact sequence of items with depths and folds; children sorted among themselves by `sort` with folders on top at every level, by name ascending and by size descending; hidden entries inside an open folder appear only with `showHidden`; a folder in `open` that is not an entry of its parent (stale) contributes nothing.
- [ ] **Step 2: tests for the filter.** With `filter = "read"`: matches at depth 0, 1 and 3 are rows with `isContext == false`; each match's ancestors are rows with `isContext == true`; non-matching siblings are gone; an open folder with no match inside and not itself a match is gone; the filter never adds a folder to the tree that is not open; `counts` returns matches only when filtered (document which: the status "5 of 33" needs both the filtered rows and the unfiltered count: give `items` a twin or a `counts(unfiltered:)` and test the pair).
- [ ] **Step 3: tests for `operands`.** Selection {folder `a`, `a/a1`, file `f`} → [`a`, `f`] in row order; {`a/a1`, `a/a2`} → both; a selected URL not in `items` is dropped (Review Focus 2).
- [ ] **Step 4: tests for `openAll`, `parentRow`, `orphans`.** `openAll` on a tree of 3 levels returns the folders breadth first; with `showing = 9_990` and a folder of 30 items it stops and reports the limit; `parentRow` of a depth-2 row is its depth-1 folder; `orphans` returns open folders under a closed or vanished ancestor.
- [ ] **Step 5: implement** (one pass building rows depth first; standardized-path keys through the existing `URL.isSameFolder`/path helper); a performance test `fiftyThousandRowsAcrossOpenFoldersUnderHalfASecond` in the style of the existing timing tests (best of 3, serialized, time printed).
- [ ] **Step 6:** `swift test --filter TreeTests`; commit.

### Task 2: Does a folder have something in it; state, session, commands, words

**Files:** Create `Sources/GroveExplorerCore/FolderPeek.swift`; Modify `Arrangement.swift`, `Browser.swift`, `Session.swift`, `CommandList.swift`, `StatusText.swift`, `Spoken.swift`; Tests `FolderPeekTests.swift`, and additions to `ArrangementTests`/`RowsStateTests`, `BrowserTests`, `SessionTests`, `CommandListTests`, `StatusTextTests`, `SpokenTests`; the spec's §7.

**Interfaces:**
- Produces:
  ```swift
  public enum FolderPeek {
      /// True when `folder` holds at least one item that would show. Reads at most until the first such item
      /// (never the whole folder, never below it). Nil when it can't be read.
      public static func hasContents(_ folder: URL, showHidden: Bool) -> Bool?
  }
  // Arrangement gains the open set, so a listing arranged for one set of open folders is not reused for another:
  public struct Arrangement { … public var open: Set<URL> … }     // `serves` compares it; `hasSameItems` too
  // Tab remembers what is open, per folder visited, bounded:
  public struct Tab { … public var openFolders: [URL: Set<URL>] … }   // key: the tab folder; at most 20 folders remembered, oldest dropped
  //   decoded with a default (older session files have no such key)
  // CommandList gains four rows (Grove table), spec §7 gains the same four:
  //   → "Open Folder in Place"   ← "Close Folder, or Go to Its Parent Row"   ⌥→ "Open Folder and Everything Inside"   ⌥← "Close Folder and Everything Inside"
  // StatusText: items(total:foldersOpen:selected:selectedBytes:filteredFrom:) per spec §16's status rules
  // Spoken: a row's sentence gains "level N" (N ≥ 2 only) and, for a folder with a chevron, "open"/"closed"
  ```
- [ ] **Step 1: `FolderPeek` tests on temp folders:** empty → false; one file → true; only a dot-file → false, and true with `showHidden`; one subfolder → true; unreadable (mode 000, restored after) → nil; a link to a folder is not followed (the caller never asks for links). Implement with `opendir`/`readdir` (or `FileManager.enumerator` with `.skipsSubdirectoryDescendants`) stopping at the first showing name; a test that a folder of 50,000 files answers in under 5 ms (it must not list the folder).
- [ ] **Step 2: Arrangement.** Tests: an arrangement for open set {a} does not serve a tab whose open set is {a, b}; same sets serve; `RowsState` sequences from the first build still pass with `open` empty; add the sequence "open a folder in tab A, switch to tab B of the same folder with nothing open, back": each tab shows its own tree. Implement.
- [ ] **Step 3: Browser/Session.** Tests: opening and closing folders records per tab folder; navigating away and back restores the set; more than 20 remembered folders drops the oldest; `repair` drops open folders that no longer exist; a session file without `openFolders` loads; round trip. Implement.
- [ ] **Step 4: CommandList and spec §7.** Add the four rows to the spec's Grove table and to `CommandList.all` with their keys (→, ←, ⌥→, ⌥← act only with the keyboard in a list and no field up); update the §7-parsing test's pinned counts with a comment naming the four rows; `noKeyIsGivenToTwoCommands` stays green (← and → are free in the list today: confirm against `listKeys`).
- [ ] **Step 5: words.** `StatusText` and `Spoken` tests with the spec's strings ("212 items · 3 folders open"; "2 of 19 selected · 350 KB"; "5 of 33"; "Package.swift, Swift Source, 2 KB, yesterday at 13:05, level 3"; "Sources, folder, open, …"). Implement.
- [ ] **Step 6:** the Core suites touched; commit.

### Task 3: The model: open folders, their listings, reads, watchers, sizes

**Files:** Create `Sources/GroveExplorer/TreeModel.swift`; Modify `Listing.swift`, `Reading.swift`, `AppModel.swift`, `Upkeep.swift`, `SizeQueue.swift`, `PaneText.swift`, `FileCommands.swift`, `Navigation.swift`, `OperationRun.swift`; Core additions where a decision is pure (with tests).

**Interfaces:**
- Consumes: Tasks 1–2; the first build's `ReadGate`, `PaneRows`, `RowsState`, `SizeWanted`, `WatchPlan`.
- Produces: `FolderListing` holds the tab folder's entries plus `children: [URL: [Entry]]` and `peeks: [URL: Bool]`, and its shown rows are `[TreeItem]` built by `Tree.items` off the main thread with the sort (the existing arrange path). `AppModel` gains `toggleFold(_ url: URL, in side: Side)`, `openAll(_:in:)`, `closeAll(_:in:)`, `foldLeft(in:)`/`foldRight(in:)` (the ←/→ commands). `entries(for:)` and `chosenItems` return what `Tree` says is showing (`Tree.operands` for operations).
- [ ] **Step 1: one listing, many folders.** Reading an open folder goes through the same guarded path as the tab's folder: a read per open folder with its own `ReadGate`, results dropped unless the folder is still open in that tab and the pane still shows that tab's folder (extend the Core predicate `PaneRows.areCurrent` to cover a child folder, with tests: a child read landing after the folder was closed, after the tab navigated, after the tab was switched, is dropped).
- [ ] **Step 2: watchers.** One `FolderWatcher` per open folder of the tabs on screen, through `WatchPlan` (extend it in Core with tests: which folders to watch given the panes' tabs and open sets; at most 64 watched open folders per pane, nearest the top of the list first, the rest refreshed when the tab's own folder changes or the row scrolls into view: say so in the status bar only if a folder is beyond the cap and changed). A watched open folder that vanishes closes: its rows, its selection and its entry in `open` go (`Tree.orphans`).
- [ ] **Step 3: peeks.** `FolderPeek.hasContents` for the folders in view first, off the main thread, a few at a time, cancelled when the tab leaves; re-asked for a folder when its parent's listing changes or its own watcher fires; answers stored in the listing and cleared with it. A folder whose answer is unknown has no chevron.
- [ ] **Step 4: sizes.** `SizeWanted` includes every showing folder and package at any depth (extend the Core function and its tests); size invalidation after an operation covers open ancestors.
- [ ] **Step 5: commands.** → opens the selected folder (one row selected, a folder with contents, closed); on an open folder it selects its first child; ← closes an open folder, otherwise selects the parent row; ⌥→ uses `Tree.openAll` and says "Stopped at 10,000 rows" in the status bar at the limit; ⌥← closes the folder and forgets what was open inside. A click on the chevron toggles; ⌥-click is ⌥→/⌥←. Rename in the app of an open folder (through the run path) keeps it open under its new name (remap `open` and `children` keys on the operation's `Change.moved`); new folder and rename-in-place find their row in the tree; arrivals (the items an operation made) are selected wherever they show.
- [ ] **Step 6: the rules.** Walk every reader of rows and selection (`chosenItems`, `visibleSelection`, `selectAll`, `openSelection`, type-to-jump, Quick Look, the context menu, drag source, drop target, VoiceOver's rows) and make each see the tree's rows; add a Core test for anything decided there. `--time-list` gains a tree case (50,000 rows across 200 open folders): report the numbers.
- [ ] **Step 7:** build; Core bundle `swift test`; commit in logical commits.

### Task 4: The list: gutter, chevron, indent, the loading row

**Files:** Create `Sources/GroveExplorer/TreeCells.swift`; Modify `FileListCells.swift`, `FileList.swift`, `FileListActions.swift`, `ListDragDrop.swift`, `RenameField.swift`, `ContextMenu.swift`, `Render.swift`, `RenderSamples.swift`; `grove-themes/app/Sources/GroveUI/GroveIcon.swift` and its list test only if no existing case is `chevron.right`/`chevron.down` (`.forward` and `.menu` are: reuse them).

- [ ] **Step 1: drawing.** The name cell draws, left to right: indent (16 pt × depth), the gutter (chevron or empty), the icon, the name. The header's "Name" stays at the pane's edge. The chevron takes the text colour while the pointer is in its gutter cell. The `.loading` item draws "···" in the quiet colour at the child's icon position, nothing in the other columns, no selection fill, no hover fill. Under a filter, context rows draw their name in the quiet colour, icon and chevron unchanged. Unreadable folders show "--" in Size. Fills and the drop line span the row.
- [ ] **Step 2: hit testing.** A click in a row's gutter cell (16 × 24 pt at that row's indent) toggles the fold and does not change the selection; ⌥-click opens or closes everything inside. Double-click on the chevron does not navigate. The `.loading` item can't be selected, clicked, dragged or dropped on; arrow keys pass over it.
- [ ] **Step 3: rename, drag, menu at depth.** The rename field starts at the indented name; a drop on a nested folder row goes into that folder (the existing rule, now with depth); a drag carries `Tree.operands`; the context menu for a nested row acts on that row.
- [ ] **Step 4: renders.** `--render` states `tree`, `tree-filter`, `tree-rename`, `tree-drop`, `tree-narrow`, `tree-size-sort` from sample data matching the mock-ups; render dark-medium and light-medium into a private folder, open them with Read and compare with the private tree mock-ups until they match in layout, sizes and colours. The existing 28 render states must be byte-identical except where every list row now has the 16 pt gutter: say which changed and look at them.
- [ ] **Step 5:** build; commit.

### Task 5: VoiceOver, the audit, the manual, the whole check

**Files:** Modify `ListAccessibility.swift`, `AccessibilityAudit.swift`, `AccessibilityLive.swift`, `docs/manual/09-files.md`, the spec (§6's "List view only … no expandable folders" wording if any, §16 if the build changed anything).

- [ ] **Step 1: VoiceOver.** A row element answers its disclosure level, whether it is disclosed (expanded), its disclosed rows and its disclosing row (`NSAccessibilityRow`'s disclosure methods), and takes "expand"/"collapse" as the fold action; the `.loading` item is not an element. The label uses Task 2's sentence. Elements stay one per URL, kept by the table, as the first build's review required.
- [ ] **Step 2: the audit.** `--audit-accessibility` gains the `tree` state: through the real accessibility server, a nested row reports its level, a folder row reports expanded/collapsed, and a row keeps its identity when its parent is closed and reopened. Run `all`: 0 unlabelled, 0 problems.
- [ ] **Step 3: the manual.** `docs/manual/09-files.md`: a short section "Opening folders in place" (the chevron, → ← ⌥→ ⌥←, what ⌘↓ still does, the filter with open folders, where paste and new folder go) and the four keys in its tables; the Core test that parses spec §7 stays green.
- [ ] **Step 4: everything once.** `swift test` in grove-explorer/app (whole bundle), and in grove-themes/app and grove-keys/app if GroveUI changed; `--audit-accessibility all`; `--time-list 50000` flat and tree; `zsh -lc 'cd grove-dotfiles && bats tests/modules_explorer_app.bats'`. Commit.
- [ ] **Step 5: the by-hand list.** Append a "Tree" area to the by-hand checklist in the SDD workspace: open and close by click and by keys; ⌥→ on a big folder stops at 10,000; a file created by another program inside an open folder appears; delete an open folder in Finder: its rows go; select a folder and a file inside it, F5: the folder arrives once; ⌘F with folders open; rename an open folder: it stays open; quit and reopen: the same folders are open; an empty folder has no chevron and gains one when a file is dropped into it; VoiceOver reads level and open/closed. STOP: the controller installs.
