# Avatar terminal logo · a second fastfetch image, chosen in Grove Themes

**Status:** design for review, 2026-11-11
**Builds on:** [2026-11-09-grove-fastfetch-design.md](2026-11-09-grove-fastfetch-design.md) (the logo, box and hook), [2026-11-10-grove-themes-design.md](2026-11-10-grove-themes-design.md) (templates, state, CLI, GUI)
**Source image:** the GitHub avatar of gmarques-x (460×460, kept privately)

## 1. Goal

New terminal windows can show the user's GitHub avatar (the tree-ring drawing) instead of the Project Grove lockup, coloured the way the lockup is: paper tone on dark schemes, dark ink on light schemes. Grove Themes chooses between the two logos, from the CLI, the gallery and the dropdown.

**Success looks like this:**
- `grove-themes logo avatar`, then a new Ghostty window, shows the tree-ring drawing beside the Grove box, in the right tone for the current scheme.
- `grove-themes logo grove` brings back today's output exactly.
- Switching schemes keeps the chosen logo.
- The same choice can be made from the gallery's "Terminal logo" row and the dropdown's submenu.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Content | The whole drawing: rings, FIG.01 corners, *Pinus sylvestris*, pine sprig, Ø 48 cm / 21 rings, `> gmarques-x` with cursor, the four dots; grid paper removed | Chosen by the user. |
| Colour | One ink tone, as the lockup: #DAC7A2 on dark schemes, #27332A on light; the drawing's texture kept; former accents slightly lighter (dark) or darker (light) so they still read | Chosen by the user. |
| Files | Made once by a script, committed as PNGs | Same as `grove.png`; no Pillow on every Mac, no dependence on the avatar URL. |
| Picker | CLI + gallery + dropdown | Chosen by the user. |
| Scope of the choice | One choice for all six schemes, stored apart from the scheme | The user picks a logo, not a logo per scheme. |
| Text fallback | `grove.ascii` for both logos | A text-art avatar is separate work. |

## 3. Out of scope

- A text-art (ASCII) avatar.
- Using the avatar on wallpapers, the README or anywhere outside fastfetch.
- Fetching the avatar automatically or keeping it in sync with GitHub.

## 4. The images

- **Generator:** a private script, `make.py` (like the lockup script; Pillow + numpy in a scratch venv). It reads `avatar.png` and finds the ink against the paper and grid (ink is darker and less saturated than the paper; the grid's thin light lines are dropped). Alpha comes from ink strength, with the lockup's ramp (t 0.2–0.45). The drawing is cropped to the ink's bounding box plus a small margin, upscaled with LANCZOS to about 4× for crisp cells, and written in the two tones.
- **Outputs** in `grove-dotfiles/config/fastfetch/` (tracked):
  - `avatar.png`: #DAC7A2, for dark schemes.
  - `avatar-light-hard.png`, `avatar-light-medium.png`, `avatar-light-soft.png`: #27332A, made with the same treatment as the matching `grove-light-*.png`.
- **Shown at** about 34×17 cells (the exact width follows the cropped aspect, at 17 rows), padding left 1, right 3, top 2, so it sits centred beside the 22-row box. The PNGs are exempt from the palette rule, like `grove.png`.
- **Review gate:** a draft of the dark file and one light file goes to the user before the rest is built.

## 5. Choosing the logo

**State:** `$GROVE_STATE/fetch-logo` holds `grove` or `avatar`. A missing or unknown value means `grove`.

**Renderer** (`grove-themes/lib/render.sh`, `gt_values`) adds:
- `fetch_logo`: `grove` or `avatar`, from the state file.
- `fetch_image`: becomes the image for the chosen logo and scheme (`grove.png`, `grove-light-<contrast>.png`, `avatar.png` or `avatar-light-<contrast>.png`).
- `fetch_width`, `fetch_height`, `fetch_pad_top`: 76/15/3 for grove, the avatar's values for avatar.
- `fetch_min_cols`: 140 for grove, 96 for avatar (image width + 4 + the 58-column box).

**Templates:**
- `config/fastfetch/config.jsonc.tmpl` takes the width, height and top padding from these values.
- `config/zsh/conf.d/95-fetch.zsh.tmpl` takes `{{fetch_min_cols}}` instead of the literal 140. The text-art rule (≥125 columns or Terminal.app) is unchanged.

With `grove`, both renders are byte-identical to today's.

## 6. Grove Themes

**CLI** (`grove-themes/bin/grove-themes`):
- `grove-themes logo` prints the current logo.
- `grove-themes logo <grove|avatar>`:
  1. renders `fastfetch/config.jsonc` and `zsh/conf.d/95-fetch.zsh` for the current scheme with the new value;
  2. only if both succeed, writes the state file;
  3. appends a log entry (`"logo": "<name>"`, scheme unchanged).
  Any other name: usage on stderr, exit 2.
- `--json` on `logo` gives `{"logo": "<name>"}`.
- `list --json` gains `"logo"` and `"logos": ["grove", "avatar"]`.
- `set <scheme>` keeps the logo, because the renderer reads the state each time.

**App** (`grove-themes/app`, SwiftUI):
- `SchemeList` decodes `logo` and `logos`.
- **Gallery:** a "Terminal logo" row below the scheme cards, with two small cards (*Project Grove*, *Avatar*). Each shows its image for the current scheme on a mini terminal background; the chosen one has the green border. The focus grid gains the row (arrows / Ctrl+H/J/K/L, Enter picks).
- **Dropdown:** a "Terminal logo" line with the current name and a submenu of both.
- Picking runs `grove-themes logo <name>` and refreshes. Errors show as for a scheme switch.
- **Card images:** the app reads the PNGs from the fastfetch config folder (`~/.config/fastfetch/`), choosing the variant for the current scheme.

New terminal windows show the change; open ones keep what they showed.

## 7. Errors

| Situation | What happens |
| --- | --- |
| `fetch-logo` missing, empty or unknown | Treated as `grove`; the next `logo <name>` rewrites it. |
| Chosen image missing on disk | The hook's existing readable check falls back to the text art. |
| A re-render fails during `logo` | Non-zero exit with the step's message; the state file is unchanged. |
| App can't read a card image | The card shows the name only. |

## 8. Testing

- **grove-themes bats:**
  - `logo` defaults to `grove`.
  - `logo avatar` renders the avatar values on a dark and a light scheme.
  - `logo grove` renders byte-identical to the current Dark Medium fixture.
  - An unknown name exits 2.
  - `--json` and `list --json` include the logo fields.
  - `set` keeps the logo.
  - A failed render leaves the state unchanged.
  - Log entries.
- **grove-dotfiles bats:**
  - The four avatar PNGs are tracked.
  - Every template renders for all six schemes with both logos.
  - The fastfetch and hook fixtures for grove are unchanged.
- **Swift (Grove Themes app):** decoding the logo fields; the focus grid with the logo row.
- **By hand, with the user:**
  - The images in Ghostty on a dark and a light scheme.
  - Switching from the gallery and from the dropdown.
  - A narrow window to see the text fallback.
