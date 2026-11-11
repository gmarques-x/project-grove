# Avatar wallpapers · a second desktop wallpaper set, chosen in Grove Themes

**Status:** design for review, 2026-11-11
**Builds on:** [2026-11-11-avatar-logo-design.md](2026-11-11-avatar-logo-design.md) (the avatar drawing, the logo choice pattern), [2026-11-10-grove-themes-design.md](2026-11-10-grove-themes-design.md) (the wallpaper step, `set`)

## 1. Goal

The desktop can show the avatar's tree-ring drawing instead of the Project Grove lockup, in each scheme's colours. Which wallpaper set is used is its own setting in Grove Themes, chosen from the CLI, the gallery and the dropdown, independent of the terminal logo.

**Success looks like this:**
- `grove-themes wallpaper avatar` puts the drawing on every screen and Space, in the current scheme's colours.
- Every later `set <scheme>` keeps the avatar wallpaper.
- `grove-themes wallpaper grove` brings back today's wallpapers.
- The same choice can be made from the gallery's "Wallpaper" row and the dropdown.
- `grove check` reports `85-macos-wallpaper` ok with either choice.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Setting | Its own choice (`grove` / `avatar`), apart from the terminal logo | Chosen by the user: logo and wallpaper can be mixed. |
| Picture | The avatar drawing (the terminal logo's crop: no prompt, no dots), centred on the scheme's bg0 | Matches the avatar logo. |
| Colour | Paper tone #DAC7A2 on dark schemes, ink #27332A with the light treatment on light ones | Same as the logo and the Grove wallpapers. |
| Files | Made once by a private script, committed | Same as the Grove wallpapers. |
| Picker | CLI + gallery + dropdown | As for the logo. |

## 3. Out of scope

- Wallpapers that mix the lockup and the avatar.
- Per-screen or per-Space choices.
- Changing the Grove wallpapers.

## 4. The images

- **Generator:** `artifacts/avatar-logo/wallpapers.py` (private). It renders the avatar drawing at high resolution (`make.py`'s recipe at a larger scale, so the lines stay sharp at desktop size). It centres the drawing on each scheme's bg0 on a 2880×1864 canvas, about 820 px tall. Light schemes use the logo's light recolour toward that scheme's bg0.
- **Outputs** in `grove-wallpapers/` (tracked): `wallpaper-avatar-<scheme>.png` for the six schemes. They're exempt from the palette rule, like the Grove wallpapers.
- **Review gate:** a dark and a light draft go to the user before anything else is built.

## 5. Choosing the wallpaper

**State:** `$GROVE_STATE/wallpaper` holds `grove` or `avatar`. A missing or unknown value (after trimming whitespace) means `grove`.

**grove-themes:**
- `gt_wallpaper` reads the state; `gt_wallpapers` prints `grove avatar`.
- `gt_step_wallpaper SCHEME` uses `wallpaper-$(gt_wallpaper)-SCHEME.png`; everything else in the step (every screen, every Space via the store, the messages) is unchanged. `set` therefore keeps the choice.
- `grove-themes wallpaper` prints the choice, or `{"wallpaper": "<name>"}` with `--json`.
- `grove-themes wallpaper <grove|avatar>` checks the file for the current scheme exists, saves the choice, then runs the wallpaper step for the current scheme. It doesn't touch the configs. It logs the step's line (`{"name": "wallpaper", …}`) under the current scheme and prints it like `set` prints its steps, or `{"wallpaper": "<name>", "steps": [ … ]}` with `--json`. Exit 1 when the step fails or needs you; other names: usage, exit 2. Only the answer goes to stdout.
- `list --json` gains `"wallpaper"` and `"wallpapers": ["grove", "avatar"]`.

**grove-dotfiles:** `85-macos-wallpaper` expects `wallpaper-<choice>-<scheme>.png`, reading the choice from the same state file with the same rule.

## 6. Grove Themes app

- `SchemeList` decodes `wallpaper` and `wallpapers`, defaulting to `grove` and both names when absent.
- `GroveThemesClient.setWallpaper(_:)` runs `wallpaper <name> --json`. A step that needs you or fails comes back as the result, as with `set`.
- `ThemesModel.pickWallpaper(_:)` runs it and refreshes. A failed or needs-you step shows the way a scheme switch's does.
- **Gallery:** a "Wallpaper" row below the "Terminal logo" row: two cards, each a thumbnail of that wallpaper for the current scheme (from `grove-wallpapers/`). The chosen one has the green border. The window grows to fit.
- **Dropdown:** a "WALLPAPER" row of two buttons below "TERMINAL LOGO".
- **Focus grid:** the wallpaper row sits between the logo row and the dropdown's menu rows, with the same column rule as the logo row.

## 7. Errors

| Situation | What happens |
| --- | --- |
| State missing, empty or unknown | Treated as `grove`. |
| Chosen file missing for the current scheme | `wallpaper <name>` fails with `wallpaper not found: <path>` and doesn't save the choice. |
| Automation refused | The step says needs-you with the existing hint. The choice is saved, so the next switch applies it. |
| No wallpaper store | As today: visible Spaces updated, with the existing message. |

## 8. Testing

- **grove-themes bats:**
  - `gt_wallpaper` defaults and trimming.
  - The step picks `wallpaper-avatar-<scheme>.png` on a dark and a light scheme.
  - `set` keeps the choice.
  - The `wallpaper` command: printing, JSON, usage exit 2, missing file not saved, the log step, stdout holding only the answer.
  - `list --json` fields.
- **grove-dotfiles bats:** `85-macos-wallpaper` expects the chosen file; the six avatar wallpapers are tracked.
- **Swift:**
  - Decoding with and without the fields.
  - The focus grid's wallpaper row.
  - `pickWallpaper` runs the CLI and refreshes.
  - A needs-you result shows.
- **By hand, with the user:**
  - The drafts.
  - Switching from the CLI, the gallery and the dropdown.
  - Another Space.
  - A scheme switch keeping the avatar wallpaper.
  - `grove check`.
