# grove-dotfiles Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ghostty as the Grove terminal (Everforest Dark Medium, quick terminal, in Terminal's Dock slot), Starship with icons plus a plain fallback for Terminal.app, and a macchina summary in every new window, all set up by `grove install`.

**Architecture:**
- Config files live in `config/`, which is already linked as `~/.config`.
- Homebrew installs Ghostty and macchina from the Brewfile.
- One new module, `90-terminal`, checks the apps and the Ghostty config, and swaps the Dock tile.
- Two `conf.d` files pick the prompt config and run macchina.
- One palette file, `theme/everforest-dark-medium`, is the only source of colors. A test enforces it.

**Tech Stack:** bash 3.2, zsh 5.9, bats-core 1.14, shellcheck 0.11, `defaults`/PlistBuddy, Ghostty 1.4 (cask), macchina 6.4, Starship 1.27.

**Spec:** `grove-dotfiles/docs/specs/2026-11-09-grove-terminal-design.md`. It builds on the foundation spec in the same folder.

## Global Constraints

- **Shells:**
  - Module code runs under `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${var,,}`, no `[[ -v ]]`.
  - `conf.d/*.zsh` is zsh and must print nothing unless the spec says so (macchina).
- **Module `check`:** returns `0` ok, `1` failed, `3` needs work, `4` needs you, and never changes anything. `apply` runs only when `check` didn't return 0.
- **Nothing is deleted:** a replaced file goes through `grove_backup`, into `$GROVE_STATE/backup/$GROVE_RUN_ID/…`.
- **Colors:** every `#RRGGBB` in `config/ghostty/config`, `config/starship.toml`, `config/starship-plain.toml` and `config/macchina/themes/grove.toml` must appear in `theme/everforest-dark-medium`. Grove's additions are only `fill #596763` and bright black = grey1.
- **Exact values** (font, sizes, palette slots, keybind, readout order, Dock rules) are in the spec, §5–§9. Copy them from there.
- **Test seams:** tests redirect the Dock domain with `GROVE_DOCK_DOMAIN` and Ghostty's CLI with `GROVE_GHOSTTY`.
  - Default domain: `com.apple.dock`.
  - Default CLI: `/Applications/Ghostty.app/Contents/MacOS/ghostty`.
  - The app check uses `GROVE_GHOSTTY_APP`, default `/Applications/Ghostty.app`.
- **Private material:** `artifacts/` and `.recording/` are never committed or referenced from tracked files.
- **Commits:** signed (already configured). Each message ends with `Co-Authored-By: <model that wrote it> <noreply@anthropic.com>`.
- **Verification:** run tests with `bats grove-dotfiles/tests` from `project-grove/`, and `shellcheck -x` every changed bash file.

## Review Focus

1. **Stale bookmark in the Dock tile.** Dock tiles carry `tile-data:book` (bookmark data) and `bundle-identifier`. If only `_CFURLString` and `file-label` change, the Dock can keep launching Terminal. The swap must:
   - delete `book`;
   - set `bundle-identifier` to `com.mitchellh.ghostty`;
   - set `file-type` to `41` (an app).

   Test: Task 5, `swap removes the old bookmark and sets Ghostty's bundle id`.
2. **Terminal found by path, not by name.** `file-label` can be localized or renamed, so match the Terminal tile by `_CFURLString` ending in `/Terminal.app/`. Test: Task 5, `swap finds Terminal by its path even when the label differs`.
3. **Ghostty and Terminal both in the Dock.** If you added Ghostty yourself, replacing Terminal would leave Ghostty in the Dock twice. Instead, remove the Terminal tile and keep the existing Ghostty one. Test: Task 5, `apply removes Terminal when Ghostty is already in the Dock`.
4. **A second Ghostty config in Application Support.** Ghostty also reads `~/Library/Application Support/com.mitchellh.ghostty/config`, after the XDG one, so its values win. A non-empty file there silently overrides Grove.
   - `check` returns 3 while that file exists and isn't empty.
   - `apply` moves it to the backup with `grove_backup`.

   Test: Task 5, `a Ghostty config in Application Support is backed up`.
