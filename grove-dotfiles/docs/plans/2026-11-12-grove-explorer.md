# Grove Explorer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grove Explorer, a file browser with one or two panes, tabs in each, Finder's keys, a list view, safe file operations with undo, and Grove Icons.

**Architecture:** A SwiftPM package `grove-explorer/app` with a pure `GroveExplorerCore` (entries, sorting, state, operations, undo, config) and an app target `GroveExplorer` (SwiftUI window, an `NSTableView` list, AppKit for drag, Quick Look and menus), drawn with the shared `GroveUI` library. Installed by the grove module `94-explorer-app`.

**Tech Stack:** Swift 6 (Command Line Tools, no Xcode), SwiftUI + AppKit, macOS 14+, Swift Testing, bats for the installer.

**Spec:** `grove-dotfiles/docs/specs/2026-11-12-grove-explorer-design.md` (read it whole before any task). Mock-ups: `artifacts/grove-explorer/mockups/*.png` (private; look, never copy into tracked files). The mock-up program's views may be adapted: `<session scratchpad>/explorer-mock/`.

## Global Constraints

- UI rules: `~/.claude/skills/grove-ui/SKILL.md`, binding. Tokens only (`GroveType`, `GroveSpace`, `GroveRadius`, theme roles); no literal colour, font size, radius or padding in a view; all app text in `GroveFont.mono`.
- Build: Command Line Tools only. The `@State` macro is unavailable: use `State(initialValue:)` with a comment, or an `ObservableObject`. `@StateObject`, `@ObservedObject`, `@Environment`, `@FocusState` work.
- Tests: Swift Testing (`import Testing`). `Package.swift` copies the `testSettings` block from `grove-keys/app/Package.swift`.
- macOS 14 minimum (`platforms: [.macOS(.v14)]`).
- Deleting is always `FileManager.trashItem`; no code path removes a user's file directly. The only direct removals are of the app's own temporary files.
- The app writes only `explorer.local.toml` and `$GROVE_STATE/explorer-session.json`, never the tracked `explorer.toml`.
- Rows 24 pt; tab strip and path bar 32 pt each; icons 16 pt; Name column capped at 560 pt; pane-width thresholds 640 pt and 430 pt; sidebar rail 48 pt.
- Bundle id `com.projectgrove.explorer`; URL scheme `groveexplorer`; app at `~/Applications/Grove Explorer.app`; signed with the "Grove Code Signing" identity as modules 96/97 do.
- Number and date formatting: sizes pinned to `en_US_POSIX` (decimal point), dates in the user's locale.
- Commits: `area: summary` plus a short body; each ends with `Co-Authored-By: Claude Fable 5.2 <noreply@anthropic.com>`. Branch `grove-explorer`. Never stage `grove-dotfiles/config/grove-keys/keys.toml` (the owner's uncommitted edit). Nothing under `artifacts/` or `.recording/` is ever committed.
- Live machine: never run the GroveKeys or GroveThemes binaries; the GroveExplorer binary may be run only with `--render` until Task 16 installs it; no simulated keys or clicks; no system-setting changes.

## Review Focus

1. **A name that already exists only by case or Unicode form** ("Notes.md" vs "notes.md", "é" composed vs decomposed) on a case-insensitive volume: it is a conflict, and "keep both" must not produce a name that collides again. → Task 9.
2. **Copying a folder into itself or into its own subfolder**, and moving an item onto itself: refused before anything is written, with a sentence. → Task 8.
3. **Symlinks and aliases**: a symlink is copied as a link, not followed; a symlink to a folder is listed as a link, not counted by the size calculator, and a loop never hangs it. → Tasks 2 and 5.
4. **An item that changes between the conflict check and the write** (created by another program meanwhile): the write must not overwrite it silently; it becomes a failed item. → Task 8.
5. **Undo after the world moved on** (the copied file was edited, the Trash was emptied, the volume ejected): the undo is refused with the sentence in the spec, and nothing else is touched. → Task 10.

---

## File structure

```
grove-explorer/
  deps/grove-themes -> ../../grove-themes/app
  app/Package.swift
  app/Sources/GroveExplorerCore/
    Entry.swift            FolderReader.swift     FolderWatcher.swift
    Sorting.swift          Filter.swift           SizeCalculator.swift
    PathBar.swift          Formatting.swift       Browser.swift (Tabs, Panes, state)
    Session.swift          ExplorerConfig.swift   IconKind.swift
    Operation.swift        OperationRunner.swift  Conflict.swift   Undo.swift
    ExplorerURL.swift
  app/Sources/GroveExplorer/
    main.swift  ExplorerApp.swift  AppModel.swift  Render.swift
    WindowView.swift  Sidebar.swift  PaneView.swift  TabStrip.swift  PathBarView.swift
    FileList.swift (NSTableView wrapper)  FileListCells.swift  StatusBar.swift
    Commands.swift (menus and keys)  ConflictPrompt.swift  QuickLook.swift
    DragDrop.swift  Icons.swift (FileGlyph, FolderIcon, system icon cache)
  app/Tests/GroveExplorerCoreTests/  (one file per Core unit, plus Fixtures/)
grove-themes/app/Sources/GroveThemesCore/Toml.swift, TomlWrite.swift   (moved from GroveKeysCore)
grove-themes/app/Sources/GroveUI/ListRoles.swift                       (new roles)
grove-dotfiles/modules/94-explorer-app/module.sh
grove-dotfiles/config/grove-explorer/explorer.toml
grove-dotfiles/tests/modules_explorer_app.bats
docs/manual/09-files.md
```

---

### Task 1: Shared groundwork: the TOML reader moves, list roles, the package skeleton

**Files:**
- Move: `grove-keys/app/Sources/GroveKeysCore/Toml.swift`, `TomlWrite.swift` → `grove-themes/app/Sources/GroveThemesCore/` (and their tests to `grove-themes/app/Tests/GroveThemesCoreTests/`)
- Create: `grove-themes/app/Sources/GroveUI/ListRoles.swift`; `grove-explorer/deps/grove-themes` (symlink); `grove-explorer/app/Package.swift`; `Sources/GroveExplorerCore/Entry.swift` (empty namespace for now); `Sources/GroveExplorer/main.swift`; `Tests/GroveExplorerCoreTests/SmokeTests.swift`
- Modify: every `GroveKeysCore` file that uses the TOML types (add `import GroveThemesCore`); `grove-dotfiles/theme/everforest-*` (six files) and `grove-themes` CLI/`ThemeColors` for the new roles; `grove-dotfiles/tests/theme.bats`

**Interfaces:**
- Produces: `TomlDocument.parse(_:)`, `TomlValue`, `TomlSection`, `TomlError` importable from `GroveThemesCore` (signatures unchanged). Theme roles `list_selected`, `list_selected_inactive`, `list_hover`, `hidden_ink` in every theme file, exposed as `ThemeColors.listSelected`, `.listSelectedInactive`, `.listHover`, `.hiddenInk`. Package products `GroveExplorer` (executable) and `GroveExplorerCore` (library); Core depends on `GroveThemesCore`, the app on `GroveExplorerCore` and `GroveUI`.

- [ ] **Step 1:** Move the two TOML files and their tests; add the imports; `swift test` in `grove-themes/app` and `grove-keys/app` both pass with the same test counts as before (83/27 and 411).
- [ ] **Step 2:** Pick the four role colours per scheme from that scheme's palette only. Rule to satisfy, checked by a new test in `theme.bats` that computes contrast from the files: against `bg0`, luminance distance `list_selected` > `list_selected_inactive` > `list_hover` > 0 in all six schemes; `hidden_ink` at least 3:1 on `bg0`. Dark starting point: `list_selected = bg3`, `list_selected_inactive = bg2`, `list_hover = bg1`; light: pick so the order holds (the mock-ups showed `bg3` hover stronger than `bg2` selection: that is the bug to remove).
- [ ] **Step 3:** Failing test `ListRolesTests.theRolesAreInEveryScheme` in `grove-themes/app/Tests` (loads each theme file, expects the four keys); add the keys, `ThemeColors` fields, the CLI's `list --json` fields; pass.
- [ ] **Step 4:** Create the explorer package (copy `testSettings` from grove-keys' `Package.swift`), a `main.swift` that prints its version and exits, and `SmokeTests.buildsAndLinks`. `cd grove-explorer/app && swift build && swift test` pass.
- [ ] **Step 5:** Run `bats tests/theme.bats tests/templates.bats` (in `grove-dotfiles`, through `zsh -lc`); commit.

### Task 2: Entries and reading a folder

**Files:** Create `Entry.swift`, `FolderReader.swift`; Test `EntryTests.swift`, `FolderReaderTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Entry: Equatable, Hashable, Sendable, Identifiable {
      public var id: URL { url }
      public let url: URL
      public let name: String            // as shown: the file name, extension included
      public let kind: Kind              // .folder, .file, .package, .symlink(toFolder: Bool), .alias, .volume
      public let size: Int64?            // nil for folders and for what can't be read
      public let modified: Date?
      public let isHidden: Bool          // dot-file or the hidden flag
      public let typeDescription: String // "Folder", "PNG Image", "Markdown" (localizedTypeDescription)
  }
  public enum FolderReadError: Error, Equatable { case noPermission, missing, notAFolder, other(String) }
  public struct FolderReader: Sendable {
      public init()
      public func read(_ folder: URL) throws(FolderReadError) -> [Entry]
  }
  ```
- [ ] **Step 1:** Tests against a temp folder built in the test: a file, a folder, a `.app`-suffixed folder with `Contents/Info.plist` (package), a dot-file, a symlink to a file, a symlink to a folder, a broken symlink. Assert kinds, `isHidden`, `size` (nil for folder, bytes for file), names with extensions. `read` of a missing path throws `.missing`; of a file `.notAFolder`; of a folder with mode 000 `.noPermission`.
- [ ] **Step 2:** Implement with `FileManager.contentsOfDirectory(at:includingPropertiesForKeys:options: [])` and one `resourceValues` call per item (keys fetched in bulk). A symlink is never resolved for its size.
- [ ] **Step 3:** Performance test `reads50kEntriesUnderTwoSeconds` (creates 50,000 empty files once per run in a temp folder; limit 2 s for `read`).
- [ ] **Step 4:** Pass; commit.

### Task 3: Sorting, filter, formatting

**Files:** Create `Sorting.swift`, `Filter.swift`, `Formatting.swift`; Test files of the same names + `Fixtures/names.txt`

**Interfaces:**
- Produces:
  ```swift
  public enum SortColumn: String, Codable, Sendable { case name, size, modified, kind }
  public struct SortOrder: Equatable, Codable, Sendable { public var column: SortColumn; public var ascending: Bool
      public static let byName = SortOrder(column: .name, ascending: true) }
  public enum Sorting { public static func sorted(_ entries: [Entry], by: SortOrder, folderSizes: [URL: Int64] = [:]) -> [Entry] }
  public enum Filter {
      public static func matches(_ entries: [Entry], words: String) -> [Entry]      // every word, case- and accent-insensitive, anywhere in the name
      public static func jumpIndex(in entries: [Entry], typed: String) -> Int?       // first name with that prefix, else nil
  }
  public enum Formatting {
      public static func size(_ bytes: Int64) -> String                              // "4 KB", "12.6 MB", "1.84 GB"; decimal units, en_US_POSIX
      public static func date(_ date: Date, now: Date, calendar: Calendar, locale: Locale, short: Bool) -> String
      public static func middleTruncated(_ name: String, to count: Int) -> String    // keeps the extension: "Screenshot 2026…44.png"
  }
  ```
- [ ] **Step 1:** Sorting tests: folders (and only `.folder` and symlinks to folders; packages sort as files) first in both directions; names by `localizedStandardCompare` ("file2" before "file10", case and accents ignored); by size uses `folderSizes` for folders (unknown size last); ties fall back to name ascending. Fixture `names.txt` holds 30 awkward names with the expected order.
- [ ] **Step 2:** Filter tests: "gro key" matches "grove-keys"; "é" matches "e"; empty words returns all; `jumpIndex` "gr" → first "gr…" in the given order, case-insensitive.
- [ ] **Step 3:** Formatting tests with the mock-up's values: 4,096 → "4 KB"; 12,600,000 → "12.6 MB"; 1,840,000,000 → "1.84 GB"; 0 → "Zero KB"; dates with a fixed `now`: same day → "Today at 09:41", previous day → "Yesterday at 18:02", older → "9 Nov 2026 at 02:04" (en_GB locale in the test), `short: true` → "Today 09:41", "9 Nov 2026".
- [ ] **Step 4:** Implement; pass; performance test `sorts50kUnderHalfASecond`; commit.

### Task 4: The browser's state: tabs, panes, history, session

**Files:** Create `Browser.swift`, `Session.swift`, `PathBar.swift`; Tests `BrowserTests.swift`, `SessionTests.swift`, `PathBarTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Tab: Equatable, Codable, Sendable, Identifiable {
      public let id: UUID
      public var folder: URL
      public var sort: SortOrder
      public var back: [URL]; public var forward: [URL]
      public var title: String { get }                                   // the folder's last component; "Home" for the home folder
  }
  public struct Pane: Equatable, Codable, Sendable { public var tabs: [Tab]; public var current: Int }
  public enum Side: Int, Codable, Sendable { case left, right; public var other: Side { get } }
  public struct Browser: Equatable, Codable, Sendable {
      public var panes: [Pane]                                           // 1 or 2
      public var active: Side
      public var showHidden: Bool
      public init(start: URL, twoPanes: Bool, showHidden: Bool)
      public var activeTab: Tab { get }
      public func tab(_ side: Side) -> Tab?
      public mutating func go(to folder: URL)                            // active tab; pushes history, clears forward
      public mutating func goBack() -> Bool; public mutating func goForward() -> Bool
      public mutating func goUp() -> Bool                                // false at a volume's root
      public mutating func newTab(folder: URL? = nil)                    // after the current one, becomes current
      public mutating func closeTab() -> Bool                            // false when it is the pane's last
      public mutating func selectTab(_ index: Int); public mutating func nextTab(); public mutating func previousTab()
      public mutating func togglePanes()                                 // 1→2: the new pane opens on the active tab's folder; 2→1: keeps the active pane
      public mutating func switchPane()                                  // with one pane: opens the second
      public mutating func setSort(_ column: SortColumn)                 // same column reverses
      public mutating func repair(exists: (URL) -> Bool, home: URL)      // a missing folder → nearest existing parent
  }
  public struct Session: Equatable, Codable, Sendable { public var browser: Browser; public var sidebarWidth: Double; public var split: Double; public var sidebarHidden: Bool
      public static func load(from: URL) -> Session?; public func save(to: URL) throws }
  public enum PathBar {
      public struct Part: Equatable, Sendable { public let title: String; public let url: URL }
      public static func parts(of folder: URL, home: URL, volumes: [URL]) -> [Part]   // from Home ("Home") when under it, else from the volume
      public static func resolve(_ typed: String, relativeTo: URL, home: URL) -> URL  // "~", "~/x", "../y", absolute
  }
  ```
- [ ] **Step 1:** Browser tests for each mutation above, including: history after back then `go` drops forward; closing the last tab returns false; `togglePanes` twice returns to an equal single pane; `setSort(.name)` twice → descending; `repair` moves `/a/b/c` to `/a` when only `/a` exists.
- [ ] **Step 2:** Session round-trip test; a file with garbage → `load` returns nil; a file from a future shape (unknown key) still loads.
- [ ] **Step 3:** PathBar tests: `~/Developer/project-grove` → ["Home", "Developer", "project-grove"]; `/Volumes/Backup/x` → ["Backup", "x"]; `/usr/local` → ["Macintosh HD", "usr", "local"] given the root volume's name; `resolve("~/x")`, `resolve("../y", relativeTo: /a/b)` → `/a/y`.
- [ ] **Step 4:** Implement; pass; commit.

### Task 5: Watching folders and calculating sizes

**Files:** Create `FolderWatcher.swift`, `SizeCalculator.swift`; Tests of the same names

**Interfaces:**
- Produces:
  ```swift
  public final class FolderWatcher: @unchecked Sendable {
      public init(folder: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void)   // FSEvents on that folder only (no recursion), coalesced
      public func stop()
  }
  public actor SizeCalculator {
      public init()
      public func size(of folder: URL) async -> Int64?          // cached; nil when cancelled or unreadable
      public func invalidate(_ folder: URL)                     // and its ancestors
      public func cancelAll()
  }
  ```
- [ ] **Step 1:** Watcher tests: create, rename and delete a file in a temp folder each call `onChange` within 1 s; a change in a subfolder does not; after `stop()` nothing is called.
- [ ] **Step 2:** Size tests: a tree with known byte counts; a symlink to a folder inside is not followed (Review Focus 3: a link pointing at its own parent returns and does not hang; test with a 2 s limit); packages are summed as trees; a second call is answered from the cache (the test deletes a file between calls and expects the old number until `invalidate`); `cancelAll` during a walk of 20,000 files returns nil quickly.
- [ ] **Step 3:** Implement (`FileManager.enumerator` with `.totalFileAllocatedSizeKey` falling back to `.fileSizeKey`; check `Task.isCancelled` per item; at most 2 walks at once); performance test `sizes20kFilesUnderThreeSeconds`; pass; commit.

### Task 6: Config and links

**Files:** Create `ExplorerConfig.swift`, `ExplorerURL.swift`, `grove-dotfiles/config/grove-explorer/explorer.toml`; Tests `ExplorerConfigTests.swift`, `ExplorerURLTests.swift`. Modify `grove-dotfiles/config/.gitignore` (allowlist the new folder's `explorer.toml` only) and the spec's §9 example.

The existing TOML reader has no arrays of tables, so favourites are tables in file order, as the Grove menu's rows are. The shipped file:

```toml
[general]
start = "~"
show_hidden = false
two_panes = false

[favourites.applications]
path = "/Applications"

[favourites.home]
path = "~"
title = "Home"

[favourites.developer]
path = "~/Developer"

[favourites.documents]
path = "~/Documents"

[favourites.downloads]
path = "~/Downloads"
```

**Interfaces:**
- Produces:
  ```swift
  public struct Favourite: Equatable, Sendable, Identifiable { public let id: String; public let url: URL; public let title: String }
  public struct ExplorerConfig: Equatable, Sendable {
      public var start: URL; public var showHidden: Bool; public var twoPanes: Bool; public var favourites: [Favourite]
      public var problem: String?                                                // "explorer.toml line 7: …" when a file didn't parse
      public static func load(tracked: String?, local: String?, home: URL, exists: (URL) -> Bool) -> ExplorerConfig
      public static let builtIn: String                                          // the shipped file's text, used when the tracked file is missing or broken
      public static func localText(favourites: [Favourite], home: URL) -> String // what the app writes to explorer.local.toml
  }
  public enum ExplorerURL: Equatable { case open(URL)
      public init?(_ url: URL) }                                                 // groveexplorer://open?path=<percent-encoded>
  ```
- [ ] **Step 1:** Config tests: the shipped file gives five favourites in order with titles "Applications", "Home", "Developer", "Documents", "Downloads"; a favourite whose folder doesn't exist is left out; a local file with any `[favourites.*]` table replaces the whole list; local `[general]` keys override one by one; a broken tracked file → built-in defaults and `problem` naming the line; a broken local file → tracked values and `problem`; `localText` round-trips through `load`; a test asserts the tracked file on disk equals `builtIn`.
- [ ] **Step 2:** URL tests: `groveexplorer://open?path=%2FUsers%2Fx%2FMy%20Docs` → `/Users/x/My Docs`; a relative path, a missing `path`, another host → nil.
- [ ] **Step 3:** Implement; update the spec's example to this shape with a line saying why; pass; commit.

### Task 7: Icons: which icon an entry gets

**Files:** Create `IconKind.swift`; Test `IconKindTests.swift` + `Fixtures/grove-icon-theme.json` (a trimmed copy of the real map with ~20 entries)

**Interfaces:**
- Produces:
  ```swift
  public struct Glyph: Equatable, Sendable { public let character: Character; public let colorHex: String }
  public enum FolderMark: String, Sendable, CaseIterable { case none, home, developer, documents, downloads, applications, desktop }
  public enum IconKind: Equatable, Sendable { case folder(FolderMark), glyph(Glyph), system }
  public struct IconMap: Sendable {
      public init(themeJSON: Data) throws
      public func kind(for entry: Entry, light: Bool, home: URL) -> IconKind
  }
  ```
- [ ] **Step 1:** Tests: a folder → `.folder(.none)`; `~/Developer` → `.folder(.developer)` (and the other five by path); a package, a volume, a `.dmg`, an alias → `.system`; `main.swift` → the Swift glyph with the dark colour, with `light: true` the `_light` twin's colour; `README.md`, `CHANGELOG.md`, `notes.md` → the same Markdown glyph (extension before name); `Makefile` (no extension) → its name's glyph; `x.unknownext` → `.system`; a compound extension `a.tar.gz` tries "tar.gz" then "gz".
- [ ] **Step 2:** Implement: parse `iconDefinitions`, `fileExtensions`, `fileNames`, `languageIds`, and `light.*`; an in-code table maps the extensions VS Code resolves by language id (md → markdown, json, js, ts, py, sh, rb, go, rs, c, h, cpp, html, css, yml/yaml, toml, lua, swift, java, kt, php, sql, xml) to the map's `languageIds` keys.
- [ ] **Step 3:** Pass; commit.

### Task 8: Operations and the runner

**Files:** Create `Operation.swift`, `OperationRunner.swift`; Tests `OperationTests.swift`, `OperationRunnerTests.swift`

**Interfaces:**
- Consumes: `Conflict.Resolution` from Task 9 is passed in as a closure, so this task defines the hook and tests with a stub.
- Produces:
  ```swift
  public enum Operation: Equatable, Sendable {
      case copy(items: [URL], to: URL), move(items: [URL], to: URL), duplicate(items: [URL])
      case rename(item: URL, to: String), newFolder(in: URL, name: String), trash(items: [URL])
      public var words: String { get }                           // "Copying 1,204 items to Downloads", "Moving notes.md to Documents"
  }
  public enum OperationRefusal: Error, Equatable { case intoItself(URL), ontoItself(URL), badName(String, reason: String), nothingToDo }
  public struct Progress: Equatable, Sendable { public var done: Int64; public var total: Int64; public var itemsDone: Int; public var itemsTotal: Int }
  public struct ItemFailure: Equatable, Sendable { public let url: URL; public let reason: String }
  public struct Outcome: Equatable, Sendable {
      public var changes: [Change]                               // what was really done, for Undo
      public var failures: [ItemFailure]; public var cancelled: Bool
      public var summary: String                                 // "Moved 3 items to Downloads", "Copied 12 of 40 items (cancelled)"
  }
  public enum Change: Equatable, Sendable { case created(URL), moved(from: URL, to: URL), trashed(original: URL, inTrash: URL), replaced(original: URL, inTrash: URL) }
  public actor OperationRunner {
      public init(fileManager: FileManager = .default)
      public func validate(_ operation: Operation) throws(OperationRefusal)
      public func existingNames(for operation: Operation) -> [URL]             // targets that already exist, compared as the volume compares names
      public func run(_ operation: Operation, resolve: @Sendable (URL) -> Conflict.Choice, progress: @Sendable (Progress) -> Void) async -> Outcome
      public func cancel()
  }
  ```
- [ ] **Step 1:** Tests on temp folders for every case: copy file and tree (dates, permissions, an extended attribute and a Finder tag survive); move within a volume is one rename; duplicate names "name copy.ext", then "name copy 2.ext"; rename; new folder; trash returns the Trash URL.
- [ ] **Step 2:** Refusals (Review Focus 2): `copy([/a], to: /a/b)` → `.intoItself`; `move([/a/x], to: /a)` → `.ontoItself`; rename to "", to "a/b", to "." → `.badName` with a reason sentence.
- [ ] **Step 3:** Safety tests: a copy is written as `.<name>.grove-partial-<uuid>` beside the target and renamed at the end, so `cancel()` mid-tree and a failure mid-file leave no partial item under the final name; one unreadable source among five → four copied, one `ItemFailure`, the run continues; Review Focus 4: a file created at the target after `existingNames` and before the write is not overwritten (the final rename uses a no-replace rename, `renamex_np` with `RENAME_EXCL`) and becomes an `ItemFailure` "an item with that name appeared"; a symlink is copied as a link (Review Focus 3).
- [ ] **Step 4:** Cross-volume test with two disk images made by `hdiutil create -size 20m -fs APFS` and attached in the test's setup (detached in teardown; the test is skipped with a message if `hdiutil` fails): a move across them copies then trashes nothing of the source until the copy is whole, and the source is removed only then; a full target volume stops with what was copied left in place and `summary` naming the missing space.
- [ ] **Step 5:** Progress: bytes for copy (reported at most 10 times a second), items otherwise. Implement; pass; commit.

### Task 9: Conflicts

**Files:** Create `Conflict.swift`; Test `ConflictTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public enum Conflict {
      public enum Choice: Equatable, Sendable { case replace, keepBoth, skip }
      public struct Question: Equatable, Sendable { public let incoming: URL; public let existing: URL; public let remaining: Int
          public let incomingSize: Int64?; public let incomingDate: Date?; public let existingSize: Int64?; public let existingDate: Date? }
      public static func freeName(for name: String, taken: (String) -> Bool) -> String     // "notes.md" → "notes 2.md", "notes 3.md"; "archive.tar.gz" → "archive 2.tar.gz"; a folder "docs" → "docs 2"
      public static func sameName(_ a: String, _ b: String, caseSensitive: Bool) -> Bool   // precomposed/decomposed forms are equal; case by the volume
  }
  public struct ConflictPlan: Equatable, Sendable {                                         // what the prompt's answers add up to
      public mutating func answer(_ choice: Conflict.Choice, for existing: URL, applyToAll: Bool)
      public func choice(for existing: URL) -> Conflict.Choice?
  }
  ```
- [ ] **Step 1:** Tests: `freeName` skips taken numbers; never returns a name for which `taken` is true; Review Focus 1: `sameName("Notes.md", "notes.md", caseSensitive: false)` is true, `"é"` composed equals decomposed, and `freeName` with a `taken` that compares that way doesn't collide; `ConflictPlan` with `applyToAll` answers every later question.
- [ ] **Step 2:** Runner integration tests (extends `OperationRunnerTests`): replace → the old item is in the Trash and the `Change` is `.replaced`; keep both → both exist; skip → untouched and not in `changes`; replacing a folder replaces it whole.
- [ ] **Step 3:** Implement; pass; commit.

### Task 10: Undo

**Files:** Create `Undo.swift`; Test `UndoTests.swift`

**Interfaces:**
- Consumes: `Outcome.changes`, `OperationRunner`.
- Produces:
  ```swift
  public struct UndoRefusal: Error, Equatable { public let sentence: String }      // "Can't undo: notes.md has changed"
  public actor UndoStack {
      public init(runner: OperationRunner)
      public func record(_ outcome: Outcome, words: String)
      public var canUndo: Bool { get }; public var canRedo: Bool { get }
      public func undo() async throws(UndoRefusal) -> String                        // returns the sentence for the status bar: "Undid: moved 3 items to Downloads"
      public func redo() async throws(UndoRefusal) -> String
  }
  ```
  Inverses: `.created(u)` → trash `u`; `.moved(from, to)` → move back; `.trashed(original, inTrash)` → move `inTrash` back to `original`; `.replaced(original, inTrash)` → trash the newcomer at `original`, then put `inTrash` back. A new folder is undone only while it is empty.
- [ ] **Step 1:** Tests: each operation of Task 8 followed by `undo` restores the temp folder's listing and contents exactly; `redo` re-applies it; a new operation clears redo.
- [ ] **Step 2:** Review Focus 5 tests: after a copy, the copy is modified (different size or date) → `undo` throws with "Can't undo: <name> has changed" and the folder is untouched; after a trash, the trashed file is removed from the Trash folder → refused; after a move, something now occupies the original place → refused; a partly cancelled operation undoes only what it did.
- [ ] **Step 3:** Implement (each recorded change keeps the size and date it left, compared before undoing); pass; commit.

### Task 11: The window, read-only: one pane with the list

**Files:** Create `ExplorerApp.swift`, `AppModel.swift`, `WindowView.swift`, `PaneView.swift`, `FileList.swift`, `FileListCells.swift`, `StatusBar.swift`, `Icons.swift`, `Render.swift`; Modify `main.swift`. The app copies the icon font and map from `grove-dotfiles/config/vscode/grove-icons/` as package resources (`resources: [.copy("Resources")]`, the two files copied into `Sources/GroveExplorer/Resources/` by the module in Task 16 and by a `make-resources.sh` beside `Package.swift` for development; the folder is git-ignored).

**Interfaces:**
- Consumes: Tasks 2–7.
- Produces: `AppModel` (`@MainActor final class AppModel: ObservableObject`): `browser: Browser`, `entries(for: Side) -> [Entry]` (sorted and filtered), `selection(for:) -> Set<URL>`, `sizes: [URL: Int64]`, `status(for:) -> StatusText`, `config: ExplorerConfig`; methods `open(_:)`, `select(_:in:)`, and one method per command added in later tasks. `FileList` is `NSViewRepresentable` over `NSTableView` (view-based, row height 24, no system header: the header row is Grove-drawn above it) with a coordinator as data source and delegate. `main.swift` handles `--render <state> <out.png> [scheme]` before starting the app (activation policy `.prohibited`, no window shown, exits): states `two-panes`, `one-pane`, `half-width`, each drawn from fixed sample data matching the mock-ups.
- [ ] **Step 1:** `AppModel` stays thin: whatever can be pure goes in Core. Add `StatusText.swift` to Core (`public enum StatusText { public static func items(total: Int, selected: Int, selectedBytes: Int64?, filteredFrom: Int?) -> String }`) with `StatusTextTests`: "212 items", "1 item", "3 of 212 selected · 48.2 MB", "4 of 212" (filter).
- [ ] **Step 2:** Build the window: `GroveWindowHeader`, a single pane, the header row (Name with the sort arrow, Size, Date Modified, Kind; click to sort), the table with icon + name / size / date / kind cells, selection drawn with `listSelected`, hover with `listHover`, contiguous selected rows as one shape, hidden items in `hiddenInk`, folder sizes as "···" until known, the status bar. Column rule by pane width (640, 430) and the Name cap (560).
- [ ] **Step 3:** `Icons.swift`: register the font for the process (`CTFontManagerRegisterFontsForURL`, scope `.process`); `FileGlyph` (1.25× the cell's font size, nudged to centre, as the mock found); `FolderIcon` shape with the six marks; system icons through `NSWorkspace.shared.icon(forFile:)` cached by path or extension.
- [ ] **Step 4:** Render `one-pane` in dark-medium and light-medium, open the PNGs, compare with `overview-one-pane-*.png`, fix until they match in layout, sizes and colours. The folder marks: accept each only when it reads at 16 pt in the render (spec §10); simplify a mark that doesn't.
- [ ] **Step 5:** Commit.

### Task 12: Navigation, path bar, tabs, sidebar, the second pane, the session

**Files:** Create `TabStrip.swift`, `PathBarView.swift`, `Sidebar.swift`, `Commands.swift`; Modify `WindowView.swift`, `PaneView.swift`, `AppModel.swift`, `ExplorerApp.swift`

**Interfaces:**
- Consumes: `Browser`, `Session`, `PathBar`, `ExplorerConfig`, `FolderWatcher`, `ExplorerURL`.
- Produces: Core `CommandList.swift`: `public struct CommandInfo: Equatable, Sendable { public let id: String; public let title: String; public let key: String?; public let modifiers: Set<Modifier>; public let menu: String }` (`Modifier`: command, option, shift, control) and `public enum CommandList { public static let all: [CommandInfo] }`, every command of spec §7, grouped by the menu-bar menu it sits in (File, Edit, View, Go). The app's `Commands.swift` pairs each id with `run: @MainActor (AppModel) -> Void` and `isEnabled: @MainActor (AppModel) -> Bool`; the menu bar menus, the key handler and (Task 14) the context menu are all built from it.
- [ ] **Step 1:** Wire every navigation and tab key of spec §7 (both tables, the rows that don't change files) through `Commands`; Tab switches pane; ⌘\ toggles panes; type-to-jump with a 1 s reset.
- [ ] **Step 2:** Tab strip (pill for the current tab, hover close at the left in reserved space, "+"), path bar (parts as buttons; ⌘L / ⌘⇧G → a field with the 1 pt green line; a missing path marks it red), the green line for the active pane, `listSelectedInactive` in the other.
- [ ] **Step 3:** Sidebar: sections from the config, iCloud Drive when `~/Library/Mobile Documents/com~apple~CloudDocs` exists, volumes from `FileManager.mountedVolumeURLs` kept live by `NSWorkspace` mount/unmount notifications, eject (`NSWorkspace.unmountAndEjectDevice`, spinner, failure line), Trash row (`NSWorkspace.shared.open` on the Trash); the lit row is the nearest favourite above the active folder; rail mode at the 430 pt rule; ⌘⌥S.
- [ ] **Step 4:** Live folders (`FolderWatcher` per shown folder, selection and scroll kept across a refresh), the empty and "needs permission" states (button opens `x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders`), a folder that vanished → `repair`.
- [ ] **Step 5:** Session saved on change (debounced 1 s) and at quit, loaded at launch; `groveexplorer://open?path=` handled in `application(_:open:)`; divider drag and double-click.
- [ ] **Step 6:** Renders `two-panes` and `half-width` in both schemes compared with the mock-ups; commit.

### Task 13: File commands: the operations in the window

**Files:** Create `ConflictPrompt.swift`; Modify `AppModel.swift`, `Commands.swift`, `StatusBar.swift`, `FileListCells.swift`

**Interfaces:**
- Consumes: Tasks 8–10.
- [ ] **Step 1:** Commands: ⌘C (file URLs to the general pasteboard), ⌘V copy here, ⌥⌘V move here, ⌘D, ⌘⌫, ⌘⇧N (new folder then inline rename), Return (inline rename: name without extension selected, 1 pt green line, red with the reason for a bad or taken name), F5, F6, ⌘Z, ⌘⇧Z, ⌘⌥C (paths), ⌘⌥T (`open -a Ghostty <folder>`), ⌘I (Finder's Get Info: `NSAppleScript`, `tell application "Finder" to open information window of (POSIX file "…" as alias)` per selected item; macOS asks once for permission to control Finder; refused, the status bar says "Allow Grove Explorer to control Finder in Privacy Settings to use Get Info").
- [ ] **Step 2:** The run loop: `validate` (a refusal is a status-bar sentence in the marked style) → `existingNames` → the conflict prompt when any (card over the scrim per the spec: opaque fill, radius 10, 1 pt line; sizes and dates of both; Skip, Replace, Keep Both as the default button; "Apply to all (N more)"; Cancel; Return and Escape work) → `run` with progress in the target pane's status bar and a cancel button → `UndoStack.record` → the summary line with "⌘Z to undo" for 5 s; failures as "3 items could not be copied" with a click listing them.
- [ ] **Step 3:** Render states `copying`, `conflict`, `undo-line`, `rename` and compare with `operations-*.png` and `list-states-*.png`; commit.

### Task 14: Drag and drop, Quick Look, the context menu, the filter

**Files:** Create `DragDrop.swift`, `QuickLook.swift`; Modify `FileList.swift`, `Sidebar.swift`, `Commands.swift`, `PaneView.swift`

- [ ] **Step 1:** Drag source and drop target on the table (`NSPasteboard` file URLs; `NSFilePromiseProvider` is not needed for local files): drop on a folder row (hover fill + 1 pt green line) or on empty space; move on the same volume, copy across; ⌥ copies, ⌘ moves; drops on sidebar rows and on tabs; drops from other apps; all through Task 13's run loop.
- [ ] **Step 2:** Quick Look: Space toggles `QLPreviewPanel` for the selection; arrows move the selection while it is up; the panel's source frame is the row's icon.
- [ ] **Step 3:** Context menu (`NSMenu` from `Commands`, per spec §7, with Open With ▸ from `NSWorkspace.urlsForApplications(toOpen:)`), and the empty-space menu.
- [ ] **Step 4:** ⌘F: `FilterField` above the list, `Filter.matches`, "4 of 212", Escape clears and returns focus.
- [ ] **Step 5:** Render `filter` and `states` sheets' states (empty, no permission) and compare; commit.

### Task 15: Accessibility and the whole-keyboard pass

- [ ] **Step 1:** Every custom control has a label; the current tab, the active pane and selected rows carry `.isSelected`; the table exposes rows with name, kind and size.
- [ ] **Step 2:** `.keyboardFocusRing()` on the window root. Tab only moves between the two lists (it is "the other pane"). ⌥⌘← puts the keyboard in the sidebar (↑/↓ move, Return opens the place and returns to the list, → or Escape returns without opening); add this row to `CommandList`, the spec's §7 and the manual.
- [ ] **Step 3:** `CommandListTests` (Core): every row of spec §7's two tables is in `CommandList.all` with that key, no key is bound twice, and every id in `CommandList.all` has an action in the app's `Commands` (a debug assertion at launch covers the last, since the app target has no tests). Commit.

### Task 16: The module, the Grove menu row, the manual

**Files:** Create `grove-dotfiles/modules/94-explorer-app/module.sh`, `grove-dotfiles/tests/modules_explorer_app.bats`, `docs/manual/09-files.md`; Modify `grove-dotfiles/config/grove/menu.toml`, `docs/manual/README.md`, the top `README.md`, `grove-keys/app/Tests/GroveKeysCoreTests/Fixtures/menu.toml`

- [ ] **Step 1:** bats first, modelled on `modules_themes_app.bats` with the same fakes (`GROVE_SWIFT`, `GROVE_CODESIGN`, `GROVE_APPS_DIR`): check fails when the app is missing or its stamp differs from the source hash; apply builds release, assembles the bundle (Info.plist: bundle id, name, `CFBundleURLTypes` with `groveexplorer`, usage strings `NSDesktopFolderUsageDescription`, `NSDocumentsFolderUsageDescription`, `NSDownloadsFolderUsageDescription`, `NSRemovableVolumesUsageDescription`, `NSNetworkVolumesUsageDescription`, `NSAppleEventsUsageDescription`; no `LSUIElement`), copies `seti.woff` and `grove-icon-theme.json` into the bundle's resources, signs, writes the stamp; a running app is not killed (the module prints "reopen Grove Explorer"); the config folder is linked.
- [ ] **Step 2:** Write `module.sh` as `97-themes-app/module.sh` without the LaunchAgent parts; pass.
- [ ] **Step 3:** Grove menu: a top-level row `[files]`, title "Files", `run = "open -a 'Grove Explorer'"`, `icon = "folder"` (add the `folder` case to `GroveIcon.Name` and its test list); placed after Appearance; update the fixture copy; `GroveKeys --check-menu` passes.
- [ ] **Step 4:** Manual chapter 9, "Files": opening it, the window, the keys (both tables), copying between panes, undo, the config file, what stays in Finder; link it from the contents and the READMEs.
- [ ] **Step 5:** Full checks: `swift test` in all three packages; `zsh -lc 'bats tests/'` in `grove-dotfiles` (about 12 minutes; never mixed with grove-themes' bats files); commit.
- [ ] **Step 6:** Install (`zsh -lc 'grove --yes install 94-explorer-app 96-keys-app'`), open the app, and hand the owner the by-hand checklist: every key of §7, drag and drop with Finder and another app, Quick Look, the five permission prompts, ejecting a disk, a scheme switch while open, tiling beside another window, a 50,000-item folder, a multi-GB copy with cancel and undo.
