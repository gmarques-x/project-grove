# grove-themes (palettes, templates, CLI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `grove-themes set <scheme>` switches Ghostty, the prompt, zsh, eza, bat, yazi, fastfetch, VS Code, macOS appearance, accent/highlight and the wallpaper between the six Everforest schemes, with git staying clean.

**Architecture:**
- Six palette files in `grove-dotfiles/theme/`; colour-carrying configs become tracked `*.tmpl` files; generated files sit at today's paths, gitignored.
- `project-grove/grove-themes/` holds the bash CLI: `lib/render.sh` (templates → files), `lib/steps.sh` (app refreshes), `bin/grove-themes` (commands).
- grove-dotfiles uses it: `05-config` renders, `70-zsh` links the command, `85-macos-wallpaper` follows the current scheme.

**Tech Stack:** bash 3.2, sed, bats-core 1.14, shellcheck 0.11, `osascript`, `defaults`, `ps`/`kill`, Python 3 + Pillow/numpy only for private one-off scripts (not in the repo).

**Spec:** `grove-dotfiles/docs/specs/2026-11-10-grove-themes-design.md` (§4 palettes, §5 templates, §6 CLI, §7 set, §8 tests).

## Global Constraints

- Branch `grove-themes` **in the main checkout** (`~/Developer/project-grove`), never a worktree (`05-config` refuses; `~/.config` links into the main checkout).
- Module code and the CLI run under `/bin/bash` 3.2: no associative arrays, `mapfile`, `${var,,}`.
- Module `check` returns `0`/`1`/`3`/`4` and changes nothing.
- Scheme names: `dark-hard dark-medium dark-soft light-hard light-medium light-soft`; default `dark-medium`. State file `$GROVE_STATE/theme` (one line).
- Template syntax `{{name}}`, name `[a-z0-9_]+`. Non-colour names, computed from the scheme name, not stored in palettes: `appearance` (dark|light), `contrast` (hard|medium|soft), `vscode_theme` (`Everforest Dark`|`Everforest Light`), `fetch_image` (`grove.png`|`grove-light.png`).
- Bats assertions: `[[ … ]] || false`, never a bare `[[ ]]` or `! cmd` mid-test (they don't fail a test; macOS also has `/usr/bin/apply`).
- Tests copy only git-tracked config: `git add` new tracked files before running them.
- Ghostty reload (spike done 2026-11-10): Ghostty 1.4.0 macOS handles `SIGUSR2` by reloading its config (log: "reloading configuration in response to SIGUSR2"). `pgrep` can't see the process from this shell: find PIDs with `ps -axo pid=,comm=` lines ending in `/Ghostty.app/Contents/MacOS/ghostty`.
- The conversion and image scripts stay private (not in the repo) and are never committed.
- Commits signed, ending `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push.

## Review Focus

1. **Hand edits to any generated file** (the user tweaks `~/.config/ghostty/config` directly, as they have before): the spec protects only VS Code, but a switch would silently drop a Ghostty edit too. This plan applies the spec's VS Code rule to every generated file (Ruling R1, Task 5): back up an edited file and report it. Test in Task 5.
2. **A state file with an unknown or empty scheme**: `current` and `render` fall back to `dark-medium` and say so on stderr, never fail the install. Test in Task 4.
3. **A target that can't be written mid-switch**: `set` exits 1, the state file keeps the old scheme, and a later `render` repairs. Test in Task 4.
4. **A fresh clone with no generated files**: `05-config` check is needs work (not ok, not failed) and apply renders; app modules after it find their files. Test in Task 4.
5. **No Ghostty running / Automation denied**: the Ghostty step reports "not running" as fine; appearance and wallpaper report needs you with the Automation hint, and the other steps still run. Tests in Task 5.

Rulings made while planning (the executor carries them; the user sees them at handoff):
- **R1:** the "edited since last written" backup applies to every generated file, not only VS Code's (Review Focus 1). Last-written copies live in `$GROVE_STATE/theme-rendered/<path>`.
- **R2:** `render` takes `--scheme S` and `--config DIR` (defaults: current scheme, `$GROVE_ROOT/config`) so `05-config`'s check and the tests can render into a temp folder (spec §5 needs it).

---

### Task 1: Six palettes

**Files:**
- Create: `theme/everforest-{dark-hard,dark-soft,light-hard,light-medium,light-soft}`
- Modify: `theme/everforest-dark-medium` (add `term0`–`term15`)
- Create: `tests/fixtures/everforest-upstream.txt` (lines `scheme name #HEX`, every background and foreground value of all six schemes, copied from the upstream Everforest palette (verified against the plugin source))
- Modify: `tests/theme.bats`

**Interfaces:**
- Produces: every palette has the upstream names, `fill`, and `term0`–`term15`; later tasks read `theme/everforest-<scheme>`.

- [ ] **Step 1:** `git -C ~/Developer/project-grove switch -c grove-themes`
- [ ] **Step 2: Failing tests** in `theme.bats`:
  - `each palette has every upstream color` — for each fixture line, the palette's value equals the hex.
  - `terminal roles follow upstream` — dark: `term0`=`bg3`, `term7`=`fg`; light: `term0`=`fg`, `term7`=`bg3`; all: `term1..6` = red green yellow blue purple aqua, `term8`=`grey1`, `term9..15` = `term1..7`.
  - `fill is Grove's` — dark schemes `#596763`, light ones equal their `bg5`.
  - Keep the existing Dark Medium tests; the Grove-additions test now allows `fill` and `term*`.
- [ ] **Step 3: Run** `bats tests/theme.bats` — Expected: the new tests fail (files missing).
- [ ] **Step 4: Write the palettes** (same header comment style as Dark Medium, each value from the fixture).
- [ ] **Step 5: Run** the same — Expected: all pass. Then `bats tests` — Expected: all 305 + new pass.
- [ ] **Step 6: Commit** `theme: all six Everforest palettes, with terminal roles`

---

### Task 2: The renderer

**Files:**
- Create: `../grove-themes/lib/render.sh`, `../grove-themes/tests/render.bats`, `../grove-themes/tests/helpers.bash` (paths below are from `project-grove/`)

**Interfaces:**
- Produces (sourced by Tasks 3–5):
  - `gt_schemes` → the six names, one per line, in the Global Constraints order.
  - `gt_valid SCHEME` → 0 when one of the six.
  - `gt_values SCHEME PALETTE_DIR` → `name<TAB>value` lines: every palette entry, then the four computed names.
  - `gt_render_file SCHEME PALETTE_DIR TEMPLATE OUT` → writes OUT; returns 1 (writing nothing) and prints `unknown name: X in TEMPLATE` when a `{{X}}` has no value.
  - `gt_templates CONFIG_DIR` → every `*.tmpl` under CONFIG_DIR, relative paths, sorted.

- [ ] **Step 1: Failing tests** (`grove-themes/tests/render.bats`, a toy palette dir in `$BATS_TEST_TMPDIR`):
  - `render fills names with the scheme's values` — `fg={{fg}} bg={{bg0}}` → the palette's hexes.
  - `render fills the computed names` — `light-soft`: `appearance`=light, `contrast`=soft, `vscode_theme`=`Everforest Light`, `fetch_image`=`grove-light.png`; `dark-hard`: dark, hard, `Everforest Dark`, `grove.png`.
  - `an unknown name fails and writes nothing` — status 1, message names it, OUT absent.
  - `text without names passes through byte for byte` — a file with `#`, `/`, `&`, `\` and `{single}` braces is unchanged.
  - `gt_valid rejects other names` — `dark`, `Dark-Medium`, `` → 1.
- [ ] **Step 2: Run** `bats ../grove-themes/tests/render.bats` — Expected: fail (no lib).
- [ ] **Step 3: Implement** `render.sh`. Build one sed script from `gt_values` (escape `&`, `/` and `\` in values), apply it, then `grep -o '{{[a-z0-9_]*}}'` on the result to catch leftovers; write to `OUT.tmp` and `mv` only on success.
- [ ] **Step 4: Run** the same, plus `shellcheck ../grove-themes/lib/render.sh` — Expected: pass, silent.
- [ ] **Step 5: Commit** `grove-themes: render templates for a scheme`

---

### Task 3: Configs become templates

**Files:**
- Create: `config/<path>.tmpl` for the 12 files in spec §5, via a private one-off conversion script (not committed)
- Create: `tests/fixtures/dark-medium/<path>` (today's 12 files, verbatim)
- Delete from git (kept on disk, now generated): the 12 config files; Modify: `config/.gitignore` (ignore them, keep `*.tmpl` tracked)
- Create: `tests/setup_suite.bash`; Modify: `tests/helpers.bash`, `tests/theme.bats`, `tests/modules_vscode.bats`, `tests/config_allowlist.bats`, and every test that reads a now-generated file
- Test: `tests/templates.bats`

**Interfaces:**
- Consumes: Task 2's `gt_render_file`, `gt_templates`, `gt_schemes`; Task 1's palettes.
- Produces: `GROVE_RENDERED` (exported by `setup_suite.bash`): a Dark Medium render of a tracked-config copy in `$BATS_SUITE_TMPDIR/config`. `grove_copy_tracked_config DEST` now also renders Dark Medium into DEST. Tests read generated files from `$GROVE_RENDERED`, never from `$GROVE_ROOT/config`.

- [ ] **Step 1: Failing tests** (`tests/templates.bats`):
  - `templates use only palette and computed names` — every `{{x}}` in every `.tmpl` is in `gt_values dark-medium`.
  - `every template renders for all six schemes` — `gt_render_file` succeeds for 12 × 6.
  - `the Dark Medium render is today's config` — for each fixture, `cmp` with the render.
  - `generated files are ignored, templates are tracked` (config_allowlist) — `git check-ignore` true for `config/ghostty/config`, false for `config/ghostty/config.tmpl`, same for all 12.
- [ ] **Step 2: Run** `bats tests/templates.bats tests/config_allowlist.bats` — Expected: fail.
- [ ] **Step 3: Convert.** The conversion script replaces each Dark Medium hex by its palette name (case-insensitive; no two names share a hex), terminal slots by `termN` (Ghostty `palette = N=`, VS Code `terminal.ansi*` in slot order), `window-theme = dark` → `{{appearance}}`, the fastfetch logo `grove.png` → `{{fetch_image}}`, VS Code's `Everforest Dark` (theme and the `[Everforest Dark]` key) → `{{vscode_theme}}`, `"everforest.darkContrast": "medium"` → both `"everforest.darkContrast": "{{contrast}}"` and `"everforest.lightContrast": "{{contrast}}"`. It prints any hex it couldn't name; the list must be empty. Copy today's files to the fixtures first. **The VS Code fixture gains the `lightContrast` line** (Ruling: spec §5 writes both keys; the byte-for-byte test compares against the fixture with that one added line).
- [ ] **Step 4: Rewire tests:** `setup_suite.bash` builds `GROVE_RENDERED`; `grove_copy_tracked_config` renders after copying; replace reads of generated files (`$GROVE_ROOT/config/<generated>`, `$GROVE_CONFIG/vscode/settings.json` …) with `$GROVE_RENDERED/…`; theme.bats's palette test checks the templates' rendered output for every scheme against that scheme's palette.
- [ ] **Step 5: Stage** `git rm --cached` the 12 generated files, `git add` templates, fixtures, `.gitignore`, tests.
- [ ] **Step 6: Run** `bats tests` and `bats ../grove-themes/tests` — Expected: all pass; `git status` shows no untracked generated files; the live `~/.config` files are byte-identical to before (`cmp` against the fixtures).
- [ ] **Step 7: Commit** `config: colour-carrying configs become templates for any scheme`

---

### Task 4: CLI commands and grove-dotfiles wiring

**Files:**
- Create: `../grove-themes/bin/grove-themes`, `../grove-themes/lib/state.sh`, `../grove-themes/tests/cli.bats`, `../grove-themes/README.md` (usage, the six schemes)
- Modify: `modules/05-config/module.sh`, `modules/70-zsh/module.sh`, `README.md` (05-config and 70-zsh rows), root `../README.md` (a `grove-themes/` row)
- Test: `tests/modules_base.bats` (05-config), `tests/modules_zsh.bats` (70-zsh link)

**Interfaces:**
- Consumes: Task 2's render functions.
- Produces:
  - `gt_current` → the state file's scheme; empty/unknown → `dark-medium` plus `grove-themes: unknown scheme in $GROVE_STATE/theme, using dark-medium` on stderr.
  - `gt_render_all SCHEME CONFIG_DIR` → renders every template into a temp dir, then `mv`s each into CONFIG_DIR; 1 on any failure (render failure: nothing moved).
  - CLI per spec §6, plus R2's `render [--scheme S] [--config DIR]`. `set SCHEME` in this task does step 1 only (configs + state); Task 5 adds the rest. Exit codes: 0 ok, 1 a step failed, 2 usage/unknown scheme.
  - `GROVE_ROOT` default: `<grove-themes>/../grove-dotfiles` (resolved through symlinks like `bin/grove` does).
- [ ] **Step 1: Failing tests** (`cli.bats`, temp copy of the tracked config + palettes):
  - `list marks the current scheme` (six lines, `*` on the current), `--json` gives `{"current": "...", "schemes": [...]}`.
  - `current defaults to dark-medium`; `current falls back on a bad state file` (Review Focus 2: `light-pink` in the file → `dark-medium`, warning on stderr, status 0).
  - `set writes the configs and the state` — `set light-soft` → rendered Ghostty config has `background = ` the light-soft `bg0`, state file `light-soft`.
  - `set with an unknown scheme exits 2 and changes nothing`.
  - `a failed render changes nothing` — a template with `{{nope}}` → exit 1, files and state as before.
  - `an unwritable target keeps the old state` (Review Focus 3) — `chmod a-w` one target folder → exit 1, state unchanged; after `chmod u+w`, `render` repairs it.
  - `render --scheme --config renders elsewhere` (R2).
  - `05-config: needs work when generated files are missing, apply renders them` (Review Focus 4); `ok when they match`; `needs work when one differs from a render`; check leaves the config folder unchanged.
  - `70-zsh links grove-themes into ~/.local/bin` (check needs work without the link; apply makes it).
- [ ] **Step 2: Run** `bats ../grove-themes/tests/cli.bats tests/modules_base.bats tests/modules_zsh.bats` — Expected: the new tests fail.
- [ ] **Step 3: Implement** the CLI, `state.sh`, the `05-config` check/apply additions (apply: after the link, `grove-themes render`; check: render into `mktemp -d` with `--config` and `cmp` each file), and the `70-zsh` link (`$GROVE_ROOT/../grove-themes/bin/grove-themes` → `~/.local/bin/grove-themes`, like `grove`).
- [ ] **Step 4: Run** the Step 2 command, `bats tests`, `bats ../grove-themes/tests`, shellcheck on the new files — Expected: all pass, silent.
- [ ] **Step 5: Commit** `grove-themes: list, current, set and render; grove renders on install`

---

### Task 5: `set` refreshes the apps and macOS

**Files:**
- Create: `../grove-themes/lib/steps.sh`, `../grove-themes/tests/set.bats`
- Modify: `../grove-themes/bin/grove-themes`, `../grove-themes/lib/render.sh` (R1 backup), `modules/85-macos-wallpaper/module.sh` + `tests/modules_wallpaper.bats`, `README.md` (85 row)

**Interfaces:**
- Consumes: Task 4's `gt_render_all`, `gt_current`; grove-dotfiles' `lib/link.sh` `grove_backup` (sourced from `$GROVE_ROOT/lib`).
- Produces: step functions, each printing one result line `name<TAB>live|next-prompt|next-launch|needs-you|failed<TAB>message` and returning 0/1:
  - `gt_step_ghostty` — `kill -USR2` each PID from `ps -axo pid=,comm=` ending `/Ghostty.app/Contents/MacOS/ghostty`; none running → live, "not running". Seam: `GROVE_PS` (default `ps`).
  - `gt_step_zsh` → next-prompt; `gt_step_static` → one line each for starship, eza, bat, fastfetch (live), vscode (live), yazi (next-launch).
  - `gt_step_appearance SCHEME` — `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true|false'`; denied → needs-you with the Automation hint `85-macos-wallpaper` uses.
  - `gt_step_accent SCHEME` — `defaults write -g AppleAccentColor -int 3`; `defaults write -g AppleHighlightColor -string "R G B Other"` from the scheme's `bg_visual` as 0–1 floats with 6 decimals.
  - `gt_step_wallpaper SCHEME` — sets every desktop to `$GROVE_ROOT/../grove-wallpapers/wallpaper-project-grove-SCHEME.png` (same AppleScript as `85-macos-wallpaper`).
  - R1 in `gt_render_all`: before replacing a target, if `$GROVE_STATE/theme-rendered/<path>` exists and differs from the target, `grove_backup` the target and print `backed up edited <path> to <dest>`; after moving, copy each new file to `theme-rendered/`.
- [ ] **Step 1: Failing tests** (`set.bats`, fakes via `stub` for `osascript`, `defaults`, `ps`, `kill` logging their args):
  - `set signals each running Ghostty` — fake `ps` lists two Ghostty PIDs and one other → `kill -USR2` for the two only.
  - `set with no Ghostty running is fine` (Review Focus 5).
  - `set turns macOS light for light schemes and dark for dark ones`.
  - `set sets the green accent and the scheme's highlight` — `light-medium` `bg_visual #EAEDC8` → `0.917647 0.929412 0.784314 Other`.
  - `set puts the scheme's wallpaper on every screen`.
  - `a denied Automation prompt doesn't stop the other steps` (Review Focus 5) — fake `osascript` fails → appearance and wallpaper needs-you, accent still written, exit 1.
  - `set backs up a hand-edited generated file` (Review Focus 1, R1) — edit the rendered Ghostty config, `set dark-hard` → backup holds the edit, output names it; an unedited file makes no backup.
  - `set --json lists every step` — one entry per step, names in spec §7 order.
  - `85-macos-wallpaper wants the current scheme's picture` — state `light-soft` → check needs work when screens show dark-medium; apply sets light-soft's.
- [ ] **Step 2: Run** `bats ../grove-themes/tests/set.bats tests/modules_wallpaper.bats` — Expected: new tests fail.
- [ ] **Step 3: Implement** `steps.sh`, wire them into `set` after step 1 (each runs regardless; any `failed`/`needs-you` → exit 1), R1, and `85-macos-wallpaper`'s file choice from the state file (read it directly; no dependency on grove-themes' lib).
- [ ] **Step 4: Run** `bats tests`, `bats ../grove-themes/tests`, shellcheck — Expected: all pass, silent.
- [ ] **Step 5: Commit** `grove-themes: set refreshes Ghostty, macOS appearance, highlight and wallpaper`

