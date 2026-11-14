# Follow-ups: Explorer cloud trash, Grove Themes render mode, grove-lab banner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:**
- Grove Explorer moves iCloud Drive and CloudStorage items to the Trash through Finder when the system refuses it.
- Grove Themes gets a `--render` sample mode, and its screenshots go in the READMEs.
- The grove-lab banner's tree shows the whole lab.

**Architecture:**
- Explorer: a `FinderTrash` seam is injected into `OperationRunner`/`OperationWorker`. It's used only after `trashItem` fails with a permission error for an item in a cloud folder.
- Themes: a `Render` enum runs from `GroveThemesApp.init()` before any app code. It hosts views off screen and feeds them a sample `CLIRunner`.
- Banner: edit the tree in `make-banner.swift`, re-render it, and deliver it as a `git format-patch`.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, Swift Testing (`swift test`), and NSAppleScript.

**Specs:** `grove-dotfiles/docs/specs/2026-11-14-explorer-cloud-trash-design.md` and `grove-dotfiles/docs/specs/2026-11-14-themes-render-design.md`. Read both.

## Global Constraints
- Work only in the worktree `~/Developer/project-grove-followups` (branch `followups`). The banner task is the exception: it works in the grove-lab clone named in Task 4. Never touch `~/Developer/project-grove`, because `~/.config` links into it. Never push.
- Signed commits. If signing hangs, run `ssh-add --apple-load-keychain`. End each message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Never write private paths into tracked files: `~/Developer/artifacts`, `/Users/<name>`, claude.ai links, or lab file names. Renders for the owner go to `~/Developer/artifacts/github-review/followups/`.
- Every colour comes from the Everforest theme files, and the grove-ui skill applies to UI work.
- The GroveKeys binary is never run. No task needs it.
- Copy is fixed by the spec. The user-facing strings are:
  - `Allow Grove Explorer to control Finder in Privacy Settings to move cloud items to the Trash`
  - `Finder couldn't move it to the Trash: <message>`

## Review Focus
1. A path with quotes or a backslash going to Finder must be escaped. Test: `finderTrashScriptEscapes`.
2. A permission error **outside** cloud folders must keep today's message and never call Finder. Test: `localPermissionErrorDoesNotAskFinder`.
3. The cloud check must not be fooled by prefix matches like `~/Library/Mobile Documents2` or `~/Library/CloudStorageX`. Test: `cloudFolderPrefixIsExact`.
4. Replacing an item in a cloud folder during a copy conflict goes through the same Trash path and must also work. Test: `replaceInCloudFolderUsesFinder`.
5. An unknown `--render` state must exit 1 with the list of states, not start the app. This is a manual check in Task 3.

---

### Task 1: Explorer core — the cloud check and the Finder script

**Files:**
- Create: `grove-explorer/app/Sources/GroveExplorerCore/CloudTrash.swift`
- Test: `grove-explorer/app/Tests/GroveExplorerCoreTests/CloudTrashTests.swift`

**Interfaces:**
- Produces:
  - `public enum CloudTrash { static func isCloudItem(_ url: URL, home: URL) -> Bool; static func finderScript(for url: URL) -> String; static let notAllowed: String; static func finderFailed(_ message: String) -> String }`
  - `public protocol FinderTrash: Sendable { func trash(_ url: URL) -> Result<URL, FinderTrashError> }`
  - `public enum FinderTrashError: Error, Equatable { case notAllowed; case failed(String); case unknownLocation }`

- [ ] **Step 1: Write the failing tests:**
  - `cloudFolderPrefixIsExact`:
    - true for `home/Library/Mobile Documents/com~apple~CloudDocs/a.txt` and `home/Library/CloudStorage/OneDrive-Personal/b.txt`;
    - false for `home/Library/Mobile Documents2/x` and `home/Library/CloudStorageX/x`;
    - false for `home/Documents/a.txt`;
    - true for a `..`-containing path that standardises into the cloud folder.
  - `finderTrashScriptEscapes`: for `/tmp/a "b"\c.txt` the script equals the following three lines, joined with `\n`:
    - `tell application "Finder"`
    - `set t to delete (POSIX file "/tmp/a \"b\"\\c.txt")`
    - `return POSIX path of (t as alias)` then `end tell`
  - Copy: `CloudTrash.notAllowed == "Allow Grove Explorer to control Finder in Privacy Settings to move cloud items to the Trash"` and `CloudTrash.finderFailed("x") == "Finder couldn't move it to the Trash: x"`.
