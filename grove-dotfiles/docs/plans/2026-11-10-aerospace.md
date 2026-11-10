# AeroSpace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AeroSpace tiles the desktop with pinned workspaces and Option shortcuts, JankyBorders outlines the focused window in the scheme's green, grove installs and checks both, and grove-themes recolours the borders on every switch.

**Architecture:** A static `config/aerospace/aerospace.toml` and a grove-themes template `config/borders/bordersrc.tmpl` both reach `~/.config` through 05-config's link. A new module `98-aerospace` checks/applies the install, the Spaces setting, the running app and Accessibility. grove-themes gains `<name>_argb` values and a `borders` step after `yazi`.

**Tech Stack:** bash 3.2, bats-core, shellcheck, TOML (parsed in tests by `/usr/bin/python3 -I` + `tomllib`), Homebrew taps.

**Spec:** `grove-dotfiles/docs/specs/2026-11-10-aerospace-design.md`

## Global Constraints

- bash 3.2 only; every `.sh` passes `shellcheck`.
- bats: assertions are `[[ … ]] || false` or `[ … ]`; never a bare `[[ ]]` or `! cmd` mid-test.
- Module `check` returns 0 ok / 1 failed / 3 needs work / 4 needs you and changes nothing.
- Tests never touch the real Mac: no real `aerospace`, `borders`, `defaults`, `open`, `osascript`, `killall`, `ps`-driven signals. Stub through PATH or the `GROVE_*` seams; `HOME`/`GROVE_STATE` point at temp folders (`grove_test_setup`, grove-themes' `setup_suite.bash` baselines).
- Workspace names are only `1`–`9`; no `persistent-workspaces`.
- Borders line, verbatim: `borders active_color={{green_argb}} inactive_color={{bg3_argb}} width=5.0 style=round hidpi=on`
- `_argb` format: `0xff` + the six hex digits upper-case, e.g. dark-medium green → `0xffA7C080`.
- Brewfile lines, verbatim: `cask "nikitabobko/tap/aerospace"` and `brew "FelixKratz/formulae/borders"`.
- Module `about`: `AeroSpace tiles the desktop`.
- Privacy: no tracked file names or links to the project's private folders.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. Homebrew not on PATH in a fresh `grove install` run → the module still finds `aerospace`/`borders` next to `brew` (as 95-vscode finds `code`). Pinned in Task 5.
2. AeroSpace running but Accessibility not granted → check says needs you (4), not needs work, and apply doesn't loop forever when run with `GROVE_YES=1`. Pinned in Task 5.
3. A scheme switch while borders isn't running must not start it or fail the switch. Pinned in Task 3.
4. A generated `config/borders/bordersrc` must stay gitignored while the template stays tracked (the allowlist `.gitignore` pattern is easy to get wrong). Pinned in Task 2.
5. Existing windows at AeroSpace startup must not be moved: every workspace rule carries `if.during-aerospace-startup = false`; float rules don't. Pinned in Task 4.

---

### Task 1: Probe AeroSpace without Accessibility (controller, live, with the user)

Not a code task: it answers the spec's open point (§7) before Task 5 is built on it. Run by the controller on the real Mac, with the user at hand.

- [ ] **Step 1:** `brew install --cask nikitabobko/tap/aerospace` and `brew install FelixKratz/formulae/borders`. Make sure `config/aerospace/aerospace.toml` doesn't exist yet (AeroSpace then runs its default config).
- [ ] **Step 2:** Before starting it: `aerospace list-workspaces --focused; echo "rc=$?"` → record stdout, stderr, rc (expected: a "can't connect to server" error).
- [ ] **Step 3:** `open -a AeroSpace`; ask the user to dismiss (not grant) the Accessibility prompt; wait 3 s; run the same command again and record. Also record `ps -axo comm= | grep -i aerospace`.
- [ ] **Step 4:** Ask the user to grant Accessibility; run it again and record (expected: `1`, rc 0).
- [ ] **Step 5:** Ledger the three results as `Task 1: probe: …`. If step 3's rc is non-zero with AeroSpace's process alive, Task 5's design stands. If step 3 succeeds or the process exits, rule the smallest change to Task 5's check (e.g. "process missing after start → needs you") and ledger it.

### Task 2: `_argb` values and the borders template

**Files:**
- Modify: `grove-themes/lib/render.sh` (`gt_values`: emit `name_argb` right after each `name_rgb`)
- Modify: `grove-themes/tests/render.bats`
- Create: `grove-dotfiles/config/borders/bordersrc.tmpl`
- Modify: `grove-dotfiles/config/.gitignore` (`!/borders/` with the other folders; `/borders/bordersrc` in the generated list)
- Modify: `grove-dotfiles/tests/config_allowlist.bats`, `grove-dotfiles/tests/templates.bats`

**Interfaces:**
- Produces: template names `<name>_argb` (`0xffRRGGBB`, upper case); the rendered file `config/borders/bordersrc` (a one-line `/bin/sh` script).

- [ ] **Step 1: Failing tests.**
  - `render.bats` "every #RRGGBB value also gets a name_argb": a palette line `white = #ffeedd` renders `{{white_argb}}` as `0xffFFEEDD`; dark-medium `{{green_argb}}` → `0xffA7C080`, `{{bg3_argb}}` → `0xff475258`.
  - `templates.bats` "bordersrc colours the borders for every scheme": for each of the six schemes, render `config/borders/bordersrc.tmpl` and assert the file's only non-comment line equals `borders active_color=0xff<green> inactive_color=0xff<bg3> width=5.0 style=round hidpi=on`, with green/bg3 read from `theme/everforest-<scheme>` and upper-cased.
  - `config_allowlist.bats`: `config/borders/bordersrc.tmpl` is not ignored; `config/borders/bordersrc` is ignored.
- [ ] **Step 2:** Run `bats grove-themes/tests/render.bats` and `bats grove-dotfiles/tests/templates.bats grove-dotfiles/tests/config_allowlist.bats` → the new tests FAIL.
- [ ] **Step 3:** Implement. The template starts with a `#` comment saying it is generated by grove-themes and run by AeroSpace at startup and by the `borders` step; then the Global Constraints line.
- [ ] **Step 4:** Both suites PASS (`bats grove-themes/tests`, `bats grove-dotfiles/tests`). Run `grove-themes render` so the live `config/borders/bordersrc` exists (05-config's check compares it).
- [ ] **Step 5:** Commit `grove-themes: _argb values; grove-dotfiles: the borders template`.

### Task 3: grove-themes step `borders`

**Files:**
- Modify: `grove-themes/lib/steps.sh` (new `gt_step_borders`; document `GROVE_BORDERS_SH` in the seams comment)
- Modify: `grove-themes/bin/grove-themes:161` (call it right after `gt_step_yazi`)
- Modify: `grove-themes/tests/set.bats`

**Interfaces:**
- Consumes: `config/borders/bordersrc` from Task 2; `GROVE_PS` and `_gt_line` as the Ghostty step uses them.
- Produces: `gt_step_borders` (no args) printing one `borders<TAB>result<TAB>message` line; returns 1 only on `failed`.

- [ ] **Step 1: Failing tests** in `set.bats`, with a fake `ps` (via `GROVE_PS`) and `GROVE_BORDERS_SH` pointing at a stub that logs its args and exits `${FAKE_SH_RC:-0}`:
  - "borders: recolours a running borders": `ps` lists `123 /opt/homebrew/bin/borders` → line `borders	live	recoloured`; the stub got `$GROVE_ROOT/config/borders/bordersrc`.
  - "borders: leaves a stopped borders alone": no borders in `ps` → `borders	live	not running`; stub never called.
  - "borders: a failing script fails the step": `FAKE_SH_RC=1` → `borders	failed	could not recolour the borders`, `set` exits 1.
  - Update "set --json lists every step" to `…chromeyaziborders""appearanceaccentwallpaper`.
- [ ] **Step 2:** `bats grove-themes/tests/set.bats` → the new/updated tests FAIL.
- [ ] **Step 3:** Implement. Match the process by its command's basename being exactly `borders` (so `bordersrc` or an editor on it never matches). Default `GROVE_BORDERS_SH` is `/bin/sh`.
- [ ] **Step 4:** `bats grove-themes/tests` PASS; `shellcheck grove-themes/lib/*.sh grove-themes/bin/grove-themes` clean; `swift test` in `grove-themes/app` still passes (Core decodes step lists generically).
- [ ] **Step 5:** Commit `grove-themes: recolour JankyBorders on every switch`.

### Task 4: `aerospace.toml`

**Files:**
- Create: `grove-dotfiles/config/aerospace/aerospace.toml`
- Modify: `grove-dotfiles/config/.gitignore` (`!/aerospace/`)
- Create: `grove-dotfiles/tests/aerospace_config.bats`
- Modify: `grove-dotfiles/tests/config_allowlist.bats`

**Interfaces:**
- Consumes: `~/.config/borders/bordersrc` (Task 2) in `after-startup-command`.

The contents are the spec's §4–§5 verbatim (gaps, shortcuts, service mode, rules, floats); build on AeroSpace's shipped default config for the keys the spec leaves alone (normalisations, `default-root-container-layout = 'tiles'`, `default-root-container-orientation = 'auto'`, `on-focused-monitor-changed = ['move-mouse monitor-lazy-center']`).

- [ ] **Step 1: Failing tests** in `aerospace_config.bats`, reading the file with a small `/usr/bin/python3 -I` + `tomllib` helper that prints what each test needs:
  - "parses as TOML".
  - "starts at login and starts borders": `start-at-login` is true; `after-startup-command` is exactly `['exec-and-forget /bin/sh ~/.config/borders/bordersrc']`.
  - "gaps are 8 everywhere": inner horizontal/vertical and outer left/right/top/bottom all 8.
  - "Option shortcuts": `alt-1`…`alt-9` → `workspace N`; `alt-shift-1`…`9` → `move-node-to-workspace N`; `alt-h/j/k/l` → `focus left/down/up/right`; `alt-shift-h/j/k/l` → `move …`; `alt-minus`/`alt-equal` → `resize smart -50`/`+50`; `alt-slash`, `alt-comma`, `alt-tab`, `alt-shift-tab`, `alt-shift-semicolon` as the spec's table.
  - "service mode": `esc`, `r`, `f`, `backspace`, `alt-shift-h/j/k/l` per spec §5, each ending in `mode main`.
  - "only workspaces 1–9": every `workspace`/`move-node-to-workspace` target is a digit 1–9; no `persistent-workspaces` key.
  - "every pinned app has its workspace": each app ID in spec §4's table maps (via an `on-window-detected` entry with `if.app-id` and `run = 'move-node-to-workspace N'`) to its N, and every such entry has `if.during-aerospace-startup = false`.
  - "floating apps": `com.apple.systempreferences`, `com.projectgrove.themes`, `com.apple.finder` each have an entry with `run = 'layout floating'` and no `during-aerospace-startup` condition.
  - `config_allowlist.bats`: `config/aerospace/aerospace.toml` is not ignored.
- [ ] **Step 2:** `bats grove-dotfiles/tests/aerospace_config.bats` → FAIL (no file).
- [ ] **Step 3:** Write the config.
- [ ] **Step 4:** `bats grove-dotfiles/tests` PASS.
- [ ] **Step 5:** Commit `grove-dotfiles: AeroSpace config`.

### Task 5: Brewfile and module `98-aerospace`

**Files:**
- Modify: `grove-dotfiles/Brewfile` (the two Global Constraints lines, after `cask "google-chrome"`)
- Create: `grove-dotfiles/modules/98-aerospace/module.sh`
- Create: `grove-dotfiles/tests/modules_aerospace.bats`
- Modify: `grove-dotfiles/tests/modules_base.bats` (Brewfile test), `grove-dotfiles/README.md` (module table row)

**Interfaces:**
- Consumes: Task 1's ledgered probe result; `grove_fail`, `grove_info`, `grove_note` from `lib/ui.sh`.
- Produces: module `98-aerospace` with `about`, `check`, `apply`. Seams: `GROVE_AEROSPACE`, `GROVE_BORDERS` (command paths; default: on PATH, else next to `${GROVE_BREW:-/opt/homebrew/bin/brew}`), `GROVE_PS` (default `ps`), `GROVE_POLL_SECONDS`; `defaults` and `open` from PATH.

**Ruling (carried from the plan, against spec §7's apply):** apply's Accessibility step follows 10-xcode-tools: open the pane, `grove_info` "allow AeroSpace in System Settings > Privacy & Security > Accessibility", then poll `aerospace list-workspaces --focused` every `GROVE_POLL_SECONDS` (default 5) until it works, and return 0. Under `GROVE_YES=1` apply doesn't open the pane or poll: it prints the hint and returns 0, so the next `grove check` reports needs you (a check of 3, e.g. on a fresh Mac, still calls apply, so grove's skip of 4 alone isn't enough).

- [ ] **Step 1: Failing tests** in `modules_aerospace.bats` (load the module as `modules_vscode.bats` does; stub `aerospace` to exit `${FAKE_AS_RC:-0}` and log args; stub `borders`, `defaults` (reads print `${FAKE_SPANS:-1}`, writes log), `open` (logs); fake `ps` via `GROVE_PS` printing `${FAKE_PS}`; `GROVE_POLL_SECONDS=0`):
  - "about": prints `AeroSpace tiles the desktop`.
  - "check: aerospace missing → 3" and "check: borders missing → 3" (`GROVE_AEROSPACE`/`GROVE_BORDERS` at a missing path, `GROVE_BREW` at a temp folder).
  - "check: finds aerospace next to brew when PATH lacks it" → not 3 for that reason.
  - "check: Spaces still separate → 3" (`FAKE_SPANS=0`).
  - "check: not running → 3" (`FAKE_PS` without AeroSpace).
  - "check: no Accessibility → 4" (`FAKE_PS='1 /Applications/AeroSpace.app/Contents/MacOS/AeroSpace'`, `FAKE_AS_RC=1`).
  - "check: all good → 0", and check never calls `defaults write` or `open`.
  - "apply: writes spans-displays and says log out": `defaults write com.apple.spaces spans-displays -bool true` logged; output contains `log out once to finish the Spaces change`.
  - "apply: leaves spans-displays alone when set" (no write).
  - "apply: opens AeroSpace when not running": `open -a AeroSpace` logged.
  - "apply: opens the Accessibility pane and waits": `aerospace` stub fails twice then succeeds (counter file) → `open x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` logged, apply returns 0.
  - "apply: aerospace missing → 1 with `run grove install homebrew`".
  - `modules_base.bats`: "the Brewfile installs AeroSpace and JankyBorders" (`grep -qx` both lines).
  - README test (as `modules_themes_app.bats:227`): row `| \`98-aerospace\` | AeroSpace tiles the desktop: pinned workspaces, Option shortcuts and JankyBorders in the scheme's colours (Accessibility is a manual step) |`.
- [ ] **Step 2:** `bats grove-dotfiles/tests/modules_aerospace.bats grove-dotfiles/tests/modules_base.bats` → FAIL.
- [ ] **Step 3:** Implement, with check's order exactly as spec §7 (installed → Spaces → running → Accessibility → ok) and Task 1's ruling if any. Running means a `ps -axo pid=,comm=` line ending in `/AeroSpace.app/Contents/MacOS/AeroSpace`.
- [ ] **Step 4:** `bats grove-dotfiles/tests` and `bats grove-themes/tests` PASS; `shellcheck grove-dotfiles/modules/*/module.sh` clean.
- [ ] **Step 5:** Commit `grove-dotfiles: module 98-aerospace and the Brewfile`.

### Task 6: Live install and hand check (controller, with the user)

- [ ] **Step 1:** Privacy checks: the project's private folders are untracked, absent from history, and named by no tracked file.
- [ ] **Step 2:** `grove install homebrew aerospace` (Accessibility was granted in Task 1, so apply should only write the Spaces setting and restart nothing). Then `aerospace reload-config` and `/bin/sh ~/.config/borders/bordersrc`.
- [ ] **Step 3:** `grove check` → every module ok, `98-aerospace` included (the Spaces change still waits for a logout; the check reads the setting, so it is ok).
- [ ] **Step 4:** `grove-themes set light-soft` then back to the current scheme: the `borders` line says `live recoloured` both times.
- [ ] **Step 5:** Ask the user to check by hand: tiling, the shortcuts, workspaces 1–6, the floating apps, the borders' colour after a switch, and AeroSpace after logging out and in.