---

### Task 6: Open zsh windows follow at the next prompt

**Files:**
- Create: `config/zsh/conf.d/99-theme.zsh` (tracked, no colours of its own)
- Test: `tests/modules_zsh.bats`

**Interfaces:**
- Consumes: the state file; the generated `40-tools`, `85-autosuggest`, `98-highlight`.
- Produces: a `precmd` function `_grove_theme_precmd` that keeps the scheme it loaded in `_grove_theme_loaded` and, when the state file's scheme differs, re-sources the three files and updates `_grove_theme_loaded`. Prints nothing.

- [ ] **Step 1: Failing test** `an open shell picks up a new scheme at the next prompt` — in `zsh -i` with the test config: note the value `98-highlight` gives `ZSH_HIGHLIGHT_STYLES[command]`; render `light-soft` into the config copy and write the state; call `_grove_theme_precmd`; the value is now light-soft's. Then `unset 'ZSH_HIGHLIGHT_STYLES[command]'` and call it again: it stays unset (nothing re-sourced when the scheme didn't change).
- [ ] **Step 2: Run** `bats tests/modules_zsh.bats` — Expected: fails.
- [ ] **Step 3: Implement** `99-theme.zsh` (`add-zsh-hook precmd _grove_theme_precmd`; read the state with zsh builtins only, no subshell per prompt).
- [ ] **Step 4: Run** `bats tests` — Expected: all pass.
- [ ] **Step 5: Commit** `zsh: open shells take the new scheme at their next prompt`