5. **The summary inside nested shells and tools.** The `GROVE_FETCHED` marker (spec §8) must survive into child processes, and an empty `GROVE_FETCHED` counts as unset. Test: Task 4, `macchina stays quiet when GROVE_FETCHED is inherited`.

---

### Task 1: Tools, palette file and the color test

**Files:**
- Modify: `grove-dotfiles/Brewfile`, `grove-dotfiles/config/.gitignore`, `grove-dotfiles/tests/config_allowlist.bats`
- Create: `grove-dotfiles/theme/everforest-dark-medium`, `grove-dotfiles/tests/theme.bats`

**Interfaces:**
- Produces:
  - **Palette file format:** one `name = #RRGGBB` per line; `#` starts a comment only at the start of a line; blank lines allowed. Section comments `# Upstream (Dark Medium)` and `# Grove additions`.
  - **`tests/theme.bats` helper `palette_hexes`:** prints every hex in the palette file, uppercased, one per line.
  - **`config_hexes FILE…`:** prints every `#RRGGBB` found in those files, uppercased.
  - **The color test:** checks the four config files from the Global Constraints, skipping any that don't exist yet, so later tasks only add files.

- [ ] **Step 1:** Add `cask "ghostty"` and `brew "macchina"` to the Brewfile. Run `/opt/homebrew/bin/brew bundle install --no-upgrade --file grove-dotfiles/Brewfile`. Expected: Ghostty.app in `/Applications`, `macchina --version` prints 6.4.x.
- [ ] **Step 2: Record the tool facts** the later tasks depend on, in the task report. Run each and note the answer:
  - `"/Applications/Ghostty.app/Contents/MacOS/ghostty" +validate-config --help`: the exact flag for a config file path.
  - `macchina --help`: whether it reads `~/.config/macchina/macchina.toml` on macOS. Check with `macchina --doctor`, which prints the config path it uses.
  - The exact readout names for 6.4.
  - The theme folder location.

  If macchina doesn't use `~/.config/macchina` on macOS, rule: the hook in Task 4 passes the config path explicitly, through whatever flag `--help` lists (`-c`/`--config`).
- [ ] **Step 3: Write failing tests** in `tests/theme.bats`:
  - `the palette has every upstream Dark Medium color`: all 24 upstream names from spec §5 are present with their exact values. Take the names and values from the spec.
  - `the palette's Grove additions are only the fill color`: the lines under `# Grove additions` are exactly `fill = #596763`.
  - `every config color comes from the palette`: `config_hexes` over the four files, minus `palette_hexes`, is empty.

  Add to `tests/config_allowlist.bats`: `ghostty and macchina configs are tracked`. `git check-ignore` must reject `config/ghostty/config`, `config/macchina/macchina.toml`, `config/macchina/themes/grove.toml` and `config/macchina/grove.ascii`.
- [ ] **Step 4:** Run `bats grove-dotfiles/tests/theme.bats grove-dotfiles/tests/config_allowlist.bats`. Expected: FAIL. The palette is missing, and the allowlist ignores `ghostty/`.
- [ ] **Step 5: Implement:**
  - Create the palette file with the values from spec §5. Bright black isn't a color, so it appears only as a comment in the Grove additions section.
  - In `config/.gitignore`, add `!/ghostty/` and `!/macchina/` after `!/zsh/`.
  - The color test already passes against the existing `starship.toml`, whose colors are all in the palette, including `#596763`.
- [ ] **Step 6:** Run the whole suite and shellcheck. Expected: PASS.
- [ ] **Step 7: Commit:** "Add the Grove palette file and the color test; install Ghostty and macchina".

### Task 2: Ghostty config

**Files:**
- Create: `grove-dotfiles/config/ghostty/config`
- Test: `grove-dotfiles/tests/theme.bats`

**Interfaces:**
- Consumes: the color test from Task 1.
- Produces: `config/ghostty/config`, which Task 5's `check` validates.

