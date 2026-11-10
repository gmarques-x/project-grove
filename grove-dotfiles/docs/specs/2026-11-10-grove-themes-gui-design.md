# grove-themes GUI · a menu bar dropdown and a gallery window for switching schemes

**Status:** design for review, 2026-11-10
**Builds on:** [2026-11-10-grove-themes-design.md](2026-11-10-grove-themes-design.md) (the CLI this app drives; its §6 `--json` and §7 steps)

## 1. Goal

A small native Mac app, Grove Themes, puts the six Everforest schemes one click away. A tree icon in the menu bar opens a dropdown of six scheme tiles; "Open Grove Themes…" opens a gallery window with bigger previews. The app looks like Project Grove by wearing whichever scheme is on. All switching is done by the `grove-themes` CLI; the app only shows and asks.

**Success looks like this:**
- After `grove install`, the tree is in the menu bar, and it's there again after logging out and in.
- One click on a tile switches the desktop, and the dropdown shows the result line ("Switched to Light Soft at 13:12 · 11 updated now, yazi next launch").
- The dropdown and the window recolour themselves to the new scheme, also when the switch was made from the terminal.
- The dropdown's status line shows the last switch, made from the app or the terminal, with any step that needs you or failed in red.
- `grove check` reports `97-themes-app` ok.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Shape | Menu bar dropdown + a window opened from it | Chosen by the user (first spec's interview). |
| Look | **Follows the scheme** ("look B"): the dropdown and window use the current scheme's colours (bg0, bg1, bg2, bg3, fg, grey1, the accents) and JetBrains Mono; the app recolours on every switch | Chosen by the user from three mockups (field-notes paper, follows the scheme, native macOS). |
| Window layout | **Gallery**: six scheme cards (3 × 2), each a small desktop, and nothing else (the log stays in the CLI: `grove-themes log`) | Chosen by the user over a list-and-preview layout. |
| App icon | The branding board's icon (paper square, camo pine, forest), cut from `Project_Grove_Branding.png` and committed as `grove-themes/app/Resources/AppIcon.png`; the large sizes are upscaled from its 288 px | Chosen by the user over a flat drawn tree. A higher-resolution original can replace the PNG later. |
| Menu bar icon | A small template pine (the logo's shape), so macOS draws it in the menu bar's own colour | Menu bar icons are monochrome by convention. |
| Start | At login, by a LaunchAgent grove writes; no Dock icon (`LSUIElement`) | Chosen by the user. |
| Build | Native SwiftUI, Swift package built from source by grove with the Command Line Tools' Swift (6.4, no Xcode), `MenuBarExtra` in `.window` style, macOS 14+ | Chosen by the user. A probe confirmed `swift build` builds a SwiftUI menu bar app and `swift test` runs Swift Testing on this Mac. |
| Logic boundary | The app never writes configs or settings; it runs the CLI and reads its JSON | One place does the switching; the app stays thin. |
| CLI path | `~/.local/bin/grove-themes` (70-zsh's link), overridable with `GROVE_THEMES_CLI` | A login agent has no shell `PATH`. |

## 3. Out of scope

- Following macOS appearance or a schedule (the first spec's decision stands).
- Settings, preferences or a scheme editor in the app.
- Notifications, keyboard shortcuts, a Dock icon.
- Distributing the app outside grove (notarisation, a DMG).

## 4. CLI additions (`grove-themes`)

- **`list --json` gains `palettes`**: an object keyed by scheme name, each `{"name": "Dark Medium", "appearance": "dark", "colors": {"bg0": "#2D353B", ...}}` with `bg0 bg1 bg2 bg3 fg grey1 red orange yellow green aqua blue purple`, from the palette files. `current` and `schemes` stay as they are.
- **Switch log:** every `set` that gets past step 1 appends one JSON line to `$GROVE_STATE/theme-log.jsonl`: `{"time": "<ISO 8601 local>", "scheme": "...", "exit": 0|1, "steps": [...]}` (the same steps as `set --json`). The file keeps the last 50 lines.
- **`grove-themes log [--json] [-n N]`** prints the last N (default 5) entries, newest first; `--json` gives `{"entries": [...]}`. A missing log is an empty list.
- bats tests for all three, stubbed like the rest of grove-themes' tests.

## 5. The app (`grove-themes/app/`)

A Swift package with two targets:

- **`GroveThemesCore`** (library, unit-tested): runs the CLI through a `CLIRunner` protocol (the real one uses `Process`; tests use a fake), decodes `list`, `set` and `log` JSON, turns step results into the status line and the log chips, and finds the state file to watch (`$GROVE_STATE/theme`, default `~/.local/state/grove/theme`).
- **`GroveThemes`** (executable, the SwiftUI app): `MenuBarExtra` with the dropdown, a `Window` scene for the gallery, a theme object that maps the current scheme's colours to SwiftUI colours, and a file watcher on the state file that reloads `list` and `log` when it changes (switches made in the terminal show up within a second).

**Dropdown** (about 320 pt wide): the pine, "Grove Themes" and the current scheme's name; two labelled rows (Dark, Light) of three tiles (Hard, Medium, Soft), each tile drawn in its scheme's bg0 with "Aa" in its fg and five accent dots; a tick and a green border on the current one. Clicking a tile runs `set <scheme> --json`: that tile shows a spinner and the others are disabled until it returns. Under the tiles, the status line of the last switch; a step that needs you or failed shows in red with its message. Then "Open Grove Themes…" and "Quit".

**Gallery window** (760 pt wide, sized to fit the cards, about 404 pt tall): seamless like Ghostty, no title bar or title, the scheme's bg0 up to the top edge with the window buttons over it in the top-left corner and the cards 28 pt lower to clear them; the window drags by any empty background. Six cards in a 3 × 2 grid, each a small desktop (the scheme's bg0 with the Grove lockup in its ink, and a terminal snippet in bg1 with prompt colours), the current one with a green border and "● on". Each card's scheme name is styled exactly like the dropdown's current-scheme line under "Grove Themes": the same size, regular weight, fg at 75% opacity (one shared text style in the code, so the two can't drift apart). Clicking a card switches, as in the dropdown. No log: the switch log is `grove-themes log`, and the dropdown keeps its status line.

**Errors:** no CLI at the path → the dropdown and window show "grove-themes isn't installed. Run grove install." and the tiles are disabled; unreadable JSON → "grove-themes gave an answer the app couldn't read" plus the first line of its output; `set` exit 1 → the switch is shown as done (the configs were written) with the failed steps in red; exit 2 → the message from stderr.

## 6. Module `97-themes-app`

`about`: "Grove Themes in the menu bar".

- **Paths:** source `$GROVE_ROOT/../grove-themes/app`; app `~/Applications/Grove Themes.app`; agent `~/Library/LaunchAgents/com.projectgrove.themes.plist` (label `com.projectgrove.themes`, runs the app's executable, `RunAtLoad` true); stamp `$GROVE_STATE/themes-app.stamp` holding a hash of the tracked source files (`git ls-files` under `app/`, sorted, `shasum`).
- **check:** `swift` missing → failed ("needs the Xcode command line tools"); app missing, or stamp ≠ current source hash → needs work; agent file missing or different from what grove would write → needs work; agent not loaded (`launchctl print gui/<uid>/com.projectgrove.themes` fails) → needs work; else ok. Changes nothing.
- **apply:** `swift build -c release` in the source; assemble the bundle (`Contents/MacOS/GroveThemes`, `Info.plist` with `CFBundleIdentifier com.projectgrove.themes`, `LSUIElement` true, `CFBundleIconFile AppIcon`; `AppIcon.icns` made from `AppIcon.png` with `sips` + `iconutil`); `codesign --force --sign -` (ad hoc); replace the installed app (quitting the running copy first); write the stamp; write the agent and `launchctl bootstrap` it (or `kickstart -k` if loaded). A failed build reports the compiler's last lines and leaves the installed app as it was.
- Tests (bats) fake `swift`, `codesign`, `iconutil`, `sips`, `launchctl` and point `HOME`/`GROVE_STATE` at temp folders; nothing touches the real Mac.

## 7. Testing

- **Swift Testing** (`swift test` in `grove-themes/app/`) for Core: decoding each JSON shape (including the palettes and a log with failed steps), the status-line text for live / next-launch / needs-you / failed mixes, the CLI-missing and bad-JSON errors (fake runner), and the state-file path.
- **bats** for the CLI additions (§4) and the module (§6), plus a test that `swift test` passes, skipped when `swift` isn't installed.
- **By hand** (Claude can't capture the screen): the user checks the dropdown, the gallery, the recolouring after a switch from the app and from the terminal, the login start, and the icon.

## 8. This Mac

Swift 6.4 (Command Line Tools) and JetBrains Mono are installed. The first switch from the app triggers macOS's Automation prompt for Grove Themes (it runs `osascript` through the CLI); allowing it once covers appearance and wallpaper.
