# SketchyBar Top Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Grove top bar: SketchyBar, a floating rounded bar on an opaque bg0 strip that hides the native menu bar, with workspaces, the front app, system status and a network popup. It's themed by grove-themes, installed and checked by grove.

**Architecture:** The tracked shell config is `sketchybarrc`, with plugins and a sourced `lib.sh` holding every parser and formatter. It reads colours from a grove-themes template. AeroSpace triggers workspace updates. Module `99-sketchybar` installs SketchyBar, starts it and hides the menu bar. Grove Keys gains a `grovekeys://menu` URL.

**Tech Stack:** SketchyBar (`felixkratz/formulae`), bash, bats, shellcheck, Swift (Grove Keys).

**Spec:** `grove-dotfiles/docs/specs/2026-11-11-sketchybar-design.md`. Mockups: a private mock-up page (style B).

## Global Constraints

- Work on branch `sketchybar`; merge only on "merge it". Never commit the private working folders.
- Strip 48 pt, bg0, `topmost=window`, `sticky=on`. Bar 32 pt, inset 8 pt, radius 10, bg0 fill, 1 pt bg3 border. AeroSpace `gaps.outer.top = 56`.
- Text JetBrains Mono 13. Icons from SF Pro's SF Symbols. Colours only from `colors.sh` (`0xffRRGGBB`, the `_argb` values).
- Rates: `B/s` under 1 KB, `KB/s` with no decimals under 1 MB, `MB/s` with one decimal. Percentages are integers. A failed or garbled source shows `—`.
- Clock format `%a %-d %b  %H:%M` (two spaces).
- `~/.config` links into this checkout, so the live bar reads the working tree. Tests never run the real `sketchybar`, `brew`, `defaults`, `aerospace` or `killall`.
- Never run grove-themes and grove-dotfiles bats files in one call. The grove-dotfiles full suite takes ~12 min (background).

## Review Focus

- **Interface changes** (Wi-Fi to Ethernet, VPN up): the network rate must not show a huge spike or a negative number. Test in Task 1: a counter that goes down, or an interface that changes, gives `—` for one interval.
- **A workspace switch** from the keyboard, the mouse or a window move: the bar updates within the trigger, not 30 s later. Checked by hand in Task 7. Task 4's test covers the trigger line.
- **A scheme switch while a popup is open:** the reload must not leave a stale popup. Checked by hand in Task 7.
- **Plugins under SketchyBar's minimal PATH:** every plugin must use absolute paths or set PATH (`/opt/homebrew/bin` for `aerospace`). Test in Task 2: run each plugin under `env -i` with fakes.
- **macOS `top` / `vm_stat` output on other locales:** decimal comma. Test in Task 1 with a comma-decimal fixture.

---

### Task 0: Spike: install SketchyBar and draw the floating bar on its strip

- [ ] **Step 1: Confirm with the user** before touching the Mac. Then run `brew tap felixkratz/formulae`, `brew trust felixkratz/formulae` and `brew install sketchybar`. Don't start the service.
- [ ] **Step 2:** Write a throwaway config in the scratchpad: the strip and bar per Global Constraints, with three dummy items left and three right. Try (a) one bracket background behind all items, and (b) bar margins with a bar background over the strip. Run `sketchybar --config <scratch>/sketchybarrc` for each, and ask the user to look.
- [ ] **Step 3:** With menu bar auto-hide on (`defaults write NSGlobalDomain _HIHideMenuBar -bool true; killall SystemUIServer`), confirm the native menu bar's reveal stays hidden behind the strip.
- [ ] **Step 4:** Record what worked in the private notes. Quit the spike bar. If neither drawing works, stop and bring the options to the user.

### Task 1: `lib.sh`, parsers and formatters

**Files:** Create `grove-dotfiles/config/sketchybar/lib.sh`, `grove-dotfiles/tests/sketchybar_lib.bats` and fixtures in `grove-dotfiles/tests/fixtures/sketchybar/` (`top.txt`, `top-comma.txt`, `vm_stat.txt`, `pmset-charging.txt`, `pmset-battery.txt`, `pmset-none.txt`, `ipconfig-wifi.txt`, `ipconfig-off.txt`, `netstat.txt`, `nettop.csv`, `workspaces.txt`), recorded from this Mac.

