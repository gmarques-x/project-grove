# grove-dotfiles VS Code (95-vscode) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** VS Code in Everforest Dark Medium with Grove Icons, JetBrains Mono 12 and Ghostty's terminal colors, set up and checked by a new module `95-vscode`.

**Architecture:**
- `config/vscode/settings.json` is linked into VS Code's user folder with `grove_link`.
- `config/vscode/grove-icons/` is a committed icon-theme extension (Seti recolored by `build.py`, a dev-only script).
- The module installs `sainnhe.everforest` by id and Grove Icons from a vsix it zips at apply time.

**Tech Stack:** bash 3.2, bats-core 1.14, shellcheck 0.11, `/usr/bin/zip`, `plutil`, VS Code 1.145 `code` CLI, Python 3 stdlib (build.py only).

**Spec:** `grove-dotfiles/docs/specs/2026-11-10-grove-vscode-design.md`. Read it first; §5 has the exact settings, §6 the icon rules, §7 check/apply, §8 the tests.

## Global Constraints

- Work on branch `vscode` **in the main checkout** (`~/Developer/project-grove`). Not a worktree: `05-config` refuses to run from one, and `~/.config` links into the main checkout.
- Module code runs under `/bin/bash` 3.2: no associative arrays, no `mapfile`, no `${var,,}`.
- `check` returns `0` ok, `1` failed, `3` needs work, `4` needs you, and never changes anything.
- Nothing is deleted: a replaced settings file goes through `grove_link`'s backup.
- Every `#RRGGBB` in `config/vscode/settings.json` and `config/vscode/grove-icons/grove-icon-theme.json` is in `theme/everforest-dark-medium` (tests/theme.bats).
- Test seams: `GROVE_CODE` (the `code` command), `GROVE_VSCODE_USER` (default `$HOME/Library/Application Support/Code/User`), `GROVE_BREW` (default `/opt/homebrew/bin/brew`; `code` is also looked for next to it).
- Extension ids: `sainnhe.everforest`; `grove.grove-icons` (publisher `grove`, name `grove-icons`), first version `1.0.0`. Icon theme id `grove-icons`, label `Grove Icons`.
- New config files must be `git add`ed before the tests run: tests copy only git-tracked config.
- Commits are signed (global config does it) and end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Don't push.

## Review Focus

1. **`code` not on PATH in a fresh run** (Homebrew just installed it): check must find `$(dirname "$GROVE_BREW")/code`, not report failed. Test in Task 3.
2. **The settings path has a space** ("Application Support"): link, backup and check must quote it. Tests in Tasks 3–4 use a `GROVE_VSCODE_USER` with a space.
3. **A different Grove Icons version is installed** (older or newer): check is needs work and apply reinstalls with `--force`. Test in Task 3 and Task 4.
4. **The Marketplace is unreachable**: apply returns 1 with `code`'s message shown, and doesn't claim success. Test in Task 4.
5. **VS Code saving settings through the link**: if VS Code replaces the link with a file on save, grove would silently stop managing it. Not testable in bats; checked by hand in Task 5.

---

### Task 1: Settings file

