# SketchyBar · the Grove top bar

**Status:** built 2026-11-11 (as shipped: §11 lists what changed from the first design)
**Builds on:** [2026-11-10-aerospace-design.md](2026-11-10-aerospace-design.md) (workspaces, gaps), [2026-11-10-grove-themes-design.md](2026-11-10-grove-themes-design.md) (templates, switch steps), [2026-11-10-grove-keys-design.md](2026-11-10-grove-keys-design.md) (the Grove Keys menu)
**Mockups:** `artifacts/sketchybar/mockups/` (private canvas https://claude.ai/artifact/6AgtzsESSmbThGs3CsqToE), style **B · Floating bar** chosen, on an opaque strip

## 1. Goal

A Grove top bar replaces the macOS menu bar. It's a floating rounded bar on an opaque strip in the desktop's colour, with the native menu bar hidden behind it. It shows the Grove tree, the AeroSpace workspaces, the front app's name, and the system status, all in the current scheme's colours.

**Success looks like this:**
- After `grove install`, the bar shows at login on every screen.
- The native menu bar never shows, not even its slide.
- Clicking a workspace switches to it, and switching with the keyboard updates the bar at once.
- `grove-themes set <scheme>` recolours the bar live.
- The network item opens a popup with per-interface totals and the top apps.
- `grove check` reports `99-sketchybar` ok.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Engine | SketchyBar (`felixkratz/formulae` tap, trusted by grove) | Chosen by the user. |
| Config language | Shell (`sketchybarrc` + bash plugins) | Matches grove's bash and bats; no SbarLua dependency. |
| Style | B: one floating rounded bar, inset 8 pt, on a full-width opaque strip in bg0 | Chosen by the user: the strip hides the native menu bar's slide. |
| Native menu bar | Auto-hide "always", fully covered by the strip | The user's choice. |
| Reaching menus | Grove tree → Grove Themes; key glyph → Grove Keys' menu; app menus wait for the app-menu helper (roadmap item 4); ⌃F2 still opens the hidden menu bar | Chosen by the user. |
| Icons | SF Pro's SF Symbols (installed); text in JetBrains Mono | No new font. |
| Colours | Palette only, from a `colors.sh` template | The palette rule (tests enforce). |

## 3. Out of scope

- The app-menu dropdown (roadmap item 4).
- Other apps' menu bar icons (SketchyBar alias items, which are broken on macOS 26+).
- Per-screen layouts: every screen shows the same bar.

## 4. Pieces

```
grove-dotfiles/Brewfile                       + tap felixkratz/formulae, brew sketchybar
grove-dotfiles/config/sketchybar/sketchybarrc the bar and items (tracked, executable)
grove-dotfiles/config/sketchybar/plugins/*.sh one script per item (tracked)
grove-dotfiles/config/sketchybar/lib.sh       parsing and formatting helpers, sourced (tracked)
grove-dotfiles/config/sketchybar/colors.sh.tmpl  rendered by grove-themes → colors.sh (gitignored)
grove-dotfiles/modules/99-sketchybar/module.sh   install, start, menu bar auto-hide, checks
grove-dotfiles/config/aerospace/aerospace.base.toml  exec-on-workspace-change trigger; gaps.outer.top = 56
grove-themes/lib/steps.sh                     new switch step "bar": sketchybar --reload
grove-keys/app                                grovekeys://menu opens its menu bar menu
```

`~/.config/sketchybar` reaches the config through 05-config's link (`!/sketchybar/` in `config/.gitignore`, plus `/sketchybar/colors.sh`).

## 5. Look

- **Strip:** the bar window is full width and 48 pt tall, `color` = bg0, `topmost = window`, so it sits above the menu bar and hides its slide. `sticky = on`.
- **Floating bar:** 32 pt tall, inset 8 pt left, right and top, corner radius 10, bg0 fill with a 1 pt bg3 border (as mockup B). It's drawn as a background bracket behind all items, or as `bar` margins plus a background on the item groups, whichever SketchyBar draws cleanly. The plan's first task settles this with a spike.
- **Text:** JetBrains Mono 13; values in fg, labels in the mockup's accents (cpu/mem aqua, ↓ blue, ↑ orange, battery green, Wi-Fi blue, volume yellow).
- **Workspaces:** 22×20 pills, radius 5; the focused one has a green fill with bg0 text, the others grey2 text.
- **Front app:** after a bg3 `│` separator, the app's name in fg, semibold.
- **Notch:** the built-in screen's notch covers the middle of the bar. No item is placed there (left items grow rightward, right items leftward).
- **AeroSpace:** `gaps.outer.top = 56` (48 + 8), so tiles start below the strip.

## 6. Items

| Item | Shows | Source | Updates |
| --- | --- | --- | --- |
| `grove` | pine glyph, green | static | click: `open -b com.projectgrove.themes` |
| `workspaces` | the numbers in use; the focused one as a pill | `aerospace list-workspaces --monitor all --empty no`; `--focused` | `aerospace_workspace_change` trigger; every 30 s; click: `aerospace workspace N` |
| `front_app` | the app's name | `front_app_switched` event (`$INFO`) | on the event |
| `system` | `cpu 12%  mem 48%` | `top -l 1 -n 0` (CPU idle → used); `vm_stat` + `sysctl hw.memsize` (used = active + wired + compressed) | 4 s |
| `network` | `↓ 1.2 MB/s  ↑ 84 KB/s` | `netstat -ibn` byte counters of the default-route interface (`route -n get default`), delta ÷ interval | 2 s |
| `network.popup` | every interface's totals since boot; the top 5 apps by bytes | `netstat -ibn`; `nettop -P -L 1 -x -J bytes_in,bytes_out` | while open (click toggles) |
| `battery` | the level, with a charging mark | `pmset -g batt` | 60 s, `power_source_change` |
| `wifi` | the SSID, `off`, or `—` | `ipconfig getsummary en0` | `wifi_change`, 60 s |
| `volume` | `vol 60%` / `mute` | `volume_change` event (`$INFO`); mute from `osascript -e 'output muted of (get volume settings)'` | on the event |
| `clock` | `Tue 11 Nov  14:32` | `date '+%a %-d %b  %H:%M'` | 10 s |
| `keys` | key glyph, grey; orange when Grove Keys needs attention | `$GROVE_STATE/keys.json` (any false) | 30 s; click: `open grovekeys://menu` |

- Formats: rates as `B/s` under 1 KB, `KB/s` with no decimals under 1 MB, `MB/s` with one decimal. Percentages are integers.
- Every plugin sources `lib.sh` and `colors.sh`, computes its text with `lib.sh` functions, then makes one `sketchybar --set` call.

## 7. Grove Themes and Grove Keys

- **grove-themes:** `colors.sh.tmpl` exports `BG0`, `BG1`, `BG3`, `FG`, `GREY2`, `GREEN`, `AQUA`, `BLUE`, `ORANGE`, `YELLOW`, `RED` as `0xffRRGGBB` (the `_argb` values). A new switch step, `bar`, runs after `borders`: `sketchybar --reload` when SketchyBar is running (live), otherwise `next-launch`.
- **Grove Keys:** registers the URL scheme `grovekeys` (Info.plist `CFBundleURLTypes`, written by module 96). `grovekeys://menu` opens its menu bar menu at the pointer (an `NSMenu` built from the same items). Any other path is ignored. The URL parsing is a tested Core function.

## 8. grove module `99-sketchybar`

- `apply`:
  1. `brew trust felixkratz/formulae` if it isn't trusted yet, then `brew install sketchybar` (through the Brewfile).
  2. `defaults write NSGlobalDomain _HIHideMenuBar -bool true`, then restart the SystemUIServer.
  3. `brew services start sketchybar`.
  4. Render colours through grove-themes if `colors.sh` is missing.
- `check` reports needs-work, each with its own message, for:
  - the tap untrusted;
  - SketchyBar not installed;
  - the service not running;
  - the config link missing;
  - `colors.sh` missing or not matching the current scheme;
  - menu bar auto-hide off;
  - the AeroSpace trigger or the 56 pt top gap missing.
- Tests use fakes for `brew`, `sketchybar`, `defaults` and `killall`, as the other modules do.

## 9. Errors

| Situation | What happens |
| --- | --- |
| A source fails or returns something unexpected | The item shows `—`; the bar keeps running. |
| AeroSpace not running | The workspaces item is empty. |
| No battery | The battery item is hidden. |
| No default route | `↓ —  ↑ —`; the popup still lists interfaces. |
| `nettop` takes more than 2 s | The popup shows totals and "top apps unavailable". |
| A theme switch while SketchyBar is stopped | The `bar` step says next-launch. |

## 10. Testing

- **bats, `lib.sh`** (recorded command outputs as fixtures):
  - the rate format (B/KB/MB, rounding);
  - CPU from `top`, memory from `vm_stat`;
  - `pmset` (charging, battery, none);
  - SSID from `ipconfig` (connected, off);
  - `nettop` top 5;
  - `netstat` totals;
  - the workspace list (none, one, many).
- **bats, config:** `bash -n` and shellcheck on `sketchybarrc`, the plugins and `lib.sh`; no `0x…` colour literal outside `colors.sh`; `colors.sh` renders for all six schemes with palette values only; `aerospace.base.toml` has the trigger and `gaps.outer.top = 56`.
- **bats, module 99:** apply and check with fakes; the config allowlist.
- **bats, grove-themes:** the `bar` step reloads when SketchyBar is running and says next-launch when it isn't.
- **Swift, Grove Keys:** `grovekeys://menu` is recognised; other URLs are ignored.
- **By hand, with the user:**
  - The look against mockup B, and the native menu bar never showing.
  - Clicks on each item.
  - A scheme switch recolouring the bar.
  - The notch.
  - Workspace switches from the keyboard.
  - The network popup.
  - Logging out and back in.

## 11. As shipped (changes made while building, with the user)

- **Strip level:** `topmost=on`. `topmost=window` sat below the menu bar.
- **Top gap:** windows start where the 48 pt strip ends, 8 pt below the floating bar: `gaps.outer.top = [{ monitor."built-in" = 11 }, 48]`. The built-in screen keeps 37.5 pt for the notch even when the menu bar hides.
- **AeroSpace:** also triggers the bar from `on-focus-changed`, so moving a window or a pinned app opening refreshes the workspaces.
- **Items:** `system` became `cpu` + `mem`, and `network` became `net.down` + `net.up` (one item can't colour two labels).
- **Separators:**
  - Bg3 bars `sep.*`: one between the tree and the workspaces.
  - Between each right-side group, and left of cpu.
- **Values:**
  - Fixed label widths, so the separators never move; numbers are right-aligned.
  - Compact rates (`2K`, `1.2M`).
  - `bat 81%`: green while charging, yellow under 20%, red under 10%.
  - cpu and mem turn yellow above 70% and red above 90%.
- **CPU source:** the last of two 1 s `iostat` samples. `top`'s single sample reads high.
- **Connection:** the `wifi` slot shows `wifi`, `eth`, `vpn` or `off`. macOS redacts Wi-Fi names from command-line tools without Location permission.
- **Hover:** clickable items (tree, network, clock, ⌘) light a bg1 background. The tree's pine is its icon image (`pine-dark.png` / `pine-light.png`).
- **Clock:** a click opens this month's calendar (`cal`) as a popup.
- **Reloads:** volume and the front app fill in after a reload (`osascript` volume, `lsappinfo`).
- **Hangs:** every slow source runs under a 2–3 s limit (`sb_timeout`).
- **Install:** SketchyBar isn't in the Brewfile, because `brew bundle` refuses untrusted taps. Module 99 trusts the tap and installs it.