**Interfaces** (all read from stdin or arguments and print to stdout; on bad input they print `—`):
- `sb_rate BYTES_PER_SEC` prints `512 B/s`, `84 KB/s` or `1.2 MB/s`.
- `sb_rate_delta OLD NEW SECONDS` prints the rate, or `—` when NEW < OLD or an argument is empty.
- `sb_cpu < top` prints the used percentage (100 − idle).
- `sb_mem MEMSIZE < vm_stat` prints the used percentage (active + wired + compressed pages × page size).
- `sb_battery < pmset` prints `87% charging`, `87%` or nothing (no battery).
- `sb_ssid < ipconfig` prints the SSID, or `off`.
- `sb_iface_bytes IFACE < netstat` prints `IN OUT` (the first `<Link#…>` row).
- `sb_totals < netstat` prints one `iface in out` line per interface with traffic.
- `sb_top_apps N < nettop-csv` prints the N largest `app in out` by in + out.
- `sb_workspaces < aerospace-list` prints the numbers, space-separated.

- [ ] **Step 1: Write the failing tests:** each function on its fixtures, plus the edges: zero, exactly 1024 → `1 KB/s`, 1 048 576 → `1.0 MB/s`, a negative delta → `—`, a comma decimal, no battery, Wi-Fi off, an empty workspace list.
- [ ] **Step 2: Run** `bats tests/sketchybar_lib.bats` → FAIL. **Step 3: Implement** in POSIX-ish bash with awk. **Step 4: Run** → PASS, and shellcheck is clean.
- [ ] **Step 5: Commit** `grove-dotfiles: sketchybar lib`.

### Task 2: `colors.sh.tmpl`, `sketchybarrc` and the plugins

**Files:**
- Create in `grove-dotfiles/config/sketchybar/`: `colors.sh.tmpl`, `sketchybarrc`, and in `plugins/` the scripts `workspaces.sh`, `front_app.sh`, `system.sh`, `network.sh`, `network_popup.sh`, `battery.sh`, `wifi.sh`, `volume.sh`, `clock.sh` and `keys.sh`.
- Modify `grove-dotfiles/config/.gitignore` (`!/sketchybar/` and `/sketchybar/colors.sh`).
- Modify `grove-dotfiles/tests/templates.bats` (the generated list gains `sketchybar/colors.sh`) and its Dark Medium fixture.
- Test: `grove-dotfiles/tests/sketchybar_config.bats`.

**Interfaces:**
- `colors.sh` exports `BG0 BG1 BG3 FG GREY2 GREEN AQUA BLUE ORANGE YELLOW RED`.
- Item names: `grove workspaces front_app system network battery wifi volume clock keys`, laid out as in spec §5–§6 with the drawing method from Task 0.
- Each plugin sets `PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`, sources `lib.sh` and `colors.sh` from `$CONFIG_DIR`, and runs one `sketchybar --set "$NAME" …`. `$SKETCHYBAR_BIN` (default `sketchybar`) is the seam tests replace.
- The network item keeps its last counters in `$TMPDIR/grove-sketchybar-net`.

- [ ] **Step 1: Write the failing tests:**
  - `bash -n` and shellcheck on every file.
  - No `0x…` literal outside `colors.sh.tmpl`.
  - The items are declared in this order: left `grove workspaces front_app`, right `keys clock volume wifi battery network system`.
  - Each plugin, under `env -i HOME=… CONFIG_DIR=… NAME=… SKETCHYBAR_BIN=<fake>` with faked sources, makes exactly one `--set` call with the expected label. Cover a normal case and a failing source (`—`).
  - `colors.sh` renders for six schemes, and the templates suite includes it.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS, and templates.bats passes.
- [ ] **Step 5: Commit** `grove-dotfiles: sketchybar config`.

### Task 3: grove-themes `bar` step

**Files:** Modify `grove-themes/lib/steps.sh` (`gt_step_bar`) and `bin/grove-themes` (`set` runs it after `borders`), and the README. Test: `grove-themes/tests/set.bats`.

