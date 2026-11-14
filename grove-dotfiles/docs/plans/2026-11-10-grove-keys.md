# Grove Keys Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Grove menu bar app that makes Caps Lock a Hyper key (hold = ⌃⌥⇧⌘, tap = Escape), runs launchers and a cheat sheet, and generates AeroSpace's bindings and per-Mac monitors from one `keys.toml`.

**Architecture:** A Swift package at `project-grove/grove-keys/app` with a pure, tested core (`GroveKeysCore`: TOML subset, keys model, AeroSpace renderer, Hyper state machine, layer view-model, save pipeline) and a thin SwiftUI/AppKit app (`GroveKeys`: event tap, `hidutil`, menu bar, window, cheat sheet). grove installs it with a new module `96-keys-app`; the tracked `aerospace.toml` becomes `aerospace.base.toml` and the real file is generated.

**Tech Stack:** Swift 6 (Command Line Tools, no Xcode), SwiftUI + AppKit, CoreGraphics event taps, IOKit HID, Swift Testing; bash + bats for the grove module.

**Spec:** `grove-dotfiles/docs/specs/2026-11-10-grove-keys-design.md` (read it with this plan). Mockups: a private mock-up page.

## Global Constraints

- Work on branch `grove-keys` in `~/Developer/project-grove`; merge only when the user says "merge it". Never commit or push the private working folders.
- Bundle ID `com.projectgrove.keys`; app `~/Applications/Grove Keys.app`; executable `GroveKeys`; LaunchAgent label `com.projectgrove.keys`; `LSUIElement` true.
- Package platform `.macOS(.v14)`, swift-tools 6.0, the same `-plugin-path` TestingMacros workaround as `grove-themes/app/Package.swift`. CLT Swift has no `@State` macro: use `State<Value>` as grove-themes does.
- `GroveKeysCore` depends on `GroveThemesCore` via `.package(path: "../../grove-themes/app")` for `Palette`, `ThemeColors`, `StatePath` and the `grove-themes list --json` client. Do not copy those types.
- Paths: keys `~/.config/grove-keys/keys.toml`; base `~/.config/aerospace/aerospace.base.toml`; output `~/.config/aerospace/aerospace.toml`; app state `$GROVE_STATE/keys.json` (default `~/.local/state/grove/keys.json`).
- Caps Lock HID usage `0x700000039` → F18 `0x70000006D`; F18 virtual keycode `79`; Escape keycode `53`.
- Defaults: `tap = "escape"`, `tap_ms = 200`, `cheatsheet_ms = 500`, `enabled = true`.
- Machine name: `scutil --get LocalHostName`.
- Tints: workspace `green`, focus/move `aqua`, launcher `blue`, layout/resize `yellow`, mode/service `orange`, free `grey1`. Every colour comes from the palette (tests enforce).
- Copy is plain and specific (spec §7, §10). Red line format: `keys.toml line N: <message>` or `AeroSpace refused the config: <message> · previous config kept`.
- grove-dotfiles full bats suite takes ~12 min: run it in the background. Never run grove-dotfiles and grove-themes bats files in one call.

## Review Focus

- **Release order:** Caps Lock released before the other key's key-up. That key-up must still carry ⌃⌥⇧⌘ (apps would otherwise see a stray plain key-up). Test in Task 4.
- **Tap off mid-hold:** Pause, quit, permission revoked or tap disabled while Caps Lock is held. The machine must reset (hide the cheat sheet, post nothing) and the next press starts clean. Test in Task 4.
- **Hand edits with editor saves:** vim and VS Code save by writing a temp file and renaming it. The watcher must still see the change and keep watching. Test in Task 6.
- **Duplicate or unsupported TOML in a hand edit:** a repeated key or table, a dotted key, an inline table. These must give an error with the line number, not be silently dropped. Test in Task 1.
- **Launcher for an app that isn't installed:** Hyper+key must swallow the key and do nothing (no crash), and the row shows "not installed". Test in Task 5 (model); Task 7 makes `Launcher.open` return false.

---

### Task 0: Spike: does AeroSpace see flags added by an event tap? (throwaway)

**Files:** scratchpad only (`$SCRATCH/hyper-spike/main.swift`); nothing committed.

