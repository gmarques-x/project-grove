# AeroSpace · a tiling desktop with pinned workspaces and scheme-coloured borders

**Status:** design for review, 2026-11-10
**Builds on:** [2026-11-10-grove-themes-design.md](2026-11-10-grove-themes-design.md) (templates, `set` steps)
**Comes before:** grove-keys (Hyper key, monitor bindings) and the SketchyBar top bar

## 1. Goal

AeroSpace becomes the core of the desktop. Every window tiles, each everyday app opens on its own numbered workspace, and the focused window wears a border in the current scheme's green. grove installs it, starts it at login and checks it; grove-themes recolours the borders on every switch.

**Success looks like this:**
- After `grove install` (and granting Accessibility once), AeroSpace is running and is running again after logging out and in.
- A new Ghostty window opens on workspace 1, Claude on 2, Chrome on 3, VS Code on 4, talk apps on 5, media apps on 6.
- Option+1–9 jumps between workspaces and Option+H/J/K/L moves focus between tiles.
- `grove-themes set light-soft` turns the focused border light-soft's green at once.
- `grove check` reports `98-aerospace` ok.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Tiling | Everything tiles, except the floating list in §4 | Chosen by the user. |
| Workspace names | `1`–`9`, nothing else | Simple shortcuts; how the bar labels them is the SketchyBar spec's call. |
| Empty workspaces | Not kept: no `persistent-workspaces`, so a workspace exists only while it has a window (or is focused) | The user wants the bar to show only workspaces in use. |
| Shortcuts | AeroSpace's Option set (§5) until grove-keys moves them to Hyper | Chosen by the user. Option+letter stops typing accents while AeroSpace runs. |
| Borders | JankyBorders, focused = green, others = bg3, following the scheme | Chosen by the user. |
| Start | AeroSpace's own `start-at-login = true`; it starts borders in `after-startup-command` | No LaunchAgent to keep; the two always run together. |
| Monitors | Every workspace on the main display | Per-Mac monitor bindings are grove-keys' job. |
| Mission Control | "Group windows by application" on (already is); "Displays have separate Spaces" off | AeroSpace's recommendations; the second needs one logout. |

## 3. Out of scope

- The Hyper key, monitor bindings and any shortcut editor (grove-keys).
- The bar and its workspace labels (SketchyBar).
- Theming AeroSpace itself (it has nothing to colour).

## 4. Workspaces and window rules

Rules match by app ID in `on-window-detected`, with `if.during-aerospace-startup = false` so windows already open when AeroSpace starts stay where they are. A rule for an app that isn't installed does nothing.

| Workspace | Apps (app ID) |
| --- | --- |
| 1 | Ghostty `com.mitchellh.ghostty` |
| 2 | Claude `com.anthropic.claudefordesktop` |
| 3 | Google Chrome `com.google.Chrome` |
| 4 | VS Code `com.microsoft.VSCode` |
| 5 | Messages `com.apple.MobileSMS`, FaceTime `com.apple.FaceTime`, Mail `com.apple.mail`, Slack `com.tinyspeck.slackmacgap`, Discord `com.hnc.Discord`, WhatsApp `net.whatsapp.WhatsApp`, Microsoft Teams `com.microsoft.teams2`, Telegram `ru.keepcoder.Telegram`, Signal `org.whispersystems.signal-desktop`, Zoom `us.zoom.xos` |
| 6 | Music `com.apple.Music`, Podcasts `com.apple.podcasts`, TV `com.apple.TV`, Spotify `com.spotify.client`, IINA `com.colliderli.iina`, VLC `org.videolan.vlc` |
| 7–9 | Free; unpinned apps (Safari included) open on the focused workspace |

**Floating:** System Settings `com.apple.systempreferences`, Grove Themes `com.projectgrove.themes`, Finder `com.apple.finder` (`layout floating`, matched at startup too). AeroSpace floats dialogs and sheets on its own.

## 5. The config (`grove-dotfiles/config/aerospace/aerospace.toml`)

Tracked and static; it reaches `~/.config/aerospace/aerospace.toml` through 05-config's `.config` link (add `!/aerospace/` to `config/.gitignore`).

- `start-at-login = true`; `after-startup-command = ['exec-and-forget /bin/sh ~/.config/borders/bordersrc']`.
- Gaps: 8 pt inner (horizontal and vertical) and 8 pt outer on every side. The top gap grows when SketchyBar arrives.
- Normalisations and the default layout (tiles, auto orientation) as AeroSpace ships them.
- Main-mode shortcuts:

