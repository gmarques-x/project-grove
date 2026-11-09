# grove-dotfiles · fastfetch with the Grove image (replaces macchina)

**Status:** approved design, 2026-11-09
**Builds on:** [2026-11-09-grove-terminal-design.md](2026-11-09-grove-terminal-design.md) (§8 macchina, §9 module `90-terminal`, §13 look revision)

## 1. Goal

The summary shown in every new terminal window keeps its look (a boxed "Grove" panel with icons, green labels, bars and color dots), but the text art on its left becomes a real image: the README banner's paper art, from the logo to the landscape, with rounded corners. fastfetch replaces macchina because macchina can only print text art.

**Success looks like this:**
- A new Ghostty window shows the image on the left and the boxed stats on the right, then the prompt.
- The box looks like today's: titled " Grove ", the same icons, labels green, separator glyph grey1, values fg, bars and eight color dots.
- The bars are colored: filled green, empty bg3 (macchina couldn't color them).
- Terminal.app, and windows too narrow for the image, show the current text art instead; very narrow windows show just the box.
- `grove check` reports `90-terminal` ok, and nothing installs or configures macchina anymore.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Tool | **fastfetch** replaces macchina | It can show images in Ghostty and color its bars; macchina can do neither. |
| Image | The banner reframed: logo to the landscape's rock, features row removed, made taller (aspect 1.61), rounded corners, 1004 × 624 PNG | Approved by the user after the spike. |
| Image tones | **Everforest night**, recolored from the theme: lightness picks a color on a palette ramp (paper bg0 → bg_green → fill → aqua → green → darkest ink fg), and the sun is the theme's yellow, drawn as a full disc behind the peak. The front pines and the rock (lower right) are removed into dark paper; the hills, lake and mountains behind them stay | Chosen by the user: first the swapped version, then "more green, following the theme colors". It blends into the terminal. |
| Image source | The PNG itself is committed (`config/fastfetch/grove.png`, ~1 MB) | It's derived from the banner the user made for the public README. The tool that made it stays private, like the other dev tools (see the private-files rule). |
| Image colors | The image is derived from the banner's paint, so it is **exempt** from the palette rule (made only of palette colors, but blended between them, so its pixels aren't exact palette hexes) | The palette rule covers config colors. Every color in the fastfetch config still comes from the palette (tested). |
| Size | Image 76 columns × 22 rows (the box's height); the whole summary needs ~140 columns | It matches the box; the width follows from the image's shape. |
| Narrow windows | ≥ 140 columns: image (1 + 76 + 3 + the 58-column box = 138). 125–139: today's text art (1 + 61 + 3 + 58 = 123). < 125: box only | Never wraps or overlaps. |
| Terminal.app | Text art (it can't show images) | Same as today. |
| Readouts | Same as macchina, except **Desktop** is dropped (fastfetch has nothing to show on macOS). **Machine** shows the model name ("MacBook Air (15-inch, M4, 2025)") instead of "Mac16,13" | Closest match. |
| CPU Load | **Kept** (~0.2 s per new window, fastfetch samples the CPU) | Parity with macchina; see §8. |
| macchina | Removed from the Brewfile, `config/`, the zsh hook and the tests | One summary tool. |

## 3. Out of scope

- Redrawing the image (it's approved as is).
- Images in other terminals (iTerm, kitty) beyond what fastfetch does on its own.
- Uninstalling macchina from Macs that already have it (Grove stops installing it; see §9 for this Mac).

## 4. Layout

```
grove-dotfiles/
├── Brewfile                              - brew "macchina", + brew "fastfetch"
├── config/
│   ├── .gitignore                        - !/macchina/, + !/fastfetch/
│   ├── fastfetch/
│   │   ├── config.jsonc                  the box, readouts, colors; logo = grove.png
│   │   ├── grove.png                     the image
│   │   └── grove.ascii                   the text art (moved from macchina/)
│   ├── macchina/                         removed
│   └── zsh/conf.d/95-fetch.zsh           renamed from 95-macchina.zsh
├── modules/90-terminal/module.sh         checks fastfetch instead of macchina
└── tests/                                updated (§10)
```

## 5. The config (`config/fastfetch/config.jsonc`)

- **Logo:** `kitty-direct` (Ghostty reads the file itself), source `~/.config/fastfetch/grove.png` (fastfetch expands `~`; checked), width 76, height 22, aspect kept, padding left 1, right 3.
- **Box:** inner width 56, drawn with fastfetch's own constants: `┌ Grove ───┐`, `│ … │` rows (left edge, jump right, right edge, jump back) and `└───┘`; an empty row under the title and above the dots, as today. Border and title fg.
- **Readouts, in order:** Host (`user@host`), Machine, Kernel, OS (`name version`), WM, Packages (`N (Homebrew)`), Terminal, Shell, Local IP (IPv4), Brightness (bar), Resolution (`W×H @ Hz`), Uptime, CPU, CPU Load (bar, if kept), Memory (bar), Battery (bar), then the color dots.
- **Keys:** the same Nerd Font icons as macchina's `[keys]`, padded to one width; labels green `#A7C080`.
- **Separator:** `` in grey1 `#859289`; values fg `#D3C6AA`.
- **Bars:** 10 × `▮ `, filled green `#A7C080`, empty bg3 `#475258`, no brackets.
- **Colors:** written as palette hex wherever fastfetch accepts it. Box borders need raw escapes (`38;2;R;G;B`); the palette test also reads those (§10).

## 6. When it runs (`conf.d/95-fetch.zsh`)

Same rules as today: once per new window in Ghostty or Terminal.app, quiet in nested shells (`GROVE_FETCHED`), off with `GROVE_NO_FETCH=1`, only when stdout is a terminal, and only if fastfetch is installed. Then it picks the logo:

| Where | Logo |
| --- | --- |
| Ghostty, ≥ 140 columns, image present | the image (the config's default) |
| Ghostty 125–139 columns, or Terminal.app, or the image is missing | `--logo-type file --logo ~/.config/fastfetch/grove.ascii`, colored aqua `#83C092` |
| < 125 columns | `--logo none` |

`cls` keeps working: it clears the screen (images included) and reloads, like a new window.

## 7. Module `90-terminal`

Unchanged except: `_term_installed` looks for `fastfetch` (on PATH or next to brew) instead of `macchina`; `about` says "Ghostty, the prompt and fastfetch"; the apply error names fastfetch.

## 8. CPU Load

fastfetch measures CPU load by sampling for ~0.2 s, so with it every new window waits 0.2 s before the summary (macchina: 0.03 s). Without it the summary is instant and the box loses one line.

**Decision:** kept, for parity with today (the recommended default; the user didn't ask to drop it). Dropping it later is one line in the config.

## 9. Rollout on this Mac

`grove install` (Homebrew installs fastfetch; `~/.config` already points at the repo). macchina stays installed but unused; `brew uninstall macchina` is offered at the end and run only with the user's OK.

## 10. Testing

- **Palette:** the fastfetch config joins "every config color comes from the palette"; `38;2;R;G;B` triples in it are converted to hex and checked too. The PNG is not checked (§2).
- **Config:** fastfetch accepts it (runs with `--pipe` against a temp HOME, exit 0, no "Error"); readouts in the spec's order; the logo is `kitty-direct`, 76 × 22, pointing at `~/.config/fastfetch/grove.png`; bar colors and characters as in §5.
- **Box:** replaying the output through a small terminal emulator in the test gives a box exactly 58 columns wide with `│` on both sides of every row (catches overflow like the old Resolution line).
- **Files:** `config/fastfetch/{config.jsonc,grove.png,grove.ascii}` are tracked; nothing under `config/macchina/` remains.
- **Hook (`95-fetch.zsh`):** the existing when-it-runs tests, ported to a fake fastfetch that prints its arguments; plus the logo choice: image at 160 columns in Ghostty; text art at 130 columns, in Terminal.app, and when `grove.png` is missing; `--logo none` at 100 columns.
- **Module:** the existing `90-terminal` tests with fastfetch in place of macchina.
- **Brewfile:** has fastfetch, not macchina.
