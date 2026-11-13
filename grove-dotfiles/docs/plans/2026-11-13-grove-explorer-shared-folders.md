# Grove Explorer Shared Folders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Saved SMB shares in a SHARED sidebar section: Connect to Server… adds one, a click mounts it through NetFS and opens it, and it stays after unmount and restart.

**Architecture:** Core holds everything decidable without the network: the address parser, the `[servers.<id>]` tables in `explorer.local.toml`, matching a mounted volume to a saved share, a row's state, and error code → sentence. The app adds a `Mounter` around `NetFSMountURLAsync`/`NetFSMountURLCancel`, a `.shared` sidebar section with a URL-less place kind, the connect sheet, ⌘K and the context-menu items.

**Tech Stack:** Swift 6, SwiftUI + AppKit, NetFS.framework, Swift Testing, Command Line Tools only (no `@State` macro).

**Spec:** grove-dotfiles/docs/specs/2026-11-13-grove-explorer-shared-folders-design.md (main spec: grove-dotfiles/docs/specs/2026-11-12-grove-explorer-design.md)

## Global Constraints

- Shares are saved only in `~/.config/grove-explorer/explorer.local.toml` as `[servers.<id>]` tables with `url = "smb://grove-lab/media"` and `order = N`; `<id>` = slug of host and share (`grove-lab-media`, `-2` on a clash). Never written to the tracked `explorer.toml`; no hostname in any tracked file.
- Accepted schemes `smb://`, `afp://`, `nfs://`; a bare `grove-lab/media` gets `smb://`. An address with a password is refused with exactly: `Leave the password out — macOS will ask for it`. A user name is kept.
- Sentences: `<host> didn't answer`, `The password was refused`, `There is no share called <share> on <host>`, `Couldn't connect to <host> (error N)`. Cancelling the password sheet is quiet (no sentence).
- No timer of the app's own on a mount; cancelling the spinner calls `NetFSMountURLCancel`.
- Connect mounts first and saves only on success. "Remove from Sidebar" forgets without ejecting.
- A saved share's mount is listed only in SHARED, not again in LOCATIONS. SHARED is shown when at least one share is saved.
- ⌘K and File ▸ Connect to Server… open the sheet; ⌘K is added to main spec §7's table (a Core test parses §7 against `CommandList`).
- Nothing about a password in logs, files, the status line or VoiceOver.
- grove-ui skill (`~/.claude/skills/grove-ui/SKILL.md`): GroveIcon/SF Symbols (`server.rack` for a share row), theme roles only, JetBrains Mono.
- The GroveExplorer binary runs only with `--render`, `--time-list`, `--audit-accessibility`; never launch, quit or kill the installed app; never install. Never commit `artifacts/`; never touch `grove-dotfiles/config/grove-keys/keys.toml`, `config/ssh/config`, `config/grove/local.env`.
- Commits: `area: summary` + body + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, by explicit path.

## Review Focus