| Shortcut | Command |
| --- | --- |
| Option+1…9 | `workspace 1`…`workspace 9` |
| Option+Shift+1…9 | `move-node-to-workspace 1`…`9` |
| Option+H/J/K/L | `focus left/down/up/right` |
| Option+Shift+H/J/K/L | `move left/down/up/right` |
| Option+− / Option+= | `resize smart -50` / `resize smart +50` |
| Option+/ | `layout tiles horizontal vertical` |
| Option+, | `layout accordion horizontal vertical` |
| Option+Tab | `workspace-back-and-forth` |
| Option+Shift+Tab | `move-workspace-to-monitor --wrap-around next` |
| Option+Shift+; | `mode service` |

- Service mode (Esc leaves it): `r` flatten-workspace-tree (reset the layout), `f` toggle floating/tiling, `Backspace` close all windows but the current, Option+Shift+H/J/K/L join with the neighbour; each then returns to main mode.

## 6. Borders

- **Template** `grove-dotfiles/config/borders/bordersrc.tmpl` renders to `config/borders/bordersrc` (gitignored, like the other generated files; `!/borders/` and `/borders/bordersrc` in `config/.gitignore`). It is a `/bin/sh` script with one line:
  `borders active_color={{green_argb}} inactive_color={{bg3_argb}} width=5.0 style=round hidpi=on`
  It is always run as `/bin/sh bordersrc`, so it needs no executable bit.
- **Renderer:** `gt_values` gains `<name>_argb` (`0xffRRGGBB`, upper-case hex) for each `#RRGGBB` palette entry, next to `<name>_rgb`.
- **grove-themes step `borders`**, after `yazi`: if a `borders` process is running (found through `GROVE_PS`, as the Ghostty step does), run `/bin/sh $GROVE_ROOT/config/borders/bordersrc`. A running borders takes the new arguments in place. Result `live` "recoloured"; not running → `live` "not running"; the script failing → `failed` "could not recolour the borders". The step's command is overridable with `GROVE_BORDERS_SH` for tests.

## 7. Module `98-aerospace`

`about`: "AeroSpace tiles the desktop".

- **Installs** come from the Brewfile (20-homebrew): `cask "nikitabobko/tap/aerospace"` and `brew "FelixKratz/formulae/borders"`.
- **check** (changes nothing):
  - `aerospace` or `borders` not on PATH → needs work.
  - `defaults read com.apple.spaces spans-displays` isn't 1 → needs work.
  - AeroSpace not running (no `AeroSpace.app` process in `ps`) → needs work.
  - Running, but `aerospace list-workspaces --focused` fails → needs you: "allow AeroSpace in System Settings > Privacy & Security > Accessibility". The plan's first task probes what the CLI really does without the permission, and adjusts this test to match.
  - Else ok.
- **apply:**
  - `defaults write com.apple.spaces spans-displays -bool true` when it isn't set, then say "log out once to finish the Spaces change".
  - `open -a AeroSpace` when it isn't running.
  - When Accessibility is missing, open that settings pane (`open x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) and return needs you.
- **Seams** for tests: `GROVE_PS`, plus `aerospace`, `defaults`, `open` and `borders` from PATH stubs.

## 8. Testing

- **bats, module:** fake `aerospace`, `borders`, `defaults`, `open` and `ps`, with `HOME` and `GROVE_STATE` in temp folders. Cover: not installed, Spaces setting off (check says needs work, apply writes it and says log out), not running (apply opens it), no Accessibility (needs you), all ok.
- **bats, grove-themes:** `_argb` values for one scheme; the rendered `bordersrc` for all six schemes (green and bg3 from each palette); the `borders` step running, not running and failing; `set` lists the step after `yazi`.
- **Config sanity:** a test that `aerospace.toml` parses (with `/usr/bin/python3 -I -c 'import tomllib'`), names workspaces only `1`–`9`, and has a rule for every app ID in §4.
- **By hand (the user):** tiling, the shortcuts, each pinned workspace, the floating apps, borders after a switch, and AeroSpace after a logout.

## 9. This Mac

MacBook Air, built-in display only. "Group windows by application" is already on; "Displays have separate Spaces" is on (the default) and gets turned off. Claude, Ghostty, Chrome, VS Code, Messages, FaceTime, Mail, Music, Podcasts and TV are installed.