- [ ] **Step 1:** Write a ~60-line Swift script with an active session event tap (`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: keyDown|keyUp|flagsChanged)`). While F18 (79) is held, OR `.maskCommand|.maskControl|.maskAlternate|.maskShift` into other keys' flags and swallow F18. Apply the mapping with `hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}'` and clear it on exit (`'{"UserKeyMapping":[]}'`, plus a `signal(SIGINT)` handler).
- [ ] **Step 2:** Add a temporary binding `cmd-ctrl-alt-shift-1 = 'workspace 1'` to the live AeroSpace config and run `aerospace reload-config`.
- [ ] **Step 3:** Ask the user to run the script from Ghostty (`swiftc main.swift -o spike && ./spike`), grant what macOS asks for, and press Caps Lock+1 from workspace 2.
  Expected: AeroSpace switches to workspace 1. Note which permissions macOS asked for.
- [ ] **Step 4:** Remove the temporary binding and reload. Record the result in the private notes.
  **If AeroSpace did not switch:** stop and bring the result to the user before Task 1.

### Task 1: Package and TOML subset parser

**Files:**
- Create: `grove-keys/app/Package.swift`, `grove-keys/app/.gitignore` (`.build/`), `grove-keys/app/Sources/GroveKeysCore/Toml.swift`, `grove-keys/app/Sources/GroveKeys/main.swift` (prints "Grove Keys" for now)
- Test: `grove-keys/app/Tests/GroveKeysCoreTests/TomlParseTests.swift`

**Interfaces:**
- Produces:
  - `public enum TomlValue: Equatable, Sendable { case string(String), array([String]), int(Int), bool(Bool) }`
  - `public struct TomlEntry: Equatable, Sendable { public var key: String; public var value: TomlValue; public var leadingComments: [String]; public var trailingComment: String? }`
  - `public struct TomlSection: Equatable, Sendable { public var path: [String]; public var leadingComments: [String]; public var entries: [TomlEntry] }` (`path == []` is the top level before any header)
  - `public struct TomlDocument: Equatable, Sendable { public var sections: [TomlSection]; public var trailingComments: [String]; public static func parse(_ text: String) throws(TomlError) -> TomlDocument; public func section(_ path: [String]) -> TomlSection? }`
  - `public struct TomlError: Error, Equatable, Sendable { public let line: Int; public let message: String }`

- [ ] **Step 1: Write the failing tests** in `TomlParseTests.swift`:
  - `parsesHeadersKeysAndValues`: `[hyper]\ntap = "escape"\ntap_ms = 200\nenabled = true\n[aerospace.main]\nalt-1 = 'workspace 1'\nesc = ["reload-config", "mode main"]\n[monitors."Test-Mac"]\n"1" = "secondary"` → sections with paths `["hyper"]`, `["aerospace","main"]`, `["monitors","Test-Mac"]`; values `.string("escape")`, `.int(200)`, `.bool(true)`, `.string("workspace 1")`, `.array(["reload-config","mode main"])`, key `"1"`.
  - `keepsComments`: a `# c1` line before `[hyper]` lands in `leadingComments` of that section; `# c2` before `tap` in that entry's `leadingComments`; `tap = "escape" # c3` gives `trailingComment == "# c3"`; comments after the last entry land in `trailingComments`.
  - `escapesInStrings`: `"a \"b\" \\ c"` → `a "b" \ c`; a `#` inside a string is not a comment.
  - `errorsCarryLineNumbers` (Review Focus): each returns `TomlError` with the given line: duplicate key in one section (`line 3`, message contains `duplicate key "tap"`), repeated table header (`duplicate table [hyper]`), dotted key `a.b = 1` (`dotted keys are not supported`), inline table `x = { a = 1 }` (`inline tables are not supported`), unterminated string, array of non-strings `[1, 2]` (`arrays must hold strings`), missing `=`.
- [ ] **Step 2: Run** `cd grove-keys/app && swift test --filter TomlParseTests` → FAIL (types missing).
- [ ] **Step 3: Implement** `TomlDocument.parse` as a line-based parser (one key/value per line; multi-line arrays are allowed and joined until `]`). `Package.swift` declares targets `GroveKeysCore` (depends on `GroveThemesCore` product from `../../grove-themes/app`), executable `GroveKeys`, test target `GroveKeysCoreTests` (with `exclude: ["Fixtures"]` and the testing plugin flags).
- [ ] **Step 4: Run** `swift test --filter TomlParseTests` → PASS; `swift build` → succeeds.
- [ ] **Step 5: Commit** `grove-keys: package and TOML subset parser`.

### Task 2: TOML writer and the keys model

**Files:**
- Create: `grove-keys/app/Sources/GroveKeysCore/TomlWrite.swift`, `grove-keys/app/Sources/GroveKeysCore/KeysFile.swift`, `grove-keys/app/Sources/GroveKeysCore/Shortcut.swift`, `grove-keys/app/Sources/GroveKeysCore/KeyNames.swift`
- Test: `Tests/GroveKeysCoreTests/TomlWriteTests.swift`, `KeysFileTests.swift`, `ShortcutTests.swift`