1. A local file with favourites and comments must keep them byte-for-byte when a share is saved or removed, and a file the config can't read is never written over (Task 1 `savingAShareKeepsFavouritesAndComments`, `unreadableLocalFileIsNotWrittenOver`).
2. The same share saved twice (typed again, or "Keep in Sidebar" on a share already saved) must not make a second row (Task 1 `savingTheSameShareTwiceKeepsOne`: same normalised URL, case-insensitive host).
3. A saved share whose volume is mounted under another name (`/Volumes/media-1` because a folder `media` existed) still matches its row (Task 1 `matchesByRemountURLThenHostAndShare`).
4. The owner clicking a not-connected row twice quickly, or clicking it while the sheet connects the same address, must start one mount, not two (Task 2 step: `Mounter` keeps one request per normalised URL).
5. A share unmounted while a pane is inside it: the pane follows the existing gone-volume rule (main spec §13, tabs move to Home) and the row turns not connected without a notice (Task 2 step: the row's state is recomputed on `didUnmountNotification`).

---

### Task 1: Shared shares in Core

**Files:**
- Create: `grove-explorer/app/Sources/GroveExplorerCore/SharedServer.swift`
- Modify: `grove-explorer/app/Sources/GroveExplorerCore/ExplorerConfig.swift` (read `[servers.<id>]` in `Layer`; local writer keeps both favourites and servers)
- Test: `grove-explorer/app/Tests/GroveExplorerCoreTests/SharedServerTests.swift`, `ExplorerConfigTests.swift`

**Interfaces:**
- Produces:
  - `public struct SharedServer: Equatable, Sendable, Identifiable { public let id: String; public let url: URL; public var name: String { get }; public var host: String { get } }` (`name` = last path part, `host` = URL host, both from `url`).
  - `public enum SharedAddress { public static func parse(_ text: String) -> Result<URL, SharedAddressProblem> }`, `public enum SharedAddressProblem: Error, Equatable { case password, unsupportedScheme(String), empty, noShare }` with `var sentence: String` (`.password` → the exact sentence in Global Constraints; others: `Use an smb://, afp:// or nfs:// address`, `Type the server's address`, `Add the share's name: smb://<host>/share`).
  - `public enum SharedServers { static func id(for url: URL, taken: Set<String>) -> String; static func adding(_ url: URL, to servers: [SharedServer]) -> [SharedServer]; static func removing(id: String, from: [SharedServer]) -> [SharedServer]; static func match(mountedRemountURL: URL?, volumeName: String, among: [SharedServer]) -> SharedServer? }`
  - `public enum SharedRowState: Equatable, Sendable { case notConnected, connecting, connected(URL) }` and `public static func state(saved: SharedServer, mounted: URL?, connecting: Bool) -> SharedRowState` (connecting wins over not connected; mounted wins over connecting).
  - `public enum MountOutcome: Equatable, Sendable { case mounted(URL), quiet, failed(String) }` and `public static func outcome(status: Int32, mountPoint: URL?, server: URL) -> MountOutcome` in `SharedServers`: 0 with a mount point → `.mounted`; `-128` (userCanceledErr) and `89` (ECANCELED) → `.quiet`; `80` (EAUTH) and `13` (EACCES) → password sentence; `2` (ENOENT) → no-share sentence; `60`, `64`, `65`, `51` (ETIMEDOUT, EHOSTDOWN, EHOSTUNREACH, ENETUNREACH) → didn't-answer; anything else → `Couldn't connect to <host> (error N)`. Check these values against the SDK's `NetFS/NetFS.h` and `sys/errno.h`; add any NetFS-specific auth/cancel codes you find there to the same buckets and name them in the test.
  - `ExplorerConfig.servers: [SharedServer]` (from the local file only, sorted by `order`), and `ExplorerConfig.localText(favourites:servers:home:keeping:)` replacing today's `localText(favourites:home:keeping:)` (all callers updated); servers written as `[servers.<id>]` with `url` and `order`, placed where the first `[servers…]` table stood, else at the end.

- [ ] **Step 1: Write the failing tests** in `SharedServerTests.swift`:
  - `parsesTheOwnersShare`: `parse("smb://grove-lab/media")` → `smb://grove-lab/media`; `parse("grove-lab/media")` → the same; `parse(" smb://grove-lab/media/ ")` → the same (trimmed, trailing slash dropped).
  - `keepsAUserRefusesAPassword`: `parse("smb://gm@grove-lab/media")` keeps `gm`; `parse("smb://gm:secret@grove-lab/media")` → `.failure(.password)` and `SharedAddressProblem.password.sentence == "Leave the password out — macOS will ask for it"`.
  - `schemes`: `afp://`, `nfs://` accepted; `http://x/y` → `.unsupportedScheme("http")`; `""` → `.empty`; `smb://grove-lab` → `.noShare`.
  - `nameAndHost`: `SharedServer(url: smb://grove-lab/media)` has `name == "media"`, `host == "grove-lab"`.
  - `idsAreSlugs`: `id(for: smb://grove-lab/media, taken: [])  == "grove-lab-media"`; with `"grove-lab-media"` taken → `"grove-lab-media-2"`.
  - `savingTheSameShareTwiceKeepsOne`: adding `smb://Grove-Lab/media` to a list holding `smb://grove-lab/media` returns the list unchanged.
  - `matchesByRemountURLThenHostAndShare`: a remount URL equal to the saved one matches; nil remount URL with volume name `media` matches `smb://grove-lab/media` only when exactly one saved share is called `media`; `media-1` with a remount URL `smb://grove-lab/media` matches.
  - `rowState`: the three precedence cases.
  - `outcomes`: each status bucket above, with the exact sentences for host `grove-lab` and share `media`.
  In `ExplorerConfigTests.swift`: `serversReadFromLocalOnly` (a `[servers.x]` table in the tracked text is ignored; the local file's are used, sorted by `order`), `savingAShareKeepsFavouritesAndComments` (round trip: local text with favourites and comments, add a server, comments and favourites unchanged, then remove it → the original text), `unreadableLocalFileIsNotWrittenOver` (throws `ConfigWriteRefused`), `badServerTableIsReported` (`url` missing or not a string → the config's problem line names the line).
- [ ] **Step 2: Run:** `cd grove-explorer/app && swift test --filter 'SharedServerTests|ExplorerConfigTests'` — Expected: FAIL (no `SharedServer`).
- [ ] **Step 3: Implement** `SharedServer.swift` and the `ExplorerConfig` changes (normalise for comparison: lowercased scheme and host, path without trailing slash, user kept).
- [ ] **Step 4: Run** the filter, then `swift test` once — Expected: PASS.
- [ ] **Step 5: Commit** by path: `explorer: saved shares, their addresses and states in Core`.

### Task 2: Mounting, the SHARED section, the sheet

**Files:**
- Create: `grove-explorer/app/Sources/GroveExplorer/Mounter.swift`, `ConnectSheet.swift`
- Modify: `Volumes.swift` (`Place.Section.shared`, `Place.Kind.share(SharedServer)`, `Place.url` optional or a share's URL nil-safe — pick one and keep every `place.url` reader correct), `Sidebar.swift`, `KeyboardReach.swift`, `ContextMenu.swift` / the sidebar's context menu, `AppModel.swift`, `Commands.swift` (menu), `GroveExplorerCore/CommandList.swift`, main spec §7 table
- Test: `CommandListTests` (existing §7 parse test covers ⌘K)

**Interfaces:**
- Consumes: Task 1 `SharedServer`, `SharedAddress.parse`, `SharedServers.adding/removing/match/state/outcome`, `MountOutcome`, `ExplorerConfig.servers`, `localText(favourites:servers:home:keeping:)`.
- Produces:
  - `@MainActor final class Mounter { func mount(_ url: URL, completion: @escaping (MountOutcome) -> Void); func cancel(_ url: URL); func isMounting(_ url: URL) -> Bool }` — one request per normalised URL (a second `mount` of the same URL joins the first), `NetFSMountURLAsync(url, nil, nil, nil, nil, nil, &requestID, queue, block)` with default options, result mapped with `SharedServers.outcome` and delivered on the main actor.
  - `AppModel`: `func connect(_ server: SharedServer)`, `func connectNew(_ text: String) async -> String?` (nil on success: saved, sheet closes, opened in the active pane; else the sentence for the sheet), `func removeShare(_ id: String)`, `func keepInSidebar(_ volume: Volume)`, `var showsConnectSheet: Bool`.
  - Command `connectToServer` in `CommandList` on ⌘K, in File ▸ "Connect to Server…".

- [ ] **Step 1: Sidebar.** `places` adds SHARED after the provider sections and before LOCATIONS when `config.servers` is non-empty; volumes matched to a saved share (`SharedServers.match` with `volumeURLForRemountingKey` and the volume name) are left out of LOCATIONS. A share row: title = `name`, quiet host text after it, `server.rack` icon (quiet unless connected), spinner while connecting (clickable: cancels), eject button when connected. Click/Return: connected → open its mount point like any place; not connected → `connect`. Lighting uses the existing deepest-place rule with the mount point.
- [ ] **Step 2: State.** Recompute rows on mount/unmount/rename notifications; an unmount while connected is silent (Review Focus 5); a failed connect puts the sentence in the active pane's notice line; `.quiet` shows nothing.
- [ ] **Step 3: Sheet.** `ConnectSheet`: native `TextField` "Server address", placeholder `smb://grove-lab/share`, Connect / Cancel; parse errors shown under the field before any mount; while connecting, a spinner on Connect and Cancel cancels the mount; a failure sentence shows under the field, the text kept; success closes it.
- [ ] **Step 4: Menus.** Share row context menu: "Remove from Sidebar" (forgets; if mounted, the volume reappears in LOCATIONS); LOCATIONS network volume (one whose `volumeURLForRemountingKey` is non-nil) context menu: "Keep in Sidebar". Header +: `.help("Connect to Server…")`. ⌘K added to `CommandList` and to main spec §7 in the same commit; run `swift test --filter CommandList` — Expected: PASS.
- [ ] **Step 5:** `swift build`, `swift test` — Expected: all pass. Commit by path: `explorer: connect to and keep shared folders in the sidebar`.

### Task 3: VoiceOver, renders, docs, hand-back

**Files:**
- Modify: `Sidebar.swift` (labels), `AccessibilityAudit.swift` / `AccessibilityLive.swift` (states), `RenderSamples.swift`, `grove-dotfiles/docs/manual/09-files.md`, the shared-folders spec only if something built differs

- [ ] **Step 1: VoiceOver:** a share row's label is `<name> on <host>, shared folder, connected` / `not connected` / `connecting`; the + is `Connect to Server`; the sheet's field and buttons labelled. Add render/audit states `shared` (three rows: connected, not connected, connecting) and `connect-sheet` (with a failure sentence showing); `--audit-accessibility all` — Expected: exit 0, 0 problems.
- [ ] **Step 2: Renders:** `shared` and `connect-sheet`, dark-medium and light-medium, into `/Users/gmarques/Developer/project-grove/artifacts/grove-explorer/renders/shared/`; look at each.
- [ ] **Step 3: Manual:** a "Shared folders" section in `09-files.md` (connect, ⌘K, states, Keychain, remove vs eject) and ⌘K in its keys table.
- [ ] **Step 4:** `swift test` once; commit by path: `explorer: shared folders read aloud, rendered and in the manual`.
- [ ] **Step 5: STOP.** Hand back render paths and a by-hand list: (1) ⌘K, `smb://grove-lab/<share>`, macOS's password sheet with "Remember in Keychain", the share opens and its row appears; (2) eject, then click the row: it reconnects without asking; (3) a wrong share name shows `There is no share called … on grove-lab` in the sheet; (4) cancel the password sheet: nothing shown; (5) quit and reopen: the row is still there; (6) a share mounted from Finder shows on its row, not in LOCATIONS; (7) Remove from Sidebar keeps it mounted under LOCATIONS. The controller installs only on the owner's word.
