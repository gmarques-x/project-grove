# Grove Themes GUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native SwiftUI menu bar app, Grove Themes (dropdown of six scheme tiles + a gallery window with a switch log), that wears the current scheme and drives the `grove-themes` CLI, installed and started at login by grove module `97-themes-app`.

**Architecture:**
- The CLI gains `palettes` in `list --json`, a switch log, and `grove-themes log`.
- `grove-themes/app/` is a Swift package: `GroveThemesCore` (models, CLI client, status text, the app's state model; all unit-tested) and `GroveThemes` (SwiftUI views only).
- `97-themes-app` builds it, assembles and signs `~/Applications/Grove Themes.app`, and loads a LaunchAgent.

**Tech Stack:** bash 3.2 + bats (CLI, module), Swift 6.4 Command Line Tools (no Xcode), SwiftUI `MenuBarExtra(.window)` + `Window`, Observation (`@Observable`), Swift Testing, macOS 14+, `sips`/`iconutil`/`codesign`/`launchctl`.

**Spec:** `grove-dotfiles/docs/specs/2026-11-10-grove-themes-gui-design.md` (§4 CLI, §5 app, §6 module, §7 tests). The CLI it drives: `2026-11-10-grove-themes-design.md` §6–7.

## Global Constraints

- Branch `themes-gui` in the main checkout (`~/Developer/project-grove`), never a worktree. **Don't `git checkout main` with generated configs at stake; finishing uses `git branch -f main themes-gui` from the branch.**
- Never run `grove-themes set/render`, `grove install`, real `osascript`/`defaults write`/signals, `launchctl` or `codesign` against the real Mac in tests. grove-themes tests get stubs from `tests/setup_suite.bash`; grove-dotfiles tests from `grove_test_setup` (temp `HOME`, `GROVE_STATE`, `GROVE_CONFIG`).
- Bash 3.2 for the CLI and module; bats `[[ … ]] || false`, never a bare `[[ ]]`/`! cmd` mid-test.
- Swift: `// swift-tools-version:6.0`, `platforms: [.macOS(.v14)]`, no third-party packages. Build/test with `zsh -lc 'cd …/grove-themes/app && swift build'` / `swift test`.
- The app never writes configs or settings. CLI path `~/.local/bin/grove-themes`, overridable with env `GROVE_THEMES_CLI`. State file `${GROVE_STATE:-~/.local/state/grove}/theme`.
- Look B: every colour in the views comes from the current scheme's palette (from `list --json`); fonts `JetBrains Mono` (fallback `.monospaced`). The card scheme name and the dropdown's current-scheme line share one text style.
- Bundle id and agent label `com.projectgrove.themes`; app `~/Applications/Grove Themes.app`, executable `GroveThemes`; agent `~/Library/LaunchAgents/com.projectgrove.themes.plist`; stamp `$GROVE_STATE/themes-app.stamp`.
- Private working files (gitignored) are never committed. `grove-themes/app/.build/` is gitignored.
- Commits signed, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push.

## Review Focus

1. **The app starts before the CLI works** (login before `grove install` finished, or the link broken): the dropdown shows the not-installed message, and opening the dropdown again re-checks and recovers without relaunching. Test in Task 2 (`refresh` recovers after the runner starts succeeding).
2. **A second click while a switch runs**, or a switch from the terminal mid-switch: the second click is ignored, nothing runs twice, and the model ends on whatever the state file says. Test in Task 2.
3. **A damaged log** (half-written or garbage line in `theme-log.jsonl`): `log` skips bad lines and the app still shows the rest. Test in Task 1 and Task 2.
4. **Switches from another day**: the status line says "on 9 Nov at 13:10", not "at 13:10". Test in Task 2.
5. **Rebuilding while the app runs / a failed build**: apply leaves the installed app and stamp untouched on a build failure, and restarts the running app on success. Test in Task 4.

Rulings made while planning:
- **P1:** status text counts "N updated now" over every step except `configs` whose result is `live` or `next-prompt`; `next-launch` steps are named ("yazi next launch"); `needs-you`/`failed` steps are named with their message. (With today's steps that reads "10 updated now, yazi next launch"; the spec's "11" was an example.)
- **P2:** the app's state model (`ThemesModel`) lives in Core so its behaviour is unit-tested; views only read it and call it.

---

### Task 1: CLI palettes, switch log and `log`

**Files:**
- Modify: `grove-themes/bin/grove-themes`, `grove-themes/lib/state.sh` (log writing), `grove-themes/README.md`
- Create: `grove-themes/lib/log.sh`
- Test: `grove-themes/tests/cli.bats`, create `grove-themes/tests/log.bats`

**Interfaces:**
- Produces (Task 2 decodes these exact shapes):
  - `list --json` → `{"current": S, "schemes": [6 names], "palettes": {"<scheme>": {"name": "Dark Medium", "appearance": "dark"|"light", "colors": {"bg0": "#RRGGBB", …}}}}`, colours exactly `bg0 bg1 bg2 bg3 fg grey1 red orange yellow green aqua blue purple`.
  - Log line in `$GROVE_STATE/theme-log.jsonl`: `{"time": "2026-11-10T13:10:04+00:00", "scheme": S, "exit": 0|1, "steps": [{"name": …, "result": …, "message": …}]}` — `steps` exactly as `set --json` prints them. Keep the last 50 lines.
  - `grove-themes log [--json] [-n N]` → newest first; `--json` → `{"entries": [...]}`; text → one line per entry `<time> <scheme> exit=<n>`. N default 5.
  - `gt_log_append SCHEME EXIT STEPS_JSON` and `gt_log_read N` in `lib/log.sh`.

- [ ] **Step 1:** `git -C ~/Developer/project-grove switch -c themes-gui`
- [ ] **Step 2: Failing tests:**
  - `list --json has every scheme's palette` — 6 keys; `dark-medium` → name `Dark Medium`, appearance `dark`, `colors.bg0` `#2D353B`, `colors.green` `#A7C080`; `light-soft` → appearance `light`, `colors.bg0` `#F3EAD3`; each `colors` has exactly the 13 keys (jq `keys`).
  - `set appends one log line`, `a failed render writes no log line` (exit 1 at step 1), `a set with a needs-you step logs exit 1 and its steps`.
  - `the log keeps the last 50` (write 55 sets with a stubbed step set, or append through `gt_log_append`).
  - `log --json lists newest first, 5 by default, -n 2 gives 2`; `log with no file is empty` (`{"entries": []}`).
  - `log skips a damaged line` (Review Focus 3) — append `{"time": "x"` and `garbage`, then a good line: `log --json` is valid JSON with only the good entries.
- [ ] **Step 3: Run** `zsh -lc 'cd ~/Developer/project-grove/grove-themes && bats tests'` — Expected: the new tests fail.
- [ ] **Step 4: Implement.** Palettes from `gt_values` per scheme (names from the scheme id: `dark-medium` → `Dark Medium`). `cmd_set` calls `gt_log_append` after step 1 succeeded, with the same steps JSON it prints. Validating a line = it starts with `{"time": "` and ends with `]}`; `log` skips other lines.
- [ ] **Step 5: Run** the same plus `shellcheck` on the changed scripts — Expected: all pass, silent.
- [ ] **Step 6: Commit** `grove-themes: palettes in list --json, a switch log, and grove-themes log`

---

### Task 2: Swift package and `GroveThemesCore`

**Files:**
- Create: `grove-themes/app/Package.swift`, `grove-themes/app/.gitignore` (`.build/`)
- Create: `grove-themes/app/Sources/GroveThemesCore/{Models.swift,CLI.swift,StatusText.swift,Hex.swift,StatePath.swift,ThemesModel.swift}`
- Create: `grove-themes/app/Tests/GroveThemesCoreTests/{ModelsTests.swift,ClientTests.swift,StatusTextTests.swift,ThemesModelTests.swift}` + `Fixtures/` with real CLI output (`list.json`, `set.json`, `set-needs-you.json`, `log.json`) captured from the stubbed bats setup, never from the real Mac
- Create: `grove-themes/app/Sources/GroveThemes/GroveThemesApp.swift` (a placeholder `MenuBarExtra` so the executable target builds; Task 3 replaces it)

**Interfaces:**
- Consumes: Task 1's JSON shapes.
- Produces (Task 3 uses exactly these):
  - `enum StepResult: String, Decodable { case live, nextPrompt = "next-prompt", nextLaunch = "next-launch", needsYou = "needs-you", failed }`
  - `struct Step: Decodable, Equatable { let name: String; let result: StepResult; let message: String }`
  - `struct Palette: Decodable, Equatable { let name: String; let appearance: String; let colors: [String: String] }`
  - `struct SchemeList: Decodable, Equatable { let current: String; let schemes: [String]; let palettes: [String: Palette] }`
  - `struct SwitchResult: Decodable, Equatable { let scheme: String; let steps: [Step] }`
  - `struct LogEntry: Decodable, Equatable { let time: Date; let scheme: String; let exit: Int; let steps: [Step] }` (ISO 8601 with offset)
  - `struct CLIOutput { let status: Int32; let stdout: Data; let stderr: String }`
  - `protocol CLIRunner: Sendable { func run(_ arguments: [String]) async throws -> CLIOutput }`; `struct ProcessRunner: CLIRunner { init(path: URL) }` (throws `CLIError.notInstalled` when the file isn't executable)
  - `enum CLIError: Error, Equatable { case notInstalled(String); case unreadable(String); case usage(String) }` with `var message: String` = "grove-themes isn't installed. Run grove install." / "grove-themes gave an answer the app couldn't read: <first line>" / the stderr text
  - `struct GroveThemesClient { init(runner: CLIRunner); func list() async throws -> SchemeList; func set(_ scheme: String) async throws -> (SwitchResult, exit: Int32); func log(limit: Int) async throws -> [LogEntry] }` — exit 2 → `.usage(stderr)`; non-JSON stdout → `.unreadable`
  - `enum StatusText { static func line(for entry: LogEntry, now: Date, calendar: Calendar) -> String; static func chips(for entry: LogEntry) -> [Chip] }`, `struct Chip: Equatable { let text: String; let kind: StepResult; let message: String }` — per Ruling P1
  - `enum Hex { static func rgb(_ hex: String) -> (red: Double, green: Double, blue: Double)? }` (0–1)
  - `enum StatePath { static func url(environment: [String: String], home: URL) -> URL }`
  - `@MainActor @Observable final class ThemesModel { init(client: GroveThemesClient); var list: SchemeList?; var log: [LogEntry]; var busyScheme: String?; var error: CLIError?; func refresh() async; func switchTo(_ scheme: String) async }`

- [ ] **Step 1: Failing tests** (Swift Testing):
  - Models: decode each fixture; `LogEntry.time` parses `2026-11-10T13:10:04+00:00`; unknown `result` fails decoding.
  - Client (fake runner): `list` returns the fixture; exit 2 → `.usage("grove-themes: unknown scheme…")`; `"not json"` → `.unreadable("not json")`; `ProcessRunner(path:)` on a missing file → `.notInstalled`.
  - StatusText: fixture `set.json` steps at 13:10 same day → `"Switched to Dark Medium at 13:10 · 10 updated now, yazi next launch"`; a needs-you appearance step → line ends `… · appearance needs you`; the day before → `"Switched to Dark Medium on 9 Nov at 13:10 · …"` (Review Focus 4; fixed `TimeZone(identifier: "UTC")` calendar, `en_GB` style day-month); chips: `10 now` (live), `yazi next launch`, `needs you: appearance` with its message.
  - Hex: `#2D353B` → (45/255, 53/255, 59/255); `2D353B`, `#XYZ`, `` → nil.
  - StatePath: `GROVE_STATE=/tmp/s` → `/tmp/s/theme`; unset → `<home>/.local/state/grove/theme`.
  - ThemesModel: `refresh` loads list and log; with a runner that fails as not-installed, `error == .notInstalled`, then after the runner succeeds a second `refresh` clears `error` (Review Focus 1); `switchTo` sets `busyScheme` during the call and clears it after, and refreshes; a second `switchTo` while busy runs nothing (count runner calls; Review Focus 2); a log JSON where one entry has an unknown step result shows the other entries (Review Focus 3: `log(limit:)` decodes entries one by one and drops only the bad one).
- [ ] **Step 2: Run** `zsh -lc 'cd ~/Developer/project-grove/grove-themes/app && swift test'` — Expected: fails to compile (types missing).
- [ ] **Step 3: Implement** the Core types and the placeholder app; `ProcessRunner` runs the CLI with `Process`, collects stdout/stderr, and passes the environment through plus `GROVE_STATE` if set.
- [ ] **Step 4: Run** `swift test` and `swift build -c release` — Expected: all tests pass; build completes with no warnings.
- [ ] **Step 5: Commit** `grove-themes app: the Core library (models, CLI client, status text, state model)`

---

### Task 3: The SwiftUI dropdown and gallery

**Files:**
- Create: `grove-themes/app/Sources/GroveThemes/{GroveThemesApp.swift (replace),Theme.swift,PineShape.swift,DropdownView.swift,SchemeTile.swift,GalleryView.swift,SchemeCard.swift,LogView.swift,StateWatcher.swift}`
- Test: `grove-themes/app/Tests/GroveThemesCoreTests/ThemeColorsTests.swift` (the palette → colour mapping lives in Core as `ThemeColors`)

**Interfaces:**
- Consumes: Task 2's Core (all of it).
- Produces: `struct ThemeColors: Equatable { init?(palette: Palette); let bg0, bg1, bg2, bg3, fg, grey1, red, orange, yellow, green, aqua, blue, purple: RGB }` in Core (`RGB` = the `Hex.rgb` tuple as a struct); `ViewModifier SchemeNameStyle` in the app (12 pt JetBrains Mono, regular, fg at 0.75), used by both the dropdown's current-scheme line and the card names.

- [ ] **Step 1: Failing test** `ThemeColors maps every palette colour` — from the list fixture's `dark-medium` palette, `bg0` = (45,53,59)/255, `green` = (167,192,128)/255; a palette missing `bg3` → nil.
- [ ] **Step 2: Run** `swift test` — Expected: fails (type missing).
- [ ] **Step 3: Implement** `ThemeColors`, then the views per spec §5:
  - `GroveThemesApp`: `MenuBarExtra` (label: `PineShape` rendered to a template `NSImage`, 16 pt) with `.menuBarExtraStyle(.window)` → `DropdownView`; `Window("Grove Themes", id: "gallery")` → `GalleryView`; one shared `ThemesModel` with `ProcessRunner(path:)` from `GROVE_THEMES_CLI` or `~/.local/bin/grove-themes`; `StateWatcher` on `StatePath.url` calls `model.refresh()` on change; `DropdownView.onAppear` calls `refresh()`.
  - `DropdownView`: header (pine in green, "Grove Themes" bold 15 pt, current name with `SchemeNameStyle`), "DARK"/"LIGHT" labels (10 pt, tracking 0.8, grey1), `SchemeTile` × 3 per row, status line from the newest log entry (`StatusText.line`; needs-you/failed parts in red), "Open Grove Themes…" (`openWindow(id: "gallery")`, `NSApp.activate`), "Quit". Width 320.
  - `SchemeTile`: rounded 8, its own bg0, "Aa" 15 pt semibold in its fg, five dots (red yellow green aqua blue), contrast label 10.5 pt; current → 2 pt border in the current scheme's green + "✓"; `busyScheme == id` → `ProgressView` small; disabled while any switch runs.
  - `GalleryView`: 760 × 560 default, background bg0, `SchemeCard` 3 × 2 grid, `LogView` under it.
  - `SchemeCard`: a mini desktop (its bg0, lockup "Project Grove" in Courier-style bold with the pine in its ink — `#DAC7A2` dark / `#27332A` light, a terminal snippet in its bg1 with aqua/green/yellow prompt), name with `SchemeNameStyle`, "● on" in green for the current one; click → `switchTo`.
  - `LogView`: the last 5 entries: time (`HH:mm`, or `d MMM HH:mm` for other days), scheme, `StatusText.chips` as capsules (live green, next-* yellow, needs-you/failed red); clicking a chip shows its message in a popover.
  - Error state: when `model.error` is set, the dropdown and gallery show `error.message` and tiles/cards are disabled.
  - `StateWatcher`: `DispatchSource.makeFileSystemObjectSource` on the state file's folder (the file may not exist yet), debounced 200 ms.
- [ ] **Step 4: Run** `swift test` and `swift build -c release` — Expected: pass, no warnings.
- [ ] **Step 5: Smoke run** (no real switching): `GROVE_THEMES_CLI=/usr/bin/false .build/release/GroveThemes & sleep 3; kill %1` — Expected: it starts and stays up until killed (the error state handles the failing CLI). Note in the report that the visual check is the user's (Task 5).
- [ ] **Step 6: Commit** `grove-themes app: menu bar dropdown and gallery window in the current scheme`

---

### Task 4: Module `97-themes-app`

**Files:**
- Create: `grove-dotfiles/modules/97-themes-app/module.sh`, `grove-themes/app/Resources/{AppIcon.png,Info.plist}`, `grove-dotfiles/tests/modules_themes_app.bats`
- Modify: `grove-dotfiles/README.md` (row after 95-vscode: `` | `97-themes-app` | Grove Themes in the menu bar: builds the app, installs it to ~/Applications and starts it at login | ``), `grove-themes/README.md` (the app)
- `AppIcon.png`: the icon cut from the Project Grove branding board (288 × 288, rounded, from the branding board — approved by the user for the repo)

**Interfaces:**
- Consumes: the Swift package (Tasks 2–3), `Info.plist` with `CFBundleIdentifier com.projectgrove.themes`, `CFBundleName Grove Themes`, `CFBundleExecutable GroveThemes`, `CFBundleIconFile AppIcon`, `LSUIElement true`, `LSMinimumSystemVersion 14.0`, `CFBundleShortVersionString 1.0`.
- Produces: `about` = `Grove Themes in the menu bar`; seams `GROVE_SWIFT` (default `swift`), `GROVE_LAUNCHCTL` (`launchctl`), `GROVE_CODESIGN` (`codesign`), `GROVE_APPS_DIR` (`$HOME/Applications`), `GROVE_AGENTS_DIR` (`$HOME/Library/LaunchAgents`); `_ta_source_hash` (sorted `git ls-files` under the app source, `shasum`), `_ta_agent_plist` (prints the agent XML: Label, ProgramArguments = the app's `Contents/MacOS/GroveThemes`, RunAtLoad true, ProcessType Interactive).

- [ ] **Step 1: Failing tests** (fakes for `swift` (creates `.build/release/GroveThemes`), `codesign`, `iconutil`, `sips`, `launchctl` (logs args; `print` succeeds only when a marker file exists)):
  - `themes-app: about names it`; `failed without swift`; `needs work when the app is missing`; `needs work when the source changed` (stamp differs); `needs work when the agent isn't loaded`; `ok when built, current and loaded`; check changes nothing (`find` before/after).
  - `apply builds, assembles, signs, installs and loads` — bundle has `Contents/MacOS/GroveThemes`, `Contents/Info.plist` (plutil: bundle id, `LSUIElement` true), `Contents/Resources/AppIcon.icns`; `codesign --force --sign -` called on the bundle; stamp = current hash; agent file equals `_ta_agent_plist`; `launchctl bootstrap gui/<uid> <agent>` called; then check is ok.
  - `apply restarts a running app` — when loaded, `launchctl kickstart -k gui/<uid>/com.projectgrove.themes` is called (Review Focus 5).
  - `a failed build leaves the installed app and stamp` (Review Focus 5) — fake `swift` exits 1 with an error line → apply returns 1, output shows the line, installed bundle and stamp unchanged.
  - `the README lists the module`.
  - `swift test passes` — skipped unless `command -v swift`; runs `swift test` in the package (no app launch).
- [ ] **Step 2: Run** `zsh -lc 'cd ~/Developer/project-grove/grove-dotfiles && bats tests/modules_themes_app.bats'` — Expected: fail.
- [ ] **Step 3: Implement** per spec §6. The icon set: `sips -z` the PNG to 16, 32, 64, 128, 256, 512, 1024 into `AppIcon.iconset/icon_<n>x<n>[@2x].png`, then `iconutil -c icns`. Build into a temp copy of the bundle and `mv` it over the installed one only after signing succeeds.
- [ ] **Step 4: Run** `bats tests` (full grove-dotfiles suite) and `shellcheck modules/97-themes-app/module.sh` — Expected: all pass, silent.
- [ ] **Step 5: Commit** `97-themes-app: build Grove Themes, install it and start it at login`

---

### Task 5: Live on this Mac (the user reviews before merge)

- [ ] **Step 1:** `zsh -lc 'grove install 97-themes-app'`, then `grove check` — Expected: all ok; the tree is in the menu bar; `launchctl print gui/$(id -u)/com.projectgrove.themes` shows it running.
- [ ] **Step 2:** One switch from the terminal (`grove-themes set dark-hard`, then `dark-medium`): `grove-themes log` shows both; the app's colours follow (the user confirms).
- [ ] **Step 3:** Hand over to the user: dropdown, gallery, switching from the app (expect macOS's Automation prompt for Grove Themes once), recolouring, the log and chips, the icon in Finder/Spotlight, and a log-out/in for the login start. Report rulings P1, P2 and any from the build. Wait for "merge it"; merge with `git branch -f main themes-gui` from the branch.