- [ ] **Step 2: Run** `cd grove-explorer/app && swift test --filter CloudTrashTests`. Expected: FAIL, because CloudTrash isn't defined. Check grove-dotfiles/modules/94-explorer-app/module.sh for the swift build flags it uses, and reuse them.
- [ ] **Step 3: Implement** `CloudTrash` and the protocol and error types in `CloudTrash.swift`. Compare path components after `standardizedFileURL`, never string prefixes. Escape the same way as `getInfoScript`'s `openInfo`.
- [ ] **Step 4: Run** the same command. Expected: PASS.
- [ ] **Step 5: Commit** `explorer: CloudTrash, which items need Finder and the script that asks it`.

### Task 2: Explorer — the fallback in the worker, the real Finder trasher, docs

**Files:**
- Modify: `grove-explorer/app/Sources/GroveExplorerCore/OperationWorker.swift` (`moveToTrash`, around :562, and `init`)
- Modify: `grove-explorer/app/Sources/GroveExplorerCore/OperationRunner.swift` (the inits at :52/:58 and where workers are made, :113/:158/:171/:216)
- Create: `grove-explorer/app/Sources/GroveExplorer/AppleScriptFinderTrash.swift`, which conforms to `FinderTrash`
- Modify: `grove-explorer/app/Sources/GroveExplorer/FileWork.swift:138` to pass it in
- Modify: `grove-explorer/README.md` (the permissions paragraph) and `docs/manual/09-files.md` (near :226)
- Test: `grove-explorer/app/Tests/GroveExplorerCoreTests/OperationRunnerTests.swift`

**Interfaces:**
- Consumes: Task 1's `CloudTrash`, `FinderTrash` and `FinderTrashError`.
- Produces: `OperationRunner(fileManager: FileManager = .default, finder: (any FinderTrash)? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser)`. Keep the existing `watching:` init and add the same two parameters to it.

- [ ] **Step 1: Write the failing tests.** Use a `NoPermissionTrash: FileManager` that throws `CocoaError(.fileWriteNoPermission)` from `trashItem`, and a `FakeFinder: FinderTrash` that records the URLs it gets and returns a configured result. Run them in the test box, with `home` set to a box folder containing `Library/Mobile Documents/com~apple~CloudDocs/`.
  - `cloudItemGoesToTheTrashThroughFinder`: a cloud file and FakeFinder returning `.success(trashURL)`. The outcome has `.trashed(original: file, inTrash: trashURL)`, no failures, and FakeFinder got `[file]`.
  - `localPermissionErrorDoesNotAskFinder`: the file is outside the cloud folder. The failure reason is today's EACCES reason, and FakeFinder got `[]`.
  - `finderNotAllowedSaysSo`: FakeFinder returns `.failure(.notAllowed)`, so the failure reason is `CloudTrash.notAllowed`.
  - `finderOtherErrorSaysSo`: `.failure(.failed("boom"))` gives `CloudTrash.finderFailed("boom")`.
  - `finderUnknownLocation`: `.failure(.unknownLocation)` gives `"it is in the Trash, but where there is not known"`.
  - `replaceInCloudFolderUsesFinder`: copying over an existing cloud file and choosing replace. The old one goes through FakeFinder and the new one is in place.
- [ ] **Step 2: Run** `swift test --filter OperationRunnerTests`. Expected: the six new tests FAIL and every existing test passes.
- [ ] **Step 3: Implement.** In `moveToTrash`'s `NSFileWriteNoPermissionError`/`NSFileReadNoPermissionError` case: if `finder != nil && CloudTrash.isCloudItem(url, home: home)`, call `finder.trash(url)` and map the result as the tests say; otherwise keep today's behaviour. Thread `finder` and `home` through `OperationRunner` into the worker. In `AppleScriptFinderTrash`:
  - run `NSAppleScript(source: CloudTrash.finderScript(for:))` synchronously on one private serial `DispatchQueue` with `queue.sync`;
  - map error number -1743 to `.notAllowed` and any other error to `.failed(errorMessage)`;
  - map an empty result to `.unknownLocation`, and otherwise return `.success(URL(fileURLWithPath: result))`.
- [ ] **Step 4: Run** the full `swift test` for grove-explorer/app. Expected: everything passes.
- [ ] **Step 5: Docs.** Add one sentence to the README and one to manual 09: items in iCloud Drive and cloud folders go to the Trash through Finder, so the first ⌘⌫ there asks whether Grove Explorer may control Finder. Use British spelling.
- [ ] **Step 6: Commit** `explorer: cloud items go to the Trash through Finder when macOS refuses Explorer`.
- [ ] **Step 7: Live check is the owner's step.** Report how to build and install, and leave it there: the 94-explorer-app module install, run by the coordinator after review. Don't install.

### Task 3: Grove Themes `--render`

