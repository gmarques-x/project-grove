# Avatar Wallpapers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Six avatar wallpapers and a wallpaper choice (`grove` / `avatar`) in Grove Themes: CLI, wallpaper step, `85-macos-wallpaper`, gallery and dropdown.

**Architecture:** A private script renders the six PNGs. grove-themes keeps the choice in `$GROVE_STATE/wallpaper`, and the existing wallpaper step picks the file from it. A new `wallpaper` command saves the choice and runs only that step. The SwiftUI app adds a row like the logo row.

**Tech Stack:** Python 3 + Pillow + numpy + scipy (scratch venv, generator only), bash + bats, Swift 6 / SwiftUI with Swift Testing.

**Spec:** `grove-dotfiles/docs/specs/2026-11-11-avatar-wallpapers-design.md`

## Global Constraints

- Work on branch `avatar-wallpapers`; merge only on "merge it". Never commit the private working folders.
- Names exactly `grove` and `avatar`; state file `$GROVE_STATE/wallpaper`; missing, empty or unknown (after trimming whitespace) → `grove`.
- Files: `grove-wallpapers/wallpaper-avatar-<scheme>.png`, 2880×1864, drawing ≈ 820 px tall, centred on the scheme's bg0 (from `grove-dotfiles/theme/everforest-<scheme>`).
- With `grove` chosen, every existing behaviour and test result is unchanged.
- `--json` answers carry only JSON on stdout.
- Never run grove-themes and grove-dotfiles bats files in one call. The grove-dotfiles full suite takes ~12 min (background).

## Review Focus

- **A wallpaper switch while macOS Automation is refused:** the command reports needs-you and exits 1, but the choice is saved, so the next `set` uses it. Test in Task 3.
- **`grove check` after choosing the avatar:** `85-macos-wallpaper` must not report needs-work for the avatar file. Test in Task 2.
- **`set` to a scheme after choosing the avatar:** it applies `wallpaper-avatar-<that scheme>.png`. Test in Task 2.
- **An older app reading the new `list --json`, and the new app reading an older CLI:** both decode. Test in Task 4.
- **The gallery window's height** with two extra rows: everything stays visible without clipping. Checked by hand in Task 5.

---

### Task 1: The six avatar wallpapers (review gate)

**Files:** Create a private script (`wallpapers.py`) and `grove-wallpapers/wallpaper-avatar-{dark,light}-{hard,medium,soft}.png`.

- [ ] **Step 1:** Write `wallpapers.py`. It imports `make.py`'s recipe and renders the drawing's alpha and tone at SCALE 6 (sharp at about 820 px tall). Light schemes get the light recolour toward each scheme's bg0. Each drawing is centred on a 2880×1864 bg0 canvas. Save the PNGs, plus small previews kept privately.
- [ ] **Step 2: Review gate.** Show the user the dark-medium and light-medium previews and iterate. Don't start Task 2 until they approve.
- [ ] **Step 3:** Commit the six PNGs: `grove-wallpapers: avatar wallpapers`.

### Task 2: The choice, the wallpaper step and `85-macos-wallpaper`

**Files:** Modify `grove-themes/lib/steps.sh` (`gt_step_wallpaper`), `grove-themes/lib/render.sh` (`gt_wallpaper`, `gt_wallpapers`), `grove-dotfiles/modules/85-macos-wallpaper/module.sh` (`_wp_file`). Test: `grove-themes/tests/set.bats` and `render.bats`, `grove-dotfiles/tests/modules_wallpaper.bats`.

**Interfaces:**
- Produces: `gt_wallpaper` (prints `grove` or `avatar`, with the same trimming as `gt_logo`), `gt_wallpapers` (prints `grove avatar`), and `gt_step_wallpaper SCHEME` (uses `wallpaper-$(gt_wallpaper)-SCHEME.png`).

- [ ] **Step 1: Write the failing tests:**
  - `wallpaper choice defaults to grove; trims; unknown is grove` (render.bats).
  - `set puts the avatar wallpaper on every screen when chosen` (set.bats; dark-hard and light-soft).
  - `set keeps the grove wallpaper by default` (the existing tests stay green).
  - In modules_wallpaper.bats: `check expects the avatar file when chosen`, `the six avatar wallpapers are tracked`.
- [ ] **Step 2: Run** them and watch them fail. **Step 3: Implement.** **Step 4: Run** the touched bats files, then the full grove-themes suite → all pass.
- [ ] **Step 5: Commit** `grove-themes: wallpaper choice`.