---

### Task 7: fastfetch's Grove image for light schemes

**Files:**
- Create: `config/fastfetch/grove-light.png` (tracked) via a private one-off image script (not committed)
- Test: `tests/theme.bats`

- [ ] **Step 1: Failing test** `the light image matches the dark one's shape` — `grove-light.png` exists and `sips -g pixelWidth -g pixelHeight -g hasAlpha` reports 1004, 426, yes (same as `grove.png`).
- [ ] **Step 2: Run** `bats tests/theme.bats` — Expected: fails.
- [ ] **Step 3: Make it** with the image script: the same recolor as the light wallpapers (ink `#27332A`, camo toward the light bg), alpha kept from `grove.png`. Look at it on `#FDF6E3` before committing.
- [ ] **Step 4: Run** `bats tests` — Expected: all pass.
- [ ] **Step 5: Commit** `fastfetch: the Grove image in dark ink for light schemes`

---

### Task 8: Live on this Mac (the user reviews before merge)

- [ ] **Step 1:** `zsh -lc 'grove install'` then `grove check` — Expected: all ok; `cmp` of every generated file against the fixtures shows no difference (this Mac still looks the same).
- [ ] **Step 2:** `grove-themes set light-medium`, then `grove-themes set dark-medium`; read every step line; `git status` clean after both.
- [ ] **Step 3:** Hand over to the user to try all six live (Ghostty, a new and an open zsh window, VS Code, yazi after relaunch, Finder/menus, wallpaper), with the rulings R1, R2 and any made during the build. Wait for "merge it".