**Files:**
- Create: `config/vscode/settings.json` (exactly spec §5)
- Modify: `config/.gitignore` (add `!/vscode/` after `!/yazi/`)
- Modify: `tests/theme.bats:48-51` (add `"$GROVE_ROOT/config/vscode/settings.json"` to the palette test's file list)
- Create: `tests/modules_vscode.bats`
- Modify: `tests/config_allowlist.bats` (add `config/vscode/settings.json` to "tracked config entries are not ignored")

**Interfaces:**
- Produces: `config/vscode/settings.json`; helper `vsc_json FILE` in `tests/modules_vscode.bats` that prints FILE with `//` comment lines removed (`sed '/^[[:space:]]*\/\//d'`), so `jq` can read it.

- [ ] **Step 1: Create the branch**

Run: `git -C ~/Developer/project-grove switch -c vscode`

- [ ] **Step 2: Write the failing tests** in `tests/modules_vscode.bats` (`load helpers`, `setup() { grove_test_setup; }`):
  - `vscode: settings are valid JSON` — `vsc_json "$GROVE_CONFIG/vscode/settings.json" | jq -e . >/dev/null`.
  - `vscode: settings choose Everforest, Grove Icons and JetBrains Mono 12` — jq asserts: `workbench.colorTheme == "Everforest Dark"`, `workbench.iconTheme == "grove-icons"`, `everforest.darkContrast == "medium"`, `editor.fontFamily == "JetBrains Mono"`, `editor.fontSize == 12`, `editor.fontLigatures == true`, `terminal.integrated.fontFamily == "JetBrains Mono"`, `terminal.integrated.fontSize == 12`.
  - `vscode: terminal colors are Ghostty's` — the 17 values under `workbench.colorCustomizations["[Everforest Dark]"]`, read in the order foreground, ansiBlack, ansiRed, ansiGreen, ansiYellow, ansiBlue, ansiMagenta, ansiCyan, ansiWhite, then the eight ansiBright*, equal `foreground` then `palette = 0..15` from `config/ghostty/config` (`sed -n 's/^palette = [0-9]*=//p'`).
  - The allowlist and theme.bats edits above.

- [ ] **Step 3: Run them to see them fail**

Run: `bats tests/modules_vscode.bats tests/config_allowlist.bats tests/theme.bats`
Expected: the three vscode tests fail (no file); allowlist fails (ignored path).

- [ ] **Step 4: Add `settings.json` and the `.gitignore` line; `git add config/.gitignore config/vscode/settings.json`**

- [ ] **Step 5: Run the tests again**

Run: same command. Expected: all pass.

- [ ] **Step 6: Commit** — `git commit -m "vscode: settings for Everforest, Grove Icons and JetBrains Mono"`

---

### Task 2: Grove Icons

**Files:**
- Create: `config/vscode/grove-icons/build.py`
- Create (generated by build.py, then committed): `grove-icon-theme.json`, `seti.woff`, `package.json`, `NOTICE` in `config/vscode/grove-icons/`
- Modify: `tests/theme.bats` (add `"$GROVE_ROOT/config/vscode/grove-icons/grove-icon-theme.json"` to the palette test)
- Test: `tests/modules_vscode.bats`

**Interfaces:**
- Produces: `config/vscode/grove-icons/package.json` with `"name": "grove-icons"`, `"publisher": "grove"`, `"version": "1.0.0"`, `"displayName": "Grove Icons"`, `"engines": {"vscode": "^1.80.0"}`, `"contributes": {"iconThemes": [{"id": "grove-icons", "label": "Grove Icons", "path": "./grove-icon-theme.json"}]}`. Task 3 reads `version` from it.
- `build.py [SETI_DIR]` — SETI_DIR defaults to `/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/theme-seti/icons`. Writes into its own folder. Stdlib only. Prints the color mapping (`#seti -> name #everforest`, one per line).

- [ ] **Step 1: Write the failing tests** in `tests/modules_vscode.bats`:
  - `vscode: every icon has a palette color` — every `.iconDefinitions[].fontColor` (jq) is in `theme/everforest-dark-medium`; none is null.
  - `vscode: Grove Icons keeps every Seti icon` — skip unless the Seti JSON exists at the default path; `jq '.iconDefinitions|length'` equal for both, and `jq 'has("light")'` is false for Grove's.
  - `vscode: the icon theme points at its files` — `package.json`'s `contributes.iconThemes[0].path` file exists; the theme's `fonts[0].src[0].path` resolves (relative to the theme file) to `seti.woff`.
  - `vscode: NOTICE credits Seti UI and Microsoft` — grep both `Seti UI` and `Microsoft Corporation` and `MIT`.
  - theme.bats edit above.

- [ ] **Step 2: Run them to see them fail**

Run: `bats tests/modules_vscode.bats tests/theme.bats` — Expected: the four new tests fail.

- [ ] **Step 3: Write `build.py`**

Read the theme colors from `theme/everforest-dark-medium` (path relative to the script: `../../../theme/everforest-dark-medium`) by parsing `name = #RRGGBB` lines. Copy `seti.woff` unchanged. Load Seti's JSON, drop `light`, keep everything else, point `fonts[0].src[0].path` at `./seti.woff`, and replace each `fontColor` with `recolor()`:

```python
ACCENTS = ["red", "orange", "yellow", "green", "aqua", "blue", "purple"]
def recolor(hex6, pal):
    h, l, s = colorsys.rgb_to_hls(*rgb01(hex6))
    if s < 0.25:                      # greys go by lightness
        return pal["grey0"] if l < 0.40 else pal["grey1"] if l < 0.65 else pal["fg"]
    def dist(name):                   # hue distance on the circle
        d = abs(h - colorsys.rgb_to_hls(*rgb01(pal[name]))[0]); return min(d, 1 - d)
    return pal[min(ACCENTS, key=dist)]
```

Write `package.json` (Interfaces above). When `grove-icon-theme.json`'s new content differs from the committed one, bump the patch version (first run writes `1.0.0`). Write `NOTICE`: the MIT text for "Seti UI, Copyright (c) 2014 Jesse Weed" and for "VS Code theme-seti, Copyright (c) Microsoft Corporation", with a line saying the colors were changed to Everforest.

- [ ] **Step 4: Generate and stage**

Run: `python3 -I config/vscode/grove-icons/build.py && git add config/vscode/grove-icons`
Expected: the mapping printed (23 Seti colors), four files written. Paste the mapping into the task report so the user sees it in Task 5.

- [ ] **Step 5: Run the tests** — same command as Step 2. Expected: all pass.

- [ ] **Step 6: Commit** — `git commit -m "vscode: Grove Icons, VS Code's Seti icons in Everforest colors"`

---

### Task 3: Module `95-vscode`, check

**Files:**
- Create: `modules/95-vscode/module.sh`
- Modify: `README.md` (row after `90-terminal`: `` | `95-vscode` | VS Code: Everforest, Grove Icons and JetBrains Mono, settings linked from the tracked config | ``)
- Test: `tests/modules_vscode.bats`

**Interfaces:**
- Consumes: `config/vscode/settings.json` (Task 1), `config/vscode/grove-icons/package.json` `version` (Task 2); `grove_link_check TARGET LINK` from `lib/link.sh`; `grove_fail` from `lib/ui.sh`.
- Produces (used by Task 4):
  - `about` → `VS Code: Everforest, Grove Icons, JetBrains Mono`
  - `_vsc_code` → prints the `code` path: `$GROVE_CODE` if set, else `command -v code`, else `$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")/code` if executable; returns 1 when none.
  - `_vsc_settings` → `${GROVE_VSCODE_USER:-$HOME/Library/Application Support/Code/User}/settings.json`
  - `_vsc_icons` → `$GROVE_CONFIG/vscode/grove-icons`
  - `_vsc_icons_version` → `plutil -extract version raw -o - "$(_vsc_icons)/package.json"`
  - `_vsc_installed WANT` → 0 when `code --list-extensions --show-versions` has a line equal to WANT (`sainnhe.everforest` matches any version: compare WANT against the part before `@` when WANT has no `@`; compare case-insensitively).
  - `check` per spec §7.

**Fake `code`** (in `setup`, via `stub code '…'`; set `GROVE_CODE="$BATS_TEST_TMPDIR/stubs/code"` and `GROVE_VSCODE_USER="$BATS_TEST_TMPDIR/Application Support/Code/User"`): appends its arguments to `$BATS_TEST_TMPDIR/code-args`; `--list-extensions` prints `$BATS_TEST_TMPDIR/extensions` (lines like `sainnhe.everforest@0.3.0`); `--install-extension X`: exit 1 with `Failed Installing Extensions: X` on stderr when `FAKE_CODE_FAIL` is set; otherwise for `sainnhe.everforest` append `sainnhe.everforest@0.3.0`, for a `.vsix` copy it to `$BATS_TEST_TMPDIR/last.vsix`, drop any `grove.grove-icons@` line and append `grove.grove-icons@<version from unzip -p X extension/package.json>`.

Helper `vsc_ready` in the test file: links settings by hand (`mkdir -p`, `ln -s`) and writes both extensions at the current version into `extensions`.

- [ ] **Step 1: Write the failing tests:**
  - `vscode: about names it` — output equals the string above.
  - `vscode: failed without the code command` — `GROVE_CODE` unset, PATH without `code`, `GROVE_BREW="$BATS_TEST_TMPDIR/nobrew/brew"` → status 1, output mentions `grove install homebrew`.
  - `vscode: finds code next to brew` — `GROVE_CODE` unset, fake copied to `$BATS_TEST_TMPDIR/brew/bin/code`, `GROVE_BREW="$BATS_TEST_TMPDIR/brew/bin/brew"`, stub dir's `code` removed, `vsc_ready` → status 0. (Review Focus 1)
  - `vscode: needs work when settings aren't linked` — extensions ready, no link → 3.
  - `vscode: needs work without Everforest` → 3.
  - `vscode: needs work when Grove Icons is another version` — `grove.grove-icons@0.9.0` → 3; `@9.9.9` → 3. (Review Focus 3)
  - `vscode: ok when everything is in place` — `vsc_ready` → 0, and `code-args` holds no `--install-extension` (check changed nothing).
  - `vscode: the README lists the module` — `grep -q '^| \`95-vscode\` |' README.md`.

- [ ] **Step 2: Run to see them fail** — `bats tests/modules_vscode.bats` — Expected: the new tests fail (no module).

- [ ] **Step 3: Write `modules/95-vscode/module.sh`** (header comment naming the seams, like `85-macos-wallpaper`) with `about`, the helpers and `check`; add the README row.

- [ ] **Step 4: Run the tests and shellcheck**

Run: `bats tests/modules_vscode.bats && shellcheck modules/95-vscode/module.sh`
Expected: all pass, shellcheck silent.

- [ ] **Step 5: Commit** — `git commit -m "95-vscode: check VS Code's settings link and extensions"`

---

### Task 4: Module `95-vscode`, apply

**Files:**
- Modify: `modules/95-vscode/module.sh`
- Test: `tests/modules_vscode.bats`

**Interfaces:**
- Consumes: Task 3's helpers; `grove_link TARGET LINK` from `lib/link.sh`; `grove_note`, `grove_fail`.
- Produces: `_vsc_vsix DIR` → builds `DIR/grove-icons.vsix` and prints its path; `apply` per spec §7.

The vsix is a zip with `extension/` holding `package.json`, `grove-icon-theme.json`, `seti.woff`, `NOTICE` (not `build.py`), plus these two files at the root, `@VERSION@` replaced by `_vsc_icons_version`:

```xml
<!-- [Content_Types].xml -->
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".woff" ContentType="font/woff"/><Default Extension=".vsixmanifest" ContentType="text/xml"/><Default Extension="" ContentType="text/plain"/></Types>
```
```xml
<!-- extension.vsixmanifest -->
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata><Identity Language="en-US" Id="grove-icons" Version="@VERSION@" Publisher="grove"/><DisplayName>Grove Icons</DisplayName><Description xml:space="preserve">VS Code's Seti icons in Everforest colors</Description><Categories>Themes</Categories></Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
```

- [ ] **Step 1: Write the failing tests:**
  - `vscode: apply links the settings, installs both, then check is ok` — empty `extensions` → apply 0; settings is a link to `$GROVE_CONFIG/vscode/settings.json`; `code-args` has `--install-extension sainnhe.everforest` and one `.vsix … --force`; output mentions `next time it opens`; check → 0. (Uses the spaced `GROVE_VSCODE_USER`: Review Focus 2.)
  - `vscode: apply backs up an existing settings file` — a real `settings.json` with `{"a":1}` → after apply it's the link, and `$GROVE_STATE/backup/test/…/settings.json` holds `{"a":1}`.
  - `vscode: apply installs only what's missing` — Everforest present, icons missing → no `sainnhe.everforest` install in `code-args`.
  - `vscode: apply replaces another Grove Icons version` — `grove.grove-icons@9.9.9` → after apply `extensions` holds `grove.grove-icons@<package version>` only once. (Review Focus 3)
  - `vscode: the vsix holds the extension and its manifest` — after apply, `unzip -l last.vsix` lists `extension.vsixmanifest`, `[Content_Types].xml`, `extension/package.json`, `extension/grove-icon-theme.json`, `extension/seti.woff`, `extension/NOTICE`, and not `build.py`; the manifest's `Version` equals the package version.
  - `vscode: apply fails when code can't install` — `FAKE_CODE_FAIL=1` → status 1, output contains `Failed Installing Extensions`, no `next time it opens`. (Review Focus 4)

- [ ] **Step 2: Run to see them fail** — `bats tests/modules_vscode.bats` — Expected: the six apply tests fail.

- [ ] **Step 3: Implement `_vsc_vsix` and `apply`.** Build in `mktemp -d`, zip with `cd DIR && /usr/bin/zip -qrX grove-icons.vsix extension.vsixmanifest '[Content_Types].xml' extension`, remove the temp folder on every exit path (a `trap … RETURN` is not available in bash 3.2 functions reliably; clean up explicitly). Show `code`'s stderr on failure (don't send it to /dev/null).

