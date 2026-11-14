# Avatar Terminal Logo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second fastfetch logo made from the user's GitHub avatar (dark and light tones), chosen in Grove Themes from the CLI, gallery and dropdown.

**Architecture:** A private script turns the avatar into four committed PNGs. grove-themes keeps the choice in `$GROVE_STATE/fetch-logo` and exposes it to the templates as new computed values, so the fastfetch config and the fetch hook pick the image, size and column threshold. A new `logo` CLI command re-renders those two files; the SwiftUI app adds a logo row and a submenu that call it.

**Tech Stack:** Python 3 + Pillow + numpy (scratch venv, generator only), bash + bats (grove-themes, grove-dotfiles), Swift 6 / SwiftUI with Swift Testing (Grove Themes app, Command Line Tools).

**Spec:** `grove-dotfiles/docs/specs/2026-11-11-avatar-logo-design.md`

## Global Constraints

- Work on branch `avatar-logo` in `~/Developer/project-grove`; merge only when the user says "merge it". Never commit the private working folders.
- `~/.config` links into this checkout: rendered files there are live. Don't leave the live fastfetch config or hook broken.
- Logo names exactly `grove` and `avatar`; state file `$GROVE_STATE/fetch-logo`; missing/unknown → `grove`.
- Tones: dark `#DAC7A2`, light `#27332A`; alpha ramp t 0.2–0.45 (as the lockup). PNGs exempt from the palette rule, like `grove.png`.
- Files: `grove-dotfiles/config/fastfetch/avatar.png`, `avatar-light-{hard,medium,soft}.png`.
- Grove values: width 76, height 15, pad top 3, min cols 140. Avatar: height 17, width from the cropped aspect, pad top 2, min cols = width + 62.
- With `grove`, every render is byte-identical to today's (fixtures prove it).
- Never run grove-themes and grove-dotfiles bats files in one bats call. The grove-dotfiles full suite takes ~12 min (background).

## Review Focus

- **A user-edited `fetch-logo` with a trailing newline or spaces** (`avatar\n`, ` avatar`): it should still read as `avatar`. Test in Task 2.
- **Switching scheme after choosing the avatar:** `set light-soft` must render `avatar-light-soft.png`, not the grove image. Test in Task 2.
- **A logo switch while the template renders fail:** the state stays as it was, and the next window still gets a working config. Test in Task 3.
- **An app built before this change reading the new `list --json`:** the extra keys must not break decoding. Test in Task 4: decoding without `logo`/`logos` still works and defaults them.
- **Narrow Ghostty windows between 96 and 139 columns:** with the avatar they show the image, and with grove the text art, as today. Test in Task 2 (render) and by hand in Task 5.

---

### Task 1: The avatar images (review gate)