**Interfaces:**
- Consumes: Task 1 types.
- Produces:
  - `extension TomlDocument { public func serialized() -> String }`: strings written with `"` and escapes; arrays `["a", "b"]`; one blank line before each header except the first; comments where they were.
  - `public struct HyperSettings: Equatable, Sendable { public var enabled = true; public var tap: TapAction = .escape; public var tapMs = 200; public var cheatsheetMs = 500 }`, `public enum TapAction: String, Sendable { case escape, none }`
  - `public struct KeysFile: Equatable, Sendable` with `public init(document: TomlDocument) throws(TomlError)`, `public init(text: String) throws(TomlError)`, `public private(set) var document: TomlDocument`, computed `hyper: HyperSettings`, `launch: [(key: String, bundleID: String)]`, `modes: [(name: String, bindings: [(key: String, value: TomlValue)])]` (file order, `main` first if present), `monitors(host: String) -> [(workspace: String, target: String)]`; mutators `setHyper(_:)`, `setLaunch(key:bundleID:)`, `removeLaunch(key:)`, `setBinding(mode:key:value:)`, `removeBinding(mode:key:)`, `setMonitor(host:workspace:target:)` (creates the section when missing; target `"main"` with no other entries still writes it). Validation errors (unknown `[hyper]` key, `tap` not escape/none, negative ms, non-string launch value) are `TomlError` with the entry's line.
  - `public struct Shortcut: Hashable, Sendable { public var modifiers: Set<Modifier>; public var key: String; public init?(aerospace: String); public var aerospace: String; public var symbols: String; public var isHyper: Bool }`, `public enum Modifier: String, Sendable { case cmd, ctrl, alt, shift }`. `init?(aerospace: "hyper-t")` gives all four modifiers; `aerospace` writes modifiers in AeroSpace's order `cmd-ctrl-alt-shift-` but `isHyper` shortcuts are written back as `hyper-…`; `symbols` gives `"⌃⌥⇧⌘ T"`, `"⌥⇧ 1"`, `"Esc"`, `"⌫"`.
  - `public enum KeyNames { public static func keyCode(_ name: String) -> UInt16?; public static func name(_ keyCode: UInt16) -> String? }`: US ANSI table for a–z, 0–9, `minus equal leftSquareBracket rightSquareBracket backslash semicolon quote comma period slash backtick tab enter esc backspace space left right up down` (AeroSpace's key names).

- [ ] **Step 1: Write the failing tests:**
  - `TomlWriteTests.roundTripsShippedFile`: `TomlDocument.parse(fixture("keys.toml")).serialized() == fixture("keys.toml")` (fixture = the shipped file from Task 3; add it to `Tests/GroveKeysCoreTests/Fixtures/` in this task using the content in Task 3 Step 1).
  - `TomlWriteTests.editKeepsComments`: set a value in a section with a leading comment, serialize, comment still directly above.
  - `KeysFileTests`: defaults when `[hyper]` is missing; `setLaunch(key:"t", bundleID:"com.mitchellh.ghostty")` then reading `launch` returns it, and the text contains `t = "com.mitchellh.ghostty"` under `[launch]`; `removeBinding` removes only that key; `setMonitor` on a missing host creates `[monitors."Host"]` at the end; `monitors(host:"Other")` is empty; `tap = "space"` throws at its line.
  - `ShortcutTests`: `hyper-t` → `isHyper`, `aerospace == "hyper-t"`, `symbols == "⌃⌥⇧⌘ T"`; `alt-shift-semicolon` → `symbols == "⌥⇧ ;"`; `cmd-ctrl-alt-shift-1` → `isHyper == true`; `KeyNames.keyCode("a") == 0`, `keyCode("semicolon") == 41`, `name(53) == "esc"`.
- [ ] **Step 2: Run** `swift test` → the new tests FAIL.
- [ ] **Step 3: Implement** the four files.
- [ ] **Step 4: Run** `swift test` → PASS.
- [ ] **Step 5: Commit** `grove-keys: TOML writer, keys model, shortcuts`.

### Task 3: Shipped files and the AeroSpace renderer

**Files:**
- Create: `grove-dotfiles/config/grove-keys/keys.toml`, `grove-dotfiles/config/aerospace/aerospace.base.toml` (git mv from `aerospace.toml`), `grove-keys/app/Sources/GroveKeysCore/AeroSpaceRenderer.swift`, `grove-keys/app/Sources/GroveKeysCore/KeysPaths.swift`
- Modify: `grove-dotfiles/config/.gitignore` (add `!/grove-keys/` and `/aerospace/aerospace.toml`), `grove-keys/app/Sources/GroveKeys/main.swift` (`--render-aerospace`)
- Test: `Tests/GroveKeysCoreTests/AeroSpaceRendererTests.swift`, fixtures `Fixtures/aerospace-before.toml` (a copy of today's `aerospace.toml`), `Fixtures/aerospace.base.toml`, `Fixtures/keys.toml`

**Interfaces:**
- Consumes: `KeysFile`, `Shortcut`.
- Produces:
  - `public enum AeroSpaceRenderer { public static let header: String; public static func render(keys: KeysFile, base: String, host: String) -> String }`. Output: `header` (`# Generated by Grove Keys from ~/.config/grove-keys/keys.toml and aerospace.base.toml. Edit those, not this file.`), a blank line, `base`, then for each mode `[mode.<name>.binding]` with entries (`hyper-` expanded to `cmd-ctrl-alt-shift-`), then `[workspace-to-monitor-force-assignment]` with `"<ws>" = "<target>"` when this host has entries.
  - `public struct KeysPaths: Sendable { public var keys, base, output: URL; public static func standard(home: URL, environment: [String: String]) -> KeysPaths }` (uses `XDG_CONFIG_HOME` if set, else `~/.config`).
  - `GroveKeys --render-aerospace`: renders with `KeysPaths.standard`, host from `scutil --get LocalHostName`, writes output atomically (to `$GROVE_KEYS_RENDER_OUT` instead when set, for grove's check), exit 0; on a `TomlError` prints `keys.toml line N: message` to stderr, exit 1, output untouched.

- [ ] **Step 1: Create the shipped files.** `aerospace.base.toml` = today's `aerospace.toml` minus both `[mode.*.binding]` tables, plus an `[[on-window-detected]]` rule floating `com.projectgrove.keys` next to the Grove Themes one; its top comment says bindings live in `grove-keys/keys.toml`. `keys.toml` = the spec §5 header and `[hyper]` block with defaults, an empty `[launch]` with the commented example, `[aerospace.main]` and `[aerospace.service]` with today's bindings and comments copied unchanged (keys and values exactly as in the current file), and `[monitors."Test-Mac"]` empty with the spec's comment. Copy both and today's file into `Fixtures/`.
- [ ] **Step 2: Write the failing tests** in `AeroSpaceRendererTests`:
  - `rendersTodaysBindings`: parse `render(keys: fixture keys, base: fixture base, host: "Test-Mac")` and `aerospace-before.toml` with `TomlDocument.parse`; for both modes, the `[mode.X.binding]` entries (key → value) are equal; all non-mode sections of `before` appear in the render with equal entries.
  - `expandsHyper`: binding `hyper-1 = "workspace 1"` renders `cmd-ctrl-alt-shift-1 = "workspace 1"`.
  - `monitorsForThisHostOnly`: host `A` has `"1" = "secondary"`, host `B` has `"2" = "main"`; render for `A` contains `[workspace-to-monitor-force-assignment]` and `"1" = "secondary"` and not `"2"`; render for `C` has no such table.
  - `startsWithHeader`.
- [ ] **Step 3: Run** `swift test --filter AeroSpaceRendererTests` → FAIL.
- [ ] **Step 4: Implement** renderer, paths and the `--render-aerospace` entry.
- [ ] **Step 5: Run** `swift test` → PASS. Then `swift run GroveKeys --render-aerospace` against a temp `XDG_CONFIG_HOME` holding the two shipped files → exit 0 and the output starts with the header.
- [ ] **Step 6: Commit** `grove-keys: keys.toml, aerospace.base.toml and the renderer`.

### Task 4: Hyper state machine

**Files:**
- Create: `grove-keys/app/Sources/GroveKeysCore/HyperMachine.swift`
- Test: `Tests/GroveKeysCoreTests/HyperMachineTests.swift`

**Interfaces:**
- Consumes: `HyperSettings`.
- Produces:
  - `public struct KeyEvent: Sendable { public enum Kind: Sendable { case down, up }; public var kind: Kind; public var keyCode: UInt16; public var time: Double /* seconds */ }`
  - `public enum Disposition: Equatable, Sendable { case pass, passWithHyper, swallow }`
  - `public enum HyperEffect: Equatable, Sendable { case postEscape, launch(key: String), showCheatSheet, hideCheatSheet }`
  - `public struct HyperMachine: Sendable { public static let f18: UInt16 = 79; public init(settings: HyperSettings, launchKeys: Set<String>); public mutating func handle(_ event: KeyEvent) -> (Disposition, [HyperEffect]); public mutating func tick(now: Double) -> [HyperEffect]; public mutating func reset() -> [HyperEffect] }`. The app calls `tick` from a timer armed at F18 down for `cheatsheetMs`. Autorepeat F18 downs while held are swallowed and ignored.

- [ ] **Step 1: Write the failing tests** (times in seconds):
  - `tapSendsEscape`: F18 down 0.0, up 0.1 → both `.swallow`; effects on up `[.postEscape]`.
  - `slowTapSendsNothing`: down 0.0, up 0.25 → `[]`.
  - `tapNoneSendsNothing`: `tap: .none`, down 0.0, up 0.1 → `[]`.
  - `holdAddsHyper`: F18 down, `1` down → `.passWithHyper`, `1` up → `.passWithHyper`, F18 up → `[]` (used, no Escape).
  - `keyUpAfterReleaseStillHyper` (Review Focus): F18 down, `1` down, F18 up, `1` up → the `1` up is `.passWithHyper`; a later `1` down is `.pass`.
  - `cheatSheetShowsAndHides`: F18 down 0.0, `tick(now: 0.5)` → `[.showCheatSheet]`, F18 up 0.9 → `[.hideCheatSheet]`, no Escape. With `cheatsheetMs = 0`, `tick` returns `[]`.
  - `keyAfterCheatSheetHidesIt`: shown, then `t` down → `.passWithHyper` and `[.hideCheatSheet]`.
  - `launcherSwallows`: `launchKeys: ["t"]`, F18 down, `t` down → `.swallow` + `[.launch(key: "t")]`, `t` up → `.swallow`.
  - `resetMidHold` (Review Focus): F18 down, tick to show, `reset()` → `[.hideCheatSheet]`; next F18 down/up 0.1 later → `[.postEscape]`.
  - `disabledPassesEverything`: `enabled = false` → every event `.pass`, no effects.
  - `otherKeysPassWhenNotHeld`: `a` down → `.pass`.
- [ ] **Step 2: Run** `swift test --filter HyperMachineTests` → FAIL.
- [ ] **Step 3: Implement** `HyperMachine` (track held state, press start time, "used" flag, cheat sheet shown, and the set of keycodes pressed while held so their key-ups keep Hyper).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `grove-keys: Hyper state machine`.

### Task 5: Layers, labels, kinds, folding, conflicts

**Files:**
- Create: `grove-keys/app/Sources/GroveKeysCore/Layers.swift`, `grove-keys/app/Sources/GroveKeysCore/BindingRows.swift`
- Test: `Tests/GroveKeysCoreTests/LayersTests.swift`, `BindingRowsTests.swift`

**Interfaces:**
- Consumes: `KeysFile`, `Shortcut`, `KeyNames`.
- Produces:
  - `public enum BindingKind: Sendable { case workspace, focusMove, launcher, layout, mode, other; public var tint: String }` (palette key names per Global Constraints; `other` → `"fg"`).
  - `public struct KeyBinding: Equatable, Sendable { public var key: String; public var label: String; public var kind: BindingKind; public var source: Source; public var conflict: Bool; public var missingApp: Bool; public enum Source: Equatable, Sendable { case launcher(bundleID: String), aerospace(mode: String, key: String) } }`
  - `public struct Layer: Equatable, Sendable, Identifiable { public var id: String; public var title: String; public var bindings: [String: KeyBinding] /* by AeroSpace key name */ }`
  - `public enum Layers { public static func build(from keys: KeysFile, appName: (String) -> String?) -> [Layer] }`: order Hyper, Option, Option+Shift, then other modifier sets in main mode (title from symbols, e.g. "⌃⌥"), then each non-main mode titled capitalised ("Service"), whose layer includes every binding in that mode keyed by key name (modifier shown in the label). Hyper layer = launchers + main-mode Hyper bindings; launcher wins on a clash and both are marked `conflict` (the AeroSpace one stays listed in Bindings rows only). `appName` returns nil for a missing app → `missingApp = true`, label = bundle ID's last component.
  - `public enum CommandLabel { public static func label(_ value: TomlValue) -> (String, BindingKind) }`: `workspace N` → (`ws N`, .workspace); `move-node-to-workspace N` → (`→ ws N`, .workspace); `workspace-back-and-forth` → (`back & forth`, .workspace); `move-workspace-to-monitor …` → (`→ monitor`, .workspace); `focus left|down|up|right` → (`← focus` / `↓ focus` / `↑ focus` / `→ focus`, .focusMove); `move …` → (`← move` …, .focusMove); `join-with …` → (`join ←` …, .focusMove); `resize smart -N|+N` → (`resize −` / `resize +`, .layout); `layout tiles …` → (`tiles`), `layout accordion …` → (`accordion`), `layout floating tiling` → (`float/tile`) all .layout; `mode X` → (`X`, .mode); arrays use their first non-`mode main` command (`reload-config` → `reload`, `flatten-workspace-tree` → `reset layout`, `close-all-windows-but-current` → `close others`, all .mode); anything else → (first word, .other).
  - `public struct BindingRow: Equatable, Sendable { public var shortcuts: String; public var action: String; public var keys: [String]; public var count: Int }`, `public enum BindingRows { public static func rows(mode: [(key: String, value: TomlValue)], folded: Bool) -> [BindingRow] }`: with `folded`, entries `<mods>-1…9` whose values are `<cmd> 1…<cmd> 9` become one row (`"⌥ 1 … 9"`, `"workspace 1 … 9"`, count 9); otherwise one row each.

- [ ] **Step 1: Write the failing tests:**
  - `LayersTests.shippedFileLayers`: from the fixture `keys.toml`: layer titles `["Hyper","Option","Option+Shift","Service"]`; Hyper empty; Option `"1"` → label `ws 1`, kind `.workspace`; `"h"` → `← focus`, `.focusMove`; `"slash"` → `tiles`; Option+Shift `"semicolon"` → `service`, `.mode`; Service `"r"` → `reset layout`; Service `"esc"` → `reload`.
  - `LayersTests.launcherConflict`: launcher `t` + main binding `hyper-t` → Hyper layer `"t"` is the launcher with `conflict == true`.
  - `LayersTests.missingApp` (Review Focus): `appName` returns nil → `missingApp == true`.
  - `LayersTests.tintsArePaletteKeys`: every `BindingKind.tint` is a key in `everforest-dark-medium` (read `grove-dotfiles/theme/everforest-dark-medium` relative to the package via `#filePath`).
  - `BindingRowsTests.foldsNineWorkspaces`: shipped main mode folded → first row `shortcuts == "⌥ 1 … 9"`, `action == "workspace 1 … 9"`, `count == 9`; unfolded → 27 rows; a run missing `alt-5` doesn't fold.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` → PASS.
- [ ] **Step 5: Commit** `grove-keys: layers, labels and binding rows`.

### Task 6: Save pipeline and file watcher

**Files:**
- Create: `grove-keys/app/Sources/GroveKeysCore/SavePipeline.swift`, `grove-keys/app/Sources/GroveKeysCore/FileWatcher.swift`, `grove-keys/app/Sources/GroveKeysCore/AeroSpaceCLI.swift`
- Test: `Tests/GroveKeysCoreTests/SavePipelineTests.swift`, `FileWatcherTests.swift`

**Interfaces:**
- Consumes: `KeysFile`, `AeroSpaceRenderer`, `KeysPaths`.
- Produces:
  - `public protocol AeroSpaceRunning: Sendable { func isRunning() async -> Bool; func dryRun() async -> (ok: Bool, message: String); func reload() async }`; `public struct AeroSpaceCLI: AeroSpaceRunning` (runs `/opt/homebrew/bin/aerospace reload-config --dry-run` / `reload-config`; running = `ps -axo comm=` contains `AeroSpace`).
  - `public enum SaveResult: Equatable, Sendable { case applied(KeysFile), unchanged(KeysFile), keysInvalid(TomlError), aerospaceRejected(KeysFile, message: String) }` and `public var redLine: String?` giving the exact copy from Global Constraints.
  - `public struct SavePipeline: Sendable { public init(paths: KeysPaths, host: String, aerospace: any AeroSpaceRunning); public func run() async -> SaveResult; public func write(_ keys: KeysFile) throws }` (spec §8 steps 1, 3–5; `write` is temp file + rename in the same folder).
  - `public final class FileWatcher: @unchecked Sendable { public init(file: URL, onChange: @escaping @Sendable () -> Void); public func start(); public func stop(); public func ignoreNextChange(contents: Data) }`: watches the file's folder with a `DispatchSource` (`.write`), compares the file's modification date and contents, and calls `onChange` once per real change; a change whose contents equal the `ignoreNextChange` data is skipped once.

- [ ] **Step 1: Write the failing tests** with a fake runner and temp folders:
  - `appliesAndReloads`: valid keys, AeroSpace running, dry run ok → output written, `reload` called once, `.applied`.
  - `unchangedSkipsReload`: second run with no change → `.unchanged`, no further reload.
  - `invalidKeysTouchesNothing`: keys file with a duplicate key on line 4 → `.keysInvalid(line: 4…)`, output file bytes unchanged, `redLine` starts with `keys.toml line 4:`.
  - `rejectedRestoresOld`: dry run fails with `"unknown command"` → output bytes equal the old ones, `redLine == "AeroSpace refused the config: unknown command · previous config kept"`.
  - `notRunningWritesWithoutReload`: `isRunning` false → output written, `dryRun` and `reload` not called, `.applied`.
  - `FileWatcherTests.seesRenameSave` (Review Focus): start watching `keys.toml`; write `x.tmp` and `rename` it over `keys.toml` → `onChange` fires once within 1 s; do it again → fires again.
  - `FileWatcherTests.ignoresOwnWrite`: `ignoreNextChange(contents:)` then write those contents → no call; a later different write → one call.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` → PASS.
- [ ] **Step 5: Commit** `grove-keys: save pipeline and file watcher`.

### Task 7: The app engine and menu bar item

**Files:**
- Create: `grove-keys/app/Sources/GroveKeys/GroveKeysApp.swift` (replaces `main.swift`'s print; keeps `--render-aerospace`), `HyperEngine.swift`, `HIDMapping.swift`, `Launcher.swift`, `Permissions.swift`, `MenuBarView.swift`, `AppModel.swift`, `Theme.swift`
- Create: `grove-keys/app/Sources/GroveKeysCore/KeysState.swift`
- Test: `Tests/GroveKeysCoreTests/KeysStateTests.swift`

**Interfaces:**
- Consumes: `HyperMachine`, `SavePipeline`, `FileWatcher`, `KeysFile`, GroveThemesCore's `ThemeColors`, `StatePath` and list client (copy Grove Themes' `Theme.swift` approach of mapping `ThemeColors` to SwiftUI colours, importing the types).
- Produces:
  - `public struct KeysState: Codable, Equatable, Sendable { public var accessibility: Bool; public var inputMonitoring: Bool; public var mapping: Bool; public static func url(environment:home:) -> URL /* $GROVE_STATE/keys.json */ ; public func write(to: URL) throws }` (JSON keys `accessibility`, `input_monitoring`, `mapping`; module 96 reads them).
  - `@MainActor final class AppModel: ObservableObject` holding `keys: KeysFile`, `redLine: String?`, `paused: Bool`, `permissions`, `colors`, `layers: [Layer]`, and `func edit(_ change: (inout KeysFile) -> Void)` (mutate → `SavePipeline.write` → `run` → publish). Tasks 8–10 build on it.
  - `HIDMapping.set() / clear()` run `/usr/bin/hidutil property --set` with the JSON in Task 0; `HyperEngine` owns the tap (re-enables on `.tapDisabledByTimeout`/`.tapDisabledByUserInput`; after 3 failures in 60 s calls `reset()`, clears the mapping and sets `redLine`), reapplies the mapping on `NSWorkspace.didWakeNotification` and on IOHIDManager keyboard-matched callbacks, posts Escape with `CGEvent(keyboardEventSource:virtualKey:53,keyDown:)`, adds `[.maskCommand, .maskControl, .maskAlternate, .maskShift]` for `.passWithHyper`. `Launcher.open(bundleID:) -> Bool` uses `NSWorkspace.urlForApplication(withBundleIdentifier:)` (false when nil, Review Focus) then `openApplication(at:configuration:)`.
  - Permissions: Accessibility via `AXIsProcessTrusted()`, Input Monitoring via `CGPreflightListenEventAccess()`; polled every 2 s until both true; mapping only set while both are true and the tap is running and `enabled && !paused`. Settings links: `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility` and `…?Privacy_ListenEvent`.
  - Menu (spec §7, mockup §4): `MenuBarExtra` with a key glyph (`keyboard` SF Symbol; orange when a permission is missing or `redLine` is set), items *Open Grove Keys* (⌘,), *Show cheat sheet*, *Pause Hyper*/*Resume Hyper*, *Quit Grove Keys* (⌘Q). Quit and Pause clear the mapping and call `reset()`.
- [ ] **Step 1: Write the failing test** `KeysStateTests.writesSnakeCaseJSON`: writing `KeysState(accessibility: true, inputMonitoring: false, mapping: false)` produces JSON with keys `accessibility`, `input_monitoring`, `mapping`; `url` honours `GROVE_STATE`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** `KeysState`, then the app files. **Step 4: Run** `swift test` → PASS; `swift build -c release` → succeeds.
- [ ] **Step 5: Live check with the user:** run `.build/release/GroveKeys` from Ghostty; grant both permissions; confirm tap → Escape (in a Ghostty vim), Caps+1 with a temporary `hyper-1 = "workspace 1"` in `keys.toml` (the file save alone must apply it), Pause clears the mapping (`hidutil property --get UserKeyMapping` shows null), Quit clears it. Remove the temporary binding.
- [ ] **Step 6: Commit** `grove-keys: Hyper engine and menu bar item`.

### Task 8: Window, Keyboard tab

**Files:**
- Create: `grove-keys/app/Sources/GroveKeys/WindowView.swift` (hidden title bar, tabs, red line, permission banner), `KeyboardView.swift`, `KeyCapView.swift`, `KeyEditorPopover.swift`, `KeyboardLayout.swift` (in Core: `GroveKeysCore/KeyboardLayout.swift`), `CommandCatalog.swift` (Core)
- Test: `Tests/GroveKeysCoreTests/KeyboardLayoutTests.swift`

**Interfaces:**
- Consumes: `AppModel`, `Layers`, `CommandLabel`, `Shortcut`, `KeysFile` mutators.
- Produces:
  - `public enum KeyboardLayout { public struct Cap: Sendable { public var name: String? /* AeroSpace key name; nil for modifiers/fn */; public var legend: String; public var width: Double; public var modifier: Modifier? } ; public static let rows: [[Cap]] }`: the five MacBook ANSI rows of the mockup (`backtick 1…0 minus equal backspace(1.5)` / `tab(1.5) q…p leftSquareBracket rightSquareBracket backslash` / `caps(1.75) a…l semicolon quote enter(1.75)` / `shift(2.25) z…m comma period slash shift(2.25)` / `fn ctrl alt cmd(1.25) space(5) cmd(1.25) alt left up/down right`).
  - `public enum CommandCatalog { public static let entries: [(title: String, template: String)] }`: `workspace N`, `move-node-to-workspace N`, `focus left|down|up|right`, `move left|down|up|right`, `resize smart -50|+50`, `layout tiles horizontal vertical`, `layout accordion horizontal vertical`, `layout floating tiling`, `workspace-back-and-forth`, `move-workspace-to-monitor --wrap-around next`, `mode service`, `close`, `reload-config`, `fullscreen`.
  - Behaviour as spec §7 and mockup §1: layer picker with binding counts, tinted caps (`BindingKind.tint`), held modifiers shown, popover with Launcher (Hyper only; app picker over `/Applications` and `~/Applications` `.app` bundles) · AeroSpace (catalog + free text) · None; writes via `AppModel.edit`; arrows / Ctrl+H/J/K/L move between caps, Enter opens, Esc closes popover then window.
- [ ] **Step 1: Write the failing test** `KeyboardLayoutTests`: every non-nil `name` resolves with `KeyNames.keyCode`; row widths sum to 15.0 ± 0.01 for rows 1–4; every key used in the shipped `keys.toml` appears in the layout.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` → PASS; build.
- [ ] **Step 5: Live check with the user** against mockup §1: layers, tints, popover on ⌥1, add a launcher on Hyper+T for Ghostty and use it, set it to None.
- [ ] **Step 6: Commit** `grove-keys: Keyboard tab`.

### Task 9: Window, Bindings tab and Monitors

**Files:**
- Create: `grove-keys/app/Sources/GroveKeys/BindingsView.swift`, `ShortcutRecorder.swift`, `MonitorsView.swift`, `Displays.swift`

**Interfaces:**
- Consumes: `AppModel`, `BindingRows`, `KeysFile` mutators, `KeyNames`, `Shortcut`.
- Produces (spec §7, mockup §2): groups Hyper key (toggle `enabled`, tap Escape/None, the two ms fields), Launchers (rows, add, missing app shown grey "not installed"), one group per mode (folded rows with "Show all N", add, remove), Monitors for this Mac. `ShortcutRecorder` captures the next key-down with a local `NSEvent` monitor, builds a `Shortcut` from its keycode and flags (four modifiers → `hyper-`), Esc cancels; a clash in the same mode shows *Replace* / *Cancel* inline. `Displays.current() -> [String]` from `NSScreen.screens.map(\.localizedName)`; each workspace 1–9 has a menu `main · secondary · built-in · <names>`; "Not set for this Mac yet" when the section is empty.
- [ ] **Step 1: Implement** the views (logic is already covered by Tasks 2, 5 and 6).
- [ ] **Step 2: Build** `swift build -c release` → succeeds; `swift test` → PASS.
- [ ] **Step 3: Live check with the user** against mockup §2: add, record, clash prompt, remove, fold/unfold, monitor menu writes `[monitors."Test-Mac"]` and the generated `aerospace.toml` gains the table; a bad hand edit shows the red line with its line number.
- [ ] **Step 4: Commit** `grove-keys: Bindings tab and monitors`.

### Task 10: Cheat sheet panel

**Files:**
- Create: `grove-keys/app/Sources/GroveKeys/CheatSheetPanel.swift`

**Interfaces:**
- Consumes: `KeyboardView` in read-only mode, `HyperEffect.showCheatSheet/hideCheatSheet`, *Show cheat sheet* menu item (shows until the next key or click).
- Produces: a non-activating borderless `NSPanel` (`.nonactivatingPanel`, level `.statusBar`, `ignoresMouseEvents` true while shown by hold) centred on the screen of the key window (fallback `NSScreen.main`), dimmed backdrop, title "Hyper" and "⌃⌥⇧⌘ · release Caps Lock to close", as mockup §3.
- [ ] **Step 1: Implement.** **Step 2: Build** → succeeds.
- [ ] **Step 3: Live check with the user:** hold Caps Lock alone → panel after ~0.5 s on the focused screen; release → gone, no Escape; menu item shows it.
- [ ] **Step 4: Commit** `grove-keys: cheat sheet`.

### Task 11: grove module `96-keys-app`

**Files:**
- Create: `grove-dotfiles/modules/96-keys-app/module.sh`, `grove-dotfiles/tests/modules_keys_app.bats`, `grove-keys/README.md`
- Modify: `grove-dotfiles/modules/98-aerospace/module.sh` (check: `aerospace.toml` missing → `grove_fail "AeroSpace has no config yet; run grove install keys-app"`), `grove-dotfiles/tests/modules_aerospace.bats`, `grove-dotfiles/tests/aerospace_config.bats` (now reads `aerospace.base.toml` and renders via the app or the fixture), `grove-dotfiles/README.md` (module list), `grove-dotfiles/tests/config_allowlist.bats` if it lists `.config` entries

**Interfaces:**
- Consumes: `GroveKeys --render-aerospace`, `KeysState` JSON, 97-themes-app's helpers as the pattern (copy its structure with `_ka_` prefixes; label `com.projectgrove.keys`; app name `Grove Keys.app`; executable `GroveKeys`; stamp `$GROVE_STATE/keys-app.stamp`).
- Produces:
  - Stamp hash covers the tracked files of both `grove-keys/app` and `grove-themes/app` (the dependency).
  - LaunchAgent plist like 97's plus `<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>`.
  - `apply` (spec §9) also runs `GroveKeys --render-aerospace` after install, and opens the two Privacy panes when `keys.json` says either is false.
  - `check` returns 3 (needs work) for: app missing, stamp stale, plist differs, agent not loaded, `aerospace.toml` differs from a fresh render (render to a temp file via `GROVE_KEYS_RENDER_OUT`), and fails with a message for missing permissions (`Grove Keys needs Input Monitoring: System Settings › Privacy & Security`) and a missing mapping while enabled.
- [ ] **Step 1: Write the failing bats tests** mirroring `modules_themes_app.bats` (about, no swift, missing app, stale source incl. a change in `grove-themes/app`, plist differs, not loaded, ok, check changes nothing, apply builds/assembles/signs/installs/loads, failed build keeps the old app, README lists the module, `swift test` passes in `grove-keys/app`), plus: `keys-app: needs work when aerospace.toml is stale`, `keys-app: fails when input monitoring is off` (fake `keys.json`), `keys-app: plist restarts on crash only`, `aerospace: fails without aerospace.toml and names keys-app`, and in `aerospace_config.bats` that the shipped `keys.toml` + base render keeps every binding the old tests checked.
- [ ] **Step 2: Run** `bats tests/modules_keys_app.bats tests/modules_aerospace.bats tests/aerospace_config.bats` → new tests FAIL.
- [ ] **Step 3: Implement** the module and the 98 change; write `grove-keys/README.md` (what it is, the file, permissions, `swift test`).
- [ ] **Step 4: Run** those bats files → PASS; then the full grove-dotfiles suite in the background → all pass; `grove check` → `96-keys-app` needs work before install.
- [ ] **Step 5: Commit** `grove-dotfiles: module 96-keys-app`.

### Task 12: Install and check by hand

- [ ] **Step 1:** `grove install keys-app` on this Mac; grant Accessibility and Input Monitoring; `grove check` → `96-keys-app ok`, `98-aerospace ok`.
- [ ] **Step 2:** With the user, run the spec §11 by-hand list: tap, hold, cheat sheet, a launcher added in the window, a hand edit (from vim, to cover rename saves), a bad hand edit, Pause/Resume, sleep/wake, a password field (Hyper does nothing; Option shortcuts work), log out and in (app back, Caps Lock is Hyper).
- [ ] **Step 3:** Copy the run ledger to the private notes; list deferred minors there. Tell the user it's ready to look at live and wait for "merge it".
