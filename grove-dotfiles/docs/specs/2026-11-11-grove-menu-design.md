# The Grove menu (Omarchy round A)

Date: 2026-11-11. Status: approved by the owner as "Omarchy round A" (items O1, O10, O21, O23, O22, O19 of the review's Omarchy proposals).

## Goal

One menu that reaches everything Grove can do, defined in a data file, shown two ways: the pine's dropdown for the mouse and a type-to-filter palette for the keyboard. Around it: a window that presents a command's output, a System submenu, an About screen with a version, a manual with a Learn submenu, and a searchable cheat sheet.

The idea is Omarchy's (its menu is one data file with a user extension file; every action is a script reachable from a hotkey, the menu and the CLI). Grove keeps what macOS already does well and wires it in rather than rebuilding it.

## 1. The menu file

`~/.config/grove/menu.toml` (tracked: `grove-dotfiles/config/grove/menu.toml`), then `~/.config/grove/menu.local.toml` (the owner's, git-ignored). The format is the TOML subset Grove Keys already parses (tables, strings, booleans, comments).

- A table is a row. Its dotted name is its id and its place in the tree: `[update.check]` is a child of `[update]`. Rows keep file order.
- Keys: `title`; one action of `run` (shell, quiet), `present` (shell, in the Grove window, §3), `open` (link or path), `builtin` (rows Grove Keys draws: `keys`, `global-menu`, `lock`); `checked` (a shell test: ✓ when it exits 0); `separator = true` (a line above the row); `hidden = true`; `icon` (an SF Symbol's name, drawn before a top-level row of the pine's menu; see the 2026-11-12 note in §2).
- A row with children is a submenu; its own action, if any, is ignored. A row with neither action nor children is left out.
- The local file: a table with a known id overrides that row key by key; a new id is appended to its parent (a missing parent is created with the id's last part as its title); `hidden = true` removes a row and its children.
- A file that can't be read or parsed: the tracked file falling back to a built-in minimal menu (Grove Themes, Grove Keys ▸, Global Menu ▸) and the error shown as a disabled first row; a broken local file is ignored with the same kind of row. The menu never fails to open.
- Shell commands run through `/bin/zsh -lc` (the login profile gives Homebrew and `~/.local/bin`), detached, with `GROVE_STATE` set. `checked` tests run when their submenu opens (and for the palette, when it opens), each with a 0.5 s limit, concurrently; a test that fails or times out is unchecked.

Initial tree: Appearance (Grove Themes…, the six schemes with ✓) · Grove Keys ▸ · Update (Check, Update Grove, Run the Installer) · Learn (Keybindings, The Grove Manual, AeroSpace, Ghostty, Yazi) · About · System (Lock, Sleep Display, Sleep, Log Out…, Restart…, Shut Down…) · Global Menu ▸.

## 2. Showing it (Grove Keys)

- **Pine menu:** `grovekeys://grove-menu` builds the NSMenu from the tree. The `keys` builtin is today's Grove Keys submenu (warnings, Open, Show Cheat Sheet, Pause/Resume, Restart when offered); `global-menu` is today's Global Menu submenu; `lock` locks the screen. Focus handling stays as it is (Grove Keys comes forward first; the previous app gets the keyboard back unless the row brought something forward: `open` and `present` rows and Open Grove Keys do).
- **Palette:** `grovekeys://palette` opens a centred floating panel: a text field and a list of every leaf row as "Appearance › Dark Medium", filtered as you type (case-insensitive, every typed word must appear in the path; rows whose title starts with the text first). ↑/↓ move, Return runs and closes, Escape closes, a click outside closes. ✓ shows for checked rows. Builtin submenus contribute their leaves where they are plain actions (the Grove Keys items); Global Menu is not in the palette. Looks like the cheat sheet's card (same fonts, `border` outline, scrim rules from the light-scheme round).
- **Deep link:** `grovekeys://menu/<id>` runs a leaf, or pops that submenu at the pointer.
- **Hotkeys:** shipped in `keys.toml`'s main mode as AeroSpace bindings, since AeroSpace already receives Hyper chords: `hyper-space = "exec-and-forget open grovekeys://palette"` and `hyper-k = "exec-and-forget open grovekeys://cheatsheet"`.
- The tree, the merge, the filter and the id lookup are pure code in GroveKeysCore with tests. Running rows and drawing are in the app target.

> **2026-11-11, later:** the palette was renamed the **Grove Launcher** (`grovekeys://launcher`; `grovekeys://palette` still answers). It moved from Hyper + Space to ⌘Space, taken in Grove Keys' key tap before Spotlight (`launcher = "cmd-space"` under `[hyper]` in `keys.toml`; the `hyper-space` binding is gone), and it gained the installed apps, ranked with the menu's rows once something is typed. The System submenu gained a first row, System Settings….

> **2026-11-12:** the pine's menu is no longer a native menu at the pointer. It is one of the bar's panels (`2026-11-12-bar-panels-design.md`, "Grove menu"): Grove's frame with the orange outline and JetBrains Mono, hung under the pine pill with its left edge on the pill's left outline, a submenu as a second panel beside the first. What changed here:
>
> - **Links.** `grovekeys://grove-menu` and `grovekeys://panel/grove` both show the panel or put it away. `grovekeys://menu/<id>` still runs a leaf; for a submenu it opens the panel under the pine with that submenu open (it was a native menu at the pointer). `grovekeys://menu` (Grove Keys' own items) and `grovekeys://app-menu` stay native menus at the pointer.
> - **Icons.** A row may have `icon = "<SF Symbol name>"`. The pine's menu draws it before a **top-level** row, quiet; rows inside a submenu have none, and neither has the launcher. The name must be one of Grove's icons (`GroveIcon.Name` in `GroveUI`: the seven the shipped rows use, `paintpalette`, `keyboard`, `arrow.triangle.2.circlepath`, `book`, `info.circle`, `power`, `menubar.rectangle`, and the bar panels' own, e.g. `wifi`, `calendar`, `display`); any other name draws no icon, and `GroveKeys --check-menu` fails on it and lists the names. A top-level row without an icon keeps the same indent, so the owner's own rows line up; `icon = ""` in `menu.local.toml` takes a shipped one away.
> - **Rows.** As before: file order, separators, hidden rows, an error in a file as a quiet first row (wrapped, it can't be chosen), the `keys` builtin as a submenu of Grove Keys' own items. `checked` tests now run when their level is shown (the top level at opening, a submenu's when it opens), each with the 0.5 s limit, all at once; the tick is green, at the row's right.
> - **Global Menu.** Still the front app's own menus, which only macOS can draw: its row shows a submenu's chevron, and choosing it (a click, → or Return) puts the panel away and pops the native Global Menu with its top-left corner where the panel's was.
> - **Pointer and keys.** A submenu opens after the pointer rests about 150 ms on its row, at once on a click, → or Return; it stays while the pointer moves toward it over other rows (300 ms of grace). ↑/↓ move (skipping lines and rows that can't be chosen, wrapping), Home/End go to the ends, Return or Space runs, a letter jumps to the next row starting with it, ← or Escape closes the submenu (Escape at the top level closes the menu). One highlighted row per level, shared by the pointer and the keys.
> - **Focus.** As before: the previous app keeps the keyboard unless the row brought something forward (`open` and `present` rows, Open Grove Keys, the cheat sheet). The panel never brings Grove Keys forward.

## 3. The Grove window: `grove present`

`grove present [--title T] <command…>` opens a new Ghostty window titled `Grove · <T>` (T defaults to the command's first word), which prints the Grove logo line, runs the command, then prints `Done` (green) or `Failed (N)` (red) and waits for a key before closing. AeroSpace floats and centres windows whose title starts with `Grove · ` (a rule in `aerospace.base.toml`). The window is its own Ghostty process that quits when its window closes, and it must not restore old windows or open a second one. Without Ghostty, the command runs in Terminal.app the same way.

## 4. System

Rows in the menu file; Lock is a builtin (the private `SACLockScreenImmediate`, falling back to `pmset displaysleepnow`). Log Out, Restart and Shut Down send loginwindow the events that show macOS's own confirmation dialog.

## 5. About and a version

`grove-dotfiles/VERSION` (starts at `0.9.0`; tags `vX.Y.Z` from now on). `grove --version` prints `grove X.Y.Z (<short commit>)`. `grove about` prints the fetch followed by: version and commit, the current scheme, the date of the last `grove update`/`install` run. The About row presents it.

## 6. Manual and Learn

`docs/manual/` at the repo root: `README.md` (contents) and short task chapters: Getting started, The desktop (workspaces, windows, the bar), The Grove menu, Themes, Hotkeys, The terminal, Updates and undo, Coming from stock macOS. Written for someone who has just installed Grove; each chapter says what to press or run, not how it's built. The top README is refreshed to today's state (six schemes, Grove Keys, the bar, the menu) and points at the manual. Learn rows open the manual on GitHub and the upstream docs.

## 7. Cheat sheet

`grovekeys://cheatsheet` toggles a searchable sheet (the hold-Caps-Lock overlay stays as it is): a text field filters the rows; Return on a row runs its binding's action where that is possible (launchers, AeroSpace commands via `aerospace <command>`), otherwise closes. Sections: Hyper (launchers and Hyper bindings), every AeroSpace mode from keys.toml, then fixed sections for the keys Grove relies on elsewhere: Ghostty (from `ghostty +list-keybinds`, read once per open), the shell (⌃R history, ⌃T files, ⌥C folders), and macOS (screenshots, emoji, dictation, Spotlight). Built after §2 since both add a panel to Grove Keys.

## Out of scope (later rounds)

Toggles and their bar indicators, Capture, Share, an Apps row, launch-or-focus for TUIs, `grove update` migrations, local override files for the other configs, third-party themes.

## Testing

- Core: menu parsing, merge with the local file, hidden rows, file order, error fallbacks, palette filter ranking, id lookup; cheat-sheet row building and filtering. Since 2026-11-12 also the `icon` key, the path to a row, and the menu list's pure parts (the keys' moves, type-to-jump, the hover timing, the rows' rectangles, a submenu's frame).
- Installer (bats): `grove present` builds the right Ghostty invocation (faked `open`), `grove --version`, `grove about`'s extra lines, the AeroSpace float rule, the shipped `menu.toml` parses (through the app's own parser: a `GroveKeys --check-menu <file>` one-shot, as `--render-aerospace` is), the two new key bindings.
- By hand: the pine menu, the palette, each System row up to macOS's confirmation, the Grove window floating and closing, the cheat sheet.