### Task 3: `grove-themes wallpaper` and `list --json`

**Files:** Modify `grove-themes/bin/grove-themes` (usage, dispatch, `cmd_wallpaper`, `cmd_list`) and `grove-themes/README.md`. Test: `grove-themes/tests/cli.bats`.

**Interfaces:**
- `wallpaper` with no name prints the choice, or `{"wallpaper": "<name>"}` with `--json`.
- `wallpaper <name>`:
  1. Unknown name: usage, exit 2.
  2. If the file for the current scheme is missing: `wallpaper not found: <path>` on stderr, exit 1, nothing saved.
  3. Save the state atomically, then run `gt_step_wallpaper <current>`.
  4. Print the step's line as `set` does, or `{"wallpaper": "<name>", "steps": [{…}]}` with `--json`.
  5. Log the step (`gt_log_append <current> <rc> <step json>`).
  6. Exit 1 if the step failed or needs you.
- `list --json` adds `"wallpaper": "<name>", "wallpapers": ["grove", "avatar"]`.

- [ ] **Step 1: Write the failing tests:**
  - `wallpaper prints grove by default`.
  - `wallpaper avatar saves, runs osascript with the avatar file, logs a wallpaper step, --json prints only JSON`.
  - `wallpaper with a refused Automation exits 1, says needs-you and still saves the choice` (Review Focus).
  - `wallpaper when the file is missing exits 1 and saves nothing`.
  - `wallpaper bogus exits 2`.
  - `list --json carries wallpaper and wallpapers`.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement**, plus usage and README. **Step 4: Run** cli.bats, then the full grove-themes suite; check `shellcheck` is clean.
- [ ] **Step 5: Commit** `grove-themes: wallpaper command`.

### Task 4: The app's wallpaper row

**Files:**
- Modify Core: `Models.swift` (`SchemeList.wallpaper`, `.wallpapers` with defaults), `CLI.swift` (`setWallpaper(_:) async throws -> (SwitchResult-like steps, exit)`; reuse `SwitchResult` decoding with a `wallpaper` key, or a small `WallpaperResult { wallpaper, steps }`), `FocusGrid.swift` (`.wallpaper(String)` row between the logo row and the menu rows; same column rule; activation disabled with `schemesDisabled`), `ThemesModel.swift` (`busyWallpaper`, `pickWallpaper(_:)`; a needs-you or failed step shows like a switch's).
- Modify app: `GalleryView.swift` (a "WALLPAPER" row of two cards showing thumbnails of `grove-wallpapers/wallpaper-<name>-<current>.png`, found next to the fastfetch config's checkout via `$GROVE_ROOT/../grove-wallpapers` or `~/.config/../../grove-wallpapers`; the window height grows to fit), `DropdownView.swift` (a "WALLPAPER" row of two pills). Reuse LogoCard/LogoPill by generalising them to a "choice card" with an image provider, rather than copying.
- Test: `ModelsTests`, `ClientTests`, `FocusGridTests`, `ThemesModelTests`.

- [ ] **Step 1: Write the failing tests:**
  - `decodes wallpaper fields`.
  - `defaults without them`.
  - `setWallpaper runs "wallpaper avatar --json" and returns its steps and exit`.
  - `focus: down from the logo row reaches the wallpaper row; gallery stops there; dropdown continues to Open, then Quit; up returns to the logo last used`.
  - `pickWallpaper refreshes; a needs-you step shows`.
  - Update the existing focus tests whose paths gain a row.
- [ ] **Step 2: Run** `swift test` → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` → PASS; `swift build -c release`; `swift test` in grove-keys/app → PASS.
- [ ] **Step 5: Commit** `grove-themes: wallpaper picker in the app`.

### Task 5: Install and check by hand

- [ ] **Step 1:**
  1. Run `grove install themes-app keys-app`.
  2. Run the full grove-dotfiles suite in the background → all pass.
  3. Run `grove check` → all ok.
- [ ] **Step 2: With the user:**
  - `grove-themes wallpaper avatar`, then check another Space.
  - A scheme switch keeps the avatar wallpaper.
  - The gallery and dropdown rows.
  - `grove check` with the avatar chosen.
  - `wallpaper grove` restores today's wallpapers.
- [ ] **Step 3:** One fresh final review (most capable model), then a fix pass. Copy the ledger to the private notes and wait for "merge it".