- [ ] **Step 1: Write the failing tests:**
  - `set reloads sketchybar when it runs` (`ps` fake lists `sketchybar`; a `sketchybar` stub records `--reload`; the step is live).
  - `set says next-launch for the bar when sketchybar isn't running`.
  - The existing `set` tests stay green with the new step line.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (detect with `$GROVE_PS -axo comm=`, like Ghostty). **Step 4: Run** the full grove-themes suite → PASS.
- [ ] **Step 5: Commit** `grove-themes: bar step`.

### Task 4: AeroSpace trigger and top gap

**Files:** Modify `grove-dotfiles/config/aerospace/aerospace.base.toml`: `exec-on-workspace-change = ['/bin/bash', '-c', '/opt/homebrew/bin/sketchybar --trigger aerospace_workspace_change FOCUSED=$AEROSPACE_FOCUSED_WORKSPACE']` and `gaps.outer.top = 56`. Update its fixture and `tests/aerospace_config.bats`.

- [ ] **Step 1:** Write the failing tests (the trigger line exactly as above, top gap 56). **Step 2:** Run → FAIL. **Step 3:** Implement, re-render the live `aerospace.toml` (`GroveKeys --render-aerospace`) and check with `aerospace reload-config --dry-run`. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `grove-dotfiles: aerospace triggers the bar`.

### Task 5: Grove Keys `grovekeys://menu`

**Files:**
- Create `grove-keys/app/Sources/GroveKeysCore/KeysURL.swift` (`enum KeysURL { case menu; init?(_ url: URL) }`).
- Modify the app: handle `NSAppleEventManager` / SwiftUI `onOpenURL`; on `.menu`, pop up its menu at the pointer.
- Modify `grove-dotfiles/modules/96-keys-app/module.sh` (Info.plist `CFBundleURLTypes` with scheme `grovekeys`).
- Test: `KeysURLTests.swift` and `modules_keys_app.bats` (the plist has the scheme).

- [ ] **Step 1: Write the failing tests:** `grovekeys://menu` gives `.menu`; `grovekeys://other`, `http://menu` and `grovekeys:` give nil. The bats test checks the plist holds `grovekeys`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` and the module bats → PASS.
- [ ] **Step 5: Commit** `grove-keys: grovekeys://menu`.

### Task 6: Module `99-sketchybar` and the Brewfile

**Files:** Create `grove-dotfiles/modules/99-sketchybar/module.sh` and `grove-dotfiles/tests/modules_sketchybar.bats`. Modify the Brewfile (`tap "felixkratz/formulae"`, `brew "felixkratz/formulae/sketchybar"`), the README module list and `config_allowlist.bats` if needed.

**Interfaces:** Seams `GROVE_BREW`, `GROVE_SKETCHYBAR`, `GROVE_DEFAULTS`, `GROVE_KILLALL`. Each `check` failure has its own message (spec §8).

- [ ] **Step 1: Write the failing tests:**
  - `about`.
  - `check` reports needs-work for: tap untrusted, not installed, service not running, config link missing, `colors.sh` stale, menu bar not auto-hidden, AeroSpace trigger missing.
  - `check` is ok when everything is set, and changes nothing.
  - `apply` trusts the tap, installs, sets the default, restarts SystemUIServer and starts the service. A failed install stops before the defaults write.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** following the 98-aerospace and 85 patterns. **Step 4: Run** the module bats, then the full grove-dotfiles suite in the background → all pass.
- [ ] **Step 5: Commit** `grove-dotfiles: module 99-sketchybar`.

### Task 7: Install and check by hand

- [ ] **Step 1:** `grove install sketchybar keys-app aerospace` (AeroSpace picks up the trigger with a reload). Then `grove check` → all ok.
- [ ] **Step 2: With the user:**
  - The look against mockup B, and the native menu bar never showing.
  - Every click: tree, workspaces, network popup, key.
  - Workspace switches from the keyboard (instant).
  - A scheme switch, with a popup open too.
  - The notch area.
  - Ethernet or VPN, if available.
  - Logging out and back in.
- [ ] **Step 3:** One fresh final review on the most capable model, then a fix pass. Copy the ledger to the private notes and wait for "merge it".