**Files:**
- Create: a private script (`make.py`), `grove-dotfiles/config/fastfetch/avatar.png`, `avatar-light-hard.png`, `avatar-light-medium.png`, `avatar-light-soft.png`
- Read: the avatar image and the private lockup script (the lockup's ink/alpha recipe), and the existing `grove.png` / `grove-light-*.png` (target look)

- [ ] **Step 1:** Write `make.py` (venv in the scratchpad, `pip install pillow numpy`). Ink mask against paper + grid; alpha from ink strength with the t 0.2–0.45 ramp; remove the grid lines; crop to the ink bounding box + 2% margin; upscale ×4 LANCZOS; write the dark file in #DAC7A2 and the three light files in #27332A, each light one treated like its `grove-light-*` counterpart. Print each output's size and the cell width at 17 rows (`round(17 * 2 * w / h)`, terminal cells being about twice as tall as wide).
- [ ] **Step 2:** Make previews: each PNG composited on its scheme's bg0 (dark medium #2D353B; light hard/medium/soft from `grove-dotfiles/theme/`), kept privately.
- [ ] **Step 3: Review gate.** Show the user the dark and light-medium previews. Iterate on the user's feedback. Don't start Task 2 until they approve the look.
- [ ] **Step 4:** Commit the four PNGs: `grove-dotfiles: avatar fastfetch images`.

### Task 2: Logo state and render values

**Files:**
- Modify: `grove-themes/lib/render.sh` (`gt_values`), the state helpers used by `gt_current`, `grove-dotfiles/config/fastfetch/config.jsonc.tmpl` (width/height/top padding), `grove-dotfiles/config/zsh/conf.d/95-fetch.zsh.tmpl` (`{{fetch_min_cols}}` for 140), `grove-dotfiles/tests/templates.bats` (the allowed computed names)
- Test: `grove-themes/tests/render.bats`, `grove-dotfiles/tests/templates.bats`

**Interfaces:**
- Produces: `gt_logo` (prints `grove` or `avatar` from `$GROVE_STATE/fetch-logo`; trims whitespace; anything else → `grove`); `gt_values` emits `fetch_logo`, `fetch_image`, `fetch_width`, `fetch_height`, `fetch_pad_top`, `fetch_min_cols`; `gt_logos` prints `grove avatar`.

- [ ] **Step 1: Write the failing tests** in `render.bats`:
  - `logo defaults to grove` (no state file).
  - `logo reads avatar with surrounding whitespace` (Review Focus).
  - `unknown logo is grove`.
  - `grove values are today's` (`fetch_image grove.png`, `fetch_width 76`, `fetch_height 15`, `fetch_pad_top 3`, `fetch_min_cols 140` on dark-medium; `grove-light-soft.png` on light-soft).
  - `avatar values` (`avatar.png` / `avatar-light-soft.png`, height 17, the Task 1 width, pad top 2, min cols width + 62).
  - `set-like scheme change keeps the avatar` (values for light-soft with state avatar → `avatar-light-soft.png`; Review Focus).
  - In `templates.bats`, `grove render is unchanged`: rendering fastfetch and the hook for dark-medium with no state equals the existing fixtures byte for byte; `every template renders for both logos`.
- [ ] **Step 2: Run** (`bats tests/render.bats` from grove-themes; `bats tests/templates.bats` from grove-dotfiles, separately) → FAIL.
- [ ] **Step 3: Implement** and update the two templates and the allowed-names list.
- [ ] **Step 4: Run** both → PASS. Re-render the live files (`grove-themes render`) and diff them against HEAD: no change with no state file.
- [ ] **Step 5: Commit** `grove-themes: logo state and fetch values`.

### Task 3: `grove-themes logo` and `list --json`

**Files:**
- Modify: `grove-themes/bin/grove-themes` (dispatch, usage, `cmd_logo`, `cmd_list` JSON), `grove-themes/README.md`
- Test: `grove-themes/tests/cli.bats`

**Interfaces:**
- Consumes: `gt_logo`, `gt_logos`, `gt_render_file`, `gt_log_append`.
- Produces:
  - `grove-themes logo [grove|avatar] [--json]`. With no name it prints the logo, or `{"logo": "<name>"}` with `--json`. With a name it:
    1. renders `fastfetch/config.jsonc.tmpl` and `zsh/conf.d/95-fetch.zsh.tmpl` for the current scheme, using the new logo, into temp outputs;
    2. only if both succeed, moves them into place and writes the state file;
    3. logs a step `{"name": "logo", "result": "live", "message": "<name>"}` via `gt_log_append <current scheme> 0 …`;
    4. prints `grove-themes: logo <name>`, or `{"logo": "<name>"}` with `--json`.
  - On a render failure it exits 1 with the message and leaves the state and both files untouched. An unknown name prints usage to stderr and exits 2.
  - `list --json` adds `"logo": "<name>", "logos": ["grove", "avatar"]`.
- Ruling against spec §6 (the log entry): spec §6 says a `"logo"` field. It becomes a step named `logo` instead, so existing log readers (the app's `LogEntry`) keep decoding.

- [ ] **Step 1: Write the failing tests:**
  - `logo prints grove by default`.
  - `logo avatar writes state, renders both files with avatar values, logs a logo step`.
  - `logo grove restores today's renders byte for byte`.
  - `logo --json`.
  - `logo bogus exits 2`.
  - `logo with a failing render keeps state and files` (make the fastfetch template unreadable in the test copy; Review Focus).
  - `list --json has logo and logos`.
  - `set keeps the logo` (`logo avatar`, then `set light-medium` renders `avatar-light-medium.png`).
- [ ] **Step 2: Run** `bats tests/cli.bats` → FAIL. **Step 3: Implement**, including the usage text and a README section. **Step 4: Run** cli.bats, then the whole grove-themes suite → PASS.
- [ ] **Step 5: Commit** `grove-themes: logo command`.

### Task 4: Grove Themes app: logo row and submenu

**Files:**
- Modify: `grove-themes/app/Sources/GroveThemesCore/Models.swift` (`SchemeList.logo`, `.logos`, decoded with defaults `grove` / `["grove","avatar"]` when absent), `CLI.swift` (`setLogo(_:) async throws`), `FocusGrid.swift` (a `.logo(String)` item and a logo row in the gallery layout, between the cards and anything below), `ThemesModel.swift` (`logo`, `pickLogo(_:)`)
- Modify: `grove-themes/app/Sources/GroveThemes/GalleryView.swift` (the "Terminal logo" row: two cards, each showing its PNG for the current scheme from `~/.config/fastfetch/` on a bg0 mini terminal; green border on the chosen one; name only if the image can't be read), `DropdownView.swift` (a "Terminal logo" line with the current name and a submenu)
- Test: `Tests/GroveThemesCoreTests/ModelsTests.swift`, `FocusGridTests.swift`, `ThemesModelTests.swift`, `ClientTests.swift`

**Interfaces:**
- Consumes: `grove-themes logo <name> --json`, `list --json`.
- Produces: `ThemesModel.pickLogo(_ name: String) async`. It runs the CLI, then refreshes the list. On failure it shows the error the same way a failed scheme switch does.

- [ ] **Step 1: Write the failing tests:**
  - `decodes logo fields`.
  - `decodes old list without logo fields` (Review Focus).
  - `gallery grid has a logo row and moves into it with down`.
  - `Enter on a logo item picks it`.
  - `pickLogo runs "logo avatar --json" and refreshes` (with the fake client).
- [ ] **Step 2: Run** `swift test` in `grove-themes/app` → FAIL. **Step 3: Implement.** **Step 4: Run** `swift test` → PASS; `swift build -c release` → succeeds.
- [ ] **Step 5: Commit** `grove-themes: logo picker in the app`.

### Task 5: Install and check by hand

- [ ] **Step 1:**
  1. Run `grove install themes-app`, which rebuilds the app.
  2. Run the full grove-dotfiles suite in the background → all pass.
  3. Run `grove check` → all ok.
- [ ] **Step 2: With the user:**
  - In Ghostty, check `grove-themes logo avatar` on a dark scheme and a light scheme.
  - Switch from the gallery row and from the dropdown.
  - Open a 100-column window: avatar image; then `logo grove`: text art.
  - Open Terminal.app: text art.
  - Run `logo grove` and check that the output is today's.
- [ ] **Step 3:** Copy the ledger to the private notes. Wait for "merge it".