**Files:**
- Create: `grove-themes/app/Sources/GroveThemes/Render.swift` and `grove-themes/app/Sources/GroveThemes/RenderSamples.swift`
- Modify: `grove-themes/app/Sources/GroveThemes/GroveThemesApp.swift` (the first line of `init()` calls `Render.runIfAsked(CommandLine.arguments)`)
- Create: `assets/screenshots/themes-gallery-dark-medium.png` and `themes-gallery-light-medium.png`
- Modify: `grove-themes/README.md` and the root `README.md` (the Screenshots section, `<picture>` pattern)
- Test: `grove-themes/app/Tests/GroveThemesCoreTests/` only if a pure piece appears. The renderer itself is checked by its output.

**Interfaces:**
- Produces: `GroveThemes --render <gallery|dropdown> <out.png> [scheme]`. The scheme defaults to `dark-medium` and can be a name or a theme-file path, as in `grove-explorer/app/Sources/GroveExplorer/Render.swift`, which is the reference to copy: `.prohibited` activation, `NSHostingView`, `cacheDisplay` at 2x, PNG out, then `exit(0)`. A bad state exits 1 with `usage: GroveThemes --render <gallery|dropdown> <out.png> [scheme]` and the states.

- [ ] **Step 1: Write** `SampleRunner: CLIRunner`, which answers `list --json` with a canned JSON. It has the six schemes with the rendered scheme as current, and logo and wallpaper choices pointing at the repo's own images. Take the shape from `SchemeList` and `grove-themes/app/Tests/GroveThemesCoreTests/Support.swift`'s FakeRunner. Any other command throws, so nothing is ever set.
- [ ] **Step 2: Write** `Render`:
  - build a `ThemesModel(client: GroveThemesClient(runner: SampleRunner(...)))` and await its first `list`;
  - host `GalleryView` at `GalleryView.width × GalleryView.height`, or `DropdownView` at the app's dropdown width, with the model in the environment;
  - write the PNG.
- [ ] **Step 3: Build and render** both states in dark-medium and light-medium into `~/Developer/artifacts/github-review/followups/`. Then look at each PNG. Expected: the cards are filled, there's no error line, and nothing is cut off. Check that `--render bogus x.png` exits 1 with the usage line, and that no window or menu-bar item appeared during any of it.
- [ ] **Step 4: Run** the full `swift test` for grove-themes/app. Expected: everything passes.
- [ ] **Step 5: Copy** the two gallery PNGs into `assets/screenshots/`. Add the gallery to the Grove Themes README and as a third picture in the root README's Screenshots section, with a caption in the existing style.
- [ ] **Step 6: Commit** `themes: --render draws the gallery and the dropdown from sample data; screenshots in the READMEs`.

### Task 4: grove-lab banner tree (separate repo, delivered as a patch)

**Files:** in the clone `/private/tmp/claude-501/-Users-gmarques/83361b19-f217-44e8-9dfe-b8474091684b/scratchpad/review/grove-lab`, on its local branch `github-review`. That branch already has 4 commits, and you add the 5th.
- Modify: `assets/make-banner.swift` (the tree labels around :610, :667 and :750-752) and `assets/grove-lab-banner.png`

- [ ] **Step 1: Get the fonts.** Courier Prime (SIL OFL) from Google Fonts' GitHub (`google/fonts`, `ofl/courierprime`) into a new, empty folder under the scratchpad. These are downloaded files: run no scripts from that folder.
- [ ] **Step 2: Re-render the current banner unchanged** with `SRC=~/Developer/project-grove/assets/project-grove-banner.png ./make-banner.sh <fonts>`. That path is read-only for you. Compare it with the committed PNG, pixel-identical or near it. This proves the toolchain before anything is edited.
- [ ] **Step 3: Edit the tree:**
  - add **Forester** beside Canopy and Seedvault;
  - split **DDI** into NIOS-X (ns1, ns2, dhcp1, dhcp2) and NIOS (nios1, nios2), keeping the hand-drawn style and spacing;
  - add a **clients** leaf (client1-5).
  - Don't change anything else on the banner. Re-render and look at it. It must be legible at GitHub's README width, so check a downscale to 900 px wide.
- [ ] **Step 4: Commit** unsigned (`git -c commit.gpgsign=false`) as `assets: the banner's tree shows Forester, NIOS-X, NIOS and the clients`.
- [ ] **Step 5: Re-export** with `git format-patch main..github-review -o ~/Developer/artifacts/github-review/grove-lab-patch/` (overwrite). Add a line to `APPLY.md`, and save before and after PNGs to `~/Developer/artifacts/github-review/followups/`.