- [ ] **Step 4: Run the whole suite and shellcheck**

Run: `bats tests && shellcheck modules/95-vscode/module.sh`
Expected: every test passes (284 + the new ones), shellcheck silent.

- [ ] **Step 5: Commit** — `git commit -m "95-vscode: link the settings and install Everforest and Grove Icons"`

---

### Task 5: Live on this Mac (the user reviews before merge)

**Files:** none changed unless the user asks.

- [ ] **Step 1: Install** — `zsh -lc 'grove install 95-vscode'` then `zsh -lc 'grove check'`. Expected: `95-vscode` ok, every other module unchanged.
- [ ] **Step 2: Open VS Code** (`open -a "Visual Studio Code" ~/Developer/project-grove`) and check by hand: Everforest Dark, Grove Icons in the explorer, JetBrains Mono in the editor and terminal, fastfetch and the prompt in the built-in terminal look like Ghostty.
- [ ] **Step 3: Link survives a save** (Review Focus 5) — toggle any setting in VS Code's Settings UI, then `test -L "$HOME/Library/Application Support/Code/User/settings.json"`. Expected: still a link, and `git status` shows the change in `config/vscode/settings.json`. Undo it with `git checkout config/vscode/settings.json`. If the link was replaced, stop and report: the settings approach needs rethinking.
- [ ] **Step 4: Hand over to the user** with the Task 2 color mapping and the sidebar-style option (`everforest.darkWorkbench`: material, flat, high-contrast). Wait for "merge it" before merging `vscode` into `main`.