- [ ] **Step 1: Write failing tests:**
  - `ghostty config sets the spec's keys`: parse `key = value` lines. Assert the values in spec §6:
    - `font-family = JetBrains Mono`, `font-size = 14`;
    - `background = #2D353B`;
    - `palette = 0=#475258` and `palette = 8=#859289`;
    - `background-opacity = 1`;
    - `keybind = global:ctrl+grave_accent=toggle_quick_terminal`;
    - `quick-terminal-position = top`.

    Assert there are 16 `palette` lines, with slots 0–15 each once.
  - `ghostty validates the config`: skip if `GROVE_GHOSTTY` (default path) isn't executable. Otherwise run validation with the flag from Task 1 Step 2. Expected: status 0 and no output.
- [ ] **Step 2:** Run the tests. Expected: FAIL (file missing).
- [ ] **Step 3: Create the config** with exactly the keys in spec §6, and a header comment pointing at the palette file.
- [ ] **Step 4:** Run the suite. Expected: PASS, including the color test, which now covers this file.
- [ ] **Step 5: Commit:** "Add the Ghostty config (Everforest Dark Medium, quick terminal)".

### Task 3: Starship icons and the Terminal.app fallback

**Files:**
- Create: `grove-dotfiles/config/starship-plain.toml` (a copy of today's `starship.toml`)
- Modify: `grove-dotfiles/config/starship.toml`, `grove-dotfiles/config/zsh/conf.d/90-prompt.zsh`
- Test: `grove-dotfiles/tests/theme.bats`, `grove-dotfiles/tests/modules_zsh.bats`

**Interfaces:**
- Produces: `90-prompt.zsh` exports `STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship-plain.toml"` only when `TERM_PROGRAM=Apple_Terminal`. It never sets `STARSHIP_CONFIG` otherwise.

- [ ] **Step 1: Write failing tests:**
  - `the two prompts differ only in symbols`: in both files, drop the lines whose key is `symbol`, `read_only` or `format`. Here `format` means only the `format` lines inside the `[cmd_duration]` and `[jobs]` tables, where the icons go. The remaining text must be identical.
  - `the icon prompt uses the spec's glyphs`: `starship.toml` contains U+E0A0 (git_branch), U+F033E (read_only) and U+F051B (cmd_duration), and `✦` (jobs).
  - Extend `starship accepts the config` to both files: no output on stderr.
  - In `modules_zsh.bats`:
    - `Terminal.app gets the plain prompt`: run `env -i … TERM_PROGRAM=Apple_Terminal zsh -ic 'print -r -- $STARSHIP_CONFIG'`, with the temp-HOME pattern of the existing login tests. Expected: `$HOME/.config/starship-plain.toml`.
    - `Ghostty gets the default prompt`: the same with `TERM_PROGRAM=ghostty`. Expected: an empty line.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement:**
  - `starship-plain.toml`: today's file. Change its header comment to "Prompt without icons, for Terminal.app".
  - `starship.toml`: the spec §7 symbols. `git_branch.symbol = " "`; `directory.read_only = " 󰌾"`; `cmd_duration.format = "[󰔛 $duration]($style) "`; `jobs.symbol = "✦"`. Everything else stays the same.
  - `90-prompt.zsh`: the `TERM_PROGRAM` branch, before `starship init`.
- [ ] **Step 4:** Run the suite and `zsh -n` on the conf.d files. Expected: PASS.
- [ ] **Step 5: Commit:** "Give the prompt icons in Ghostty, keep it plain in Terminal.app".

### Task 4: macchina config and the new-window hook

**Files:**
- Create: `grove-dotfiles/config/macchina/macchina.toml`, `grove-dotfiles/config/macchina/themes/grove.toml`, `grove-dotfiles/config/macchina/grove.ascii`, `grove-dotfiles/config/zsh/conf.d/95-macchina.zsh`
- Test: `grove-dotfiles/tests/modules_zsh.bats`, `grove-dotfiles/tests/theme.bats`

**Interfaces:**
- Consumes: the tool facts from Task 1 Step 2: readout names, the config flag if one is needed, and the theme location.
- Produces: the hook exports `GROVE_FETCHED=1` after running macchina.

- [ ] **Step 1: Write failing tests** in `modules_zsh.bats`. Use a stub `macchina` that prints `FETCH`, put first on PATH. Run `zsh -ic` through `script -q /dev/null` so stdout is a terminal, inside `env -i HOME=… PATH=stubs:/usr/bin:/bin`.
  - `macchina runs in a new Ghostty window`: `TERM_PROGRAM=ghostty`. Output contains `FETCH`, and `print $GROVE_FETCHED` prints `1`.
  - `macchina runs in a new Terminal.app window`: `TERM_PROGRAM=Apple_Terminal`. Output contains `FETCH`.
  - `macchina stays quiet when GROVE_FETCHED is inherited`: `GROVE_FETCHED=1`. No `FETCH`. With `GROVE_FETCHED=` (empty), `FETCH` appears.
  - `macchina stays quiet with GROVE_NO_FETCH=1`, `… in other terminals` (`TERM_PROGRAM=vscode`), `… when stdout isn't a terminal` (no `script`), and `… when macchina is missing` (no stub). In each: no `FETCH`, no error output, status 0.

  In `theme.bats`:
  - `macchina shows the spec's readouts in order`: the `show` list equals spec §8's list, or Task 1's 6.4 names where they differed.
  - `macchina accepts its config`: skip unless `macchina` is installed. `macchina --doctor` with the config, exit 0, no error lines. Use `HOME` pointing at a temp dir whose `.config` links to the repo's `config/`.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3: Implement:**
  - **The three macchina files:**
    - colors and readouts from spec §8;
    - the ASCII tree at most 10 lines × 20 columns, colored green;
    - the theme's bar colors aqua on bg3.
  - **`95-macchina.zsh`:**
    - checks the five conditions of spec §8;
    - runs macchina, adding the config flag only if Task 1 found it necessary;
    - ignores its exit status;
    - then `export GROVE_FETCHED=1`.
- [ ] **Step 4:** Run the suite. Expected: PASS, including the color test over `grove.toml`.
- [ ] **Step 5: Commit:** "Show a macchina summary in every new terminal window".

### Task 5: The `90-terminal` module

**Files:**
- Create: `grove-dotfiles/modules/90-terminal/module.sh`, `grove-dotfiles/tests/modules_terminal.bats`

**Interfaces:**
- Consumes:
  - from `lib/ui.sh`: `grove_info`, `grove_note`, `grove_fail`;
  - from `lib/link.sh`: `grove_backup PATH`;
  - `config/ghostty/config` from Task 2.
- Produces:
  - `about`, `check`, `apply`, per the module contract.
  - **Internal helpers** (bash, run in the module subshell):
    - `_term_dock_domain`: prints `${GROVE_DOCK_DOMAIN:-com.apple.dock}`.
    - `_term_dock_state PLIST`: prints `ghostty`, `terminal`, `both` or `neither`, from the plist's `persistent-apps`.
    - `_term_dock_fix PLIST`: edits the plist in place per spec §9 and Review Focus 1–3. Returns 0 when changed, 2 when nothing needed changing, 1 on error.
    - `_term_extra_config`: prints the Application Support config path when that file exists and isn't empty.

- [ ] **Step 1: Write failing tests** in `tests/modules_terminal.bats`. Setup:
  - `GROVE_DOCK_DOMAIN=com.grove.testdock`, deleted in setup and teardown;
  - a temp `GROVE_GHOSTTY_APP` folder;
  - `GROVE_GHOSTTY`: a stub that exits with `$BATS_TEST_TMPDIR/ghostty-rc` (default 0) and echoes `$BATS_TEST_TMPDIR/ghostty-msg`;
  - stubs for `macchina` and `killall`. `killall` logs to a file.

  Seed the domain with `defaults import` from a heredoc plist with three tiles:
  - Safari: label `Safari`, URL `file:///Applications/Safari.app/`;
  - Terminal: label `Terminal`, URL `file:///System/Applications/Utilities/Terminal.app/`, a `book` data key, `bundle-identifier com.apple.Terminal`;
  - System Settings.

  Tests:
  - `check is ok on a finished setup`.
  - `check needs work when Ghostty is missing`, `… when macchina is missing`, `… when the Dock has Terminal`, `… when Ghostty isn't in the Dock`.
  - `check fails with Ghostty's message when the config is invalid`: rc 1, msg `bad key`. Status 1, and the output contains `bad key`.
  - `apply swaps Terminal for Ghostty in the same slot`: the labels read `Safari, Ghostty, System Settings`, in the same order.
  - `swap removes the old bookmark and sets Ghostty's bundle id`: tile 1 has no `book`. Its `bundle-identifier` is `com.mitchellh.ghostty`, and its URL is `file:///Applications/Ghostty.app/`.
  - `swap finds Terminal by its path even when the label differs`: seed the label `Terminal (old)`. The swap still happens.
  - `apply puts Ghostty first when Terminal is absent`.
  - `apply removes Terminal when Ghostty is already in the Dock`: seed both. Afterwards there's exactly one Ghostty tile and no Terminal tile.
  - `apply twice changes nothing and doesn't restart the Dock`: the second run leaves `killall.log` with one line.
  - `apply leaves the Dock untouched when the import fails`: a `defaults` wrapper stub fails on `import` and passes everything else to `/usr/bin/defaults`. Status 1, and `defaults export` matches the seed.
  - `a Ghostty config in Application Support is backed up`: `check` returns 3. After `apply`, the file is under `$GROVE_STATE/backup/test/Library/Application Support/com.mitchellh.ghostty/config`.
  - `apply fails without Ghostty or macchina and points to grove install homebrew`.
  - `apply prints the Accessibility step, also with GROVE_QUIET=1`.
- [ ] **Step 2:** Run the tests. Expected: FAIL (no module).
- [ ] **Step 3: Implement `module.sh`.**
  - **The Dock change runs on a temp plist from `defaults export`:**
    - Edit it with `/usr/libexec/PlistBuddy`.
    - `defaults import` it back, and `killall Dock` only if `_term_dock_fix` returned 0.
    - On any failure, don't import.
  - **`about`:** "Ghostty, the prompt and macchina".
  - **`check` order:**
    1. App and macchina.
    2. Validation (status 1, with the message through `grove_fail`).
    3. The extra config.
    4. The Dock.
- [ ] **Step 4:** Run the suite and shellcheck. Expected: PASS.
- [ ] **Step 5: Commit:** "Add the 90-terminal module: checks Ghostty and swaps it into the Dock".

### Task 6: Docs and rollout on this Mac (interactive, with the user)

**Files:**
- Modify: `grove-dotfiles/README.md` (module table row `90-terminal`, and a short "Terminal" section: Ghostty, quick terminal, the Accessibility step, the plain prompt in Terminal.app, `GROVE_NO_FETCH`)
- Modify: `grove-dotfiles/docs/specs/2026-11-09-grove-terminal-design.md` (a "Results" note at the end)

- [ ] **Step 1:** README changes. Run the full suite and lint. Commit: "Document the terminal setup".
- [ ] **Step 2:** Run `grove check` here. Expected: `90-terminal` needs work, and everything else ok.
- [ ] **Step 3: The user runs `grove install` in Terminal**, then opens Ghostty and allows it under Privacy & Security › Accessibility.
- [ ] **Step 4: Verify with the user:**
  - `grove check` exits 0;
  - the Dock reads Ghostty, Safari, System Settings;
  - a new Ghostty window shows the summary, then the icon prompt;
  - a nested `zsh` shows no summary;
  - ⌃` toggles the quick terminal from another app;
  - Terminal.app shows the plain prompt with no broken glyphs.
- [ ] **Step 5:** Record the results, including the `SHLVL` that Ghostty's first shell reports, which explains the marker choice, in the spec's Results note. Commit: "Record the terminal rollout results".
