# grove-dotfiles · Terminal (Ghostty, Starship, macchina)

**Status:** approved design, 2026-11-09
**Builds on:** [2026-11-09-grove-dotfiles-foundation-design.md](2026-11-09-grove-dotfiles-foundation-design.md)

## 1. Goal

Ghostty becomes the Project Grove terminal:
- Everforest Dark Medium, a solid window, JetBrains Mono 14 with ligatures;
- a ⌃` quick terminal that drops down from any app;
- it takes Terminal's place in the Dock, and Terminal.app stays installed as a fallback.

The Starship prompt keeps its layout and colors and gains icons, which Ghostty draws without a patched font. macchina shows a short Everforest summary in every new window.

On a fresh Mac, `grove install` sets all of this up. On this Mac, running it again moves Terminal's Dock slot to Ghostty and changes nothing else.

**Success looks like this:**
- `grove check` reports `90-terminal` ok.
- A new Ghostty window shows the macchina summary, then the prompt with icons.
- ⌃` toggles the quick terminal, once Ghostty is allowed under Accessibility.
- The Dock reads Ghostty, Safari, System Settings.
- Terminal.app still works, with the icon-free prompt and no broken glyphs.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Variant (design study D1) | Everforest **Dark Medium** | Upstream's default, the best contrast balance in the study, and the prompt already uses it. |
| Surfaces (D4) | **Solid** window, `background-opacity = 1` | Every contrast number in the study holds; nothing depends on the wallpaper. |
| Overrides (D5) | Allowed, but only in one place: the palette file's "Grove additions" section | Every app gets the same change, and a test enforces it. |
| Font | JetBrains Mono 14, ligatures on | Comfortable on a MacBook Air; ligatures are the reason for the ligature family. |
| Icons | Nerd Font glyphs, drawn by Ghostty's built-in symbol font | No patched font to install. Terminal.app can't draw them, so it gets a plain prompt. |
| macchina | Every new window, readouts: Machine & OS, Resources, Shell & terminal | Chosen by the user. Quiet in nested shells and tools, through an inherited `GROVE_FETCHED` marker. |
| Dock | Ghostty replaces Terminal in its slot | Chosen by the user. Terminal.app stays installed. |
| Structure | One module, `90-terminal`; configs live in `config/`; Homebrew installs the apps | `~/.config` already links into the repo, so only checks and the Dock need code. |

## 3. Out of scope

- Light variants and following macOS Appearance (D2).
- Editor module.
- Shell plugins and completions.
- Ghostty themes for other variants.
- Granting the Accessibility permission. macOS allows only the user to do that, so it's a printed manual step.

## 4. Layout

```
grove-dotfiles/
├── Brewfile                          + cask "ghostty", + brew "macchina"
├── theme/
│   └── everforest-dark-medium        palette: upstream colors + Grove additions
├── config/
│   ├── .gitignore                    + !/ghostty/, + !/macchina/
│   ├── ghostty/config
│   ├── macchina/macchina.toml
│   ├── macchina/themes/grove.toml
│   ├── macchina/grove.ascii          the tree mark
│   ├── starship.toml                 prompt with icons
│   ├── starship-plain.toml           prompt without icons (Terminal.app)
│   └── zsh/conf.d/
│       ├── 90-prompt.zsh             chooses the Starship config, then inits Starship
│       └── 95-macchina.zsh           the summary on new windows
├── modules/90-terminal/module.sh
└── tests/
    ├── modules_terminal.bats
    └── theme.bats
```

## 5. Palette file

`theme/everforest-dark-medium` holds one `name = #RRGGBB` pair per line, with `#` comments. Sections:

- **Upstream** (from `autoload/everforest.vim`, MIT), Dark Medium:
  - backgrounds: `bg_dim #232A2E`, `bg0 #2D353B`, `bg1 #343F44`, `bg2 #3D484D`, `bg3 #475258`, `bg4 #4F585E`, `bg5 #56635F`, `bg_visual #543A48`, `bg_red #514045`, `bg_yellow #4D4C43`, `bg_green #425047`, `bg_blue #3A515D`, `bg_purple #4A444E`;
  - foregrounds: `fg #D3C6AA`, `red #E67E80`, `orange #E69875`, `yellow #DBBC7F`, `green #A7C080`, `aqua #83C092`, `blue #7FBBB3`, `purple #D699B6`, `grey0 #7A8478`, `grey1 #859289`, `grey2 #9DA9A0`.
- **Grove additions:**
  - `fill #596763`: the prompt's `─` line, carried over from the Everforest zsh port.
  - Bright black: `grey1` instead of upstream's `bg3`, so dim terminal text stays readable. This is a mapping, not a new color.

The test in `tests/theme.bats` collects every `#RRGGBB` in `config/ghostty/config`, both Starship files and `config/macchina/themes/grove.toml`. It fails if any of them is missing from the palette file, ignoring case.

## 6. Ghostty

`config/ghostty/config`. Only these keys are set; everything else is Ghostty's default.

| Key | Value |
| --- | --- |
| `font-family` | `JetBrains Mono` |
| `font-size` | `14` |
| `background` | `#2D353B` (bg0) |
| `foreground` | `#D3C6AA` (fg) |
| `cursor-color` | `#D3C6AA` (fg) |
| `selection-background` | `#543A48` (bg_visual) |
| `selection-foreground` | `#D3C6AA` (fg) |
| `palette` 0 / 8 | `#475258` (bg3) / `#859289` (grey1, Grove addition) |
| `palette` 1, 9 | `#E67E80` red |
| `palette` 2, 10 | `#A7C080` green |
| `palette` 3, 11 | `#DBBC7F` yellow |
| `palette` 4, 12 | `#7FBBB3` blue |
| `palette` 5, 13 | `#D699B6` purple |
| `palette` 6, 14 | `#83C092` aqua |
| `palette` 7, 15 | `#D3C6AA` fg |
| `background-opacity` | `1` |
| `window-theme` | `dark` |
| `macos-titlebar-style` | `transparent` |
| `window-padding-x`, `window-padding-y` | `12` |
| `keybind` | `global:ctrl+grave_accent=toggle_quick_terminal` |
| `quick-terminal-position` | `top` |
| `shell-integration` | `zsh` |

The file must pass `ghostty +validate-config --config-file=<file>`.

## 7. Starship

### `config/starship.toml` (icons)

It keeps today's format, colors and order. The only changes are symbols:

| Module | Symbol | Nerd Font name |
| --- | --- | --- |
| `git_branch` | `` followed by a space | `nf-pl-branch`, U+E0A0 |
| `directory.read_only` | space, then `󰌾` | `nf-md-lock`, U+F033E |
| `cmd_duration` | `󰔛` before the duration | `nf-md-timer_outline`, U+F051B |
| `jobs` | `✦` with the count | (Unicode) |

These stay as they are:
- the git status marks `? ! +`;
- `status` with `✗`;
- `character` with `❯`;
- the `─` fill.

### `config/starship-plain.toml`

Today's `starship.toml`, unchanged.

A test checks that the two files differ only in symbol values: each file, with its symbol fields stripped, gives the same text.

### Choosing the file (`conf.d/90-prompt.zsh`)

When `TERM_PROGRAM` is `Apple_Terminal`, it exports `STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship-plain.toml"`. Everywhere else, Starship uses its default path, `~/.config/starship.toml`. Then it runs `starship init zsh`, as today.

## 8. macchina

**`config/macchina/macchina.toml`:**
- `theme = "grove"`;
- `show` lists, in this order: `Host`, `Machine`, `OperatingSystem`, `Kernel`, `Processor`, `Memory`, `Battery`, `Uptime`, `Shell`, `Terminal`, `Packages`.

**`config/macchina/themes/grove.toml`:**
- key color green `#A7C080`, separator color grey1 `#859289`, values in fg `#D3C6AA`;
- bars (memory, battery) in aqua `#83C092` on bg3 `#475258`;
- custom ASCII art from `~/.config/macchina/grove.ascii`, colored green.

**`config/macchina/grove.ascii`:** a small tree, at most 10 lines and 20 columns.

The configs must give no errors in `macchina --doctor`. Readout names and theme keys follow macchina 6.4's documentation. If a name doesn't exist in 6.4, the plan uses the nearest one and notes it.

### When it runs (`conf.d/95-macchina.zsh`)

macchina runs once, before the first prompt, only when all of these are true:

- the shell is interactive (`[[ -o interactive ]]`) and stdout is a terminal (`[[ -t 1 ]]`);
- `TERM_PROGRAM` is `ghostty` or `Apple_Terminal`;
- `GROVE_FETCHED` is unset. After running, the hook exports `GROVE_FETCHED=1`, so every shell started from that window (nested shells, `exec zsh`, tools like Claude Code) inherits it and stays quiet, while a new window starts without it. This replaces an earlier `SHLVL = 1` rule: Ghostty starts its shell through `login` and `exec`, so `SHLVL` isn't reliably 1 in a new window;
- `GROVE_NO_FETCH` is unset or empty;
- `macchina` is on PATH.

Otherwise it does nothing and prints nothing. Its exit status never affects the shell.

## 9. Module `90-terminal`

`about`: "Ghostty, the prompt and macchina".

**`check` (changes nothing):**

| Condition | Result |
| --- | --- |
| `/Applications/Ghostty.app` missing, or `macchina` not on PATH | 3 |
| `ghostty +validate-config` reports errors for `$GROVE_CONFIG/ghostty/config` | 1, with Ghostty's message |
| The Dock's `persistent-apps` doesn't include Ghostty, or includes Terminal | 3 |
| Otherwise | 0 |

Ghostty's CLI is `/Applications/Ghostty.app/Contents/MacOS/ghostty`. Tests override it with `GROVE_GHOSTTY`, and override the Dock domain with `GROVE_DOCK_DOMAIN`, the same way the Finder tests use temporary domains.

**`apply`:**

1. If Ghostty or macchina is missing, it fails with: "Ghostty or macchina is missing; run `grove install homebrew`". It installs nothing itself.
2. Dock:
   1. `defaults export <dock domain> <tmp>.plist`.
   2. With PlistBuddy, find the `persistent-apps` entry whose `tile-data:file-label` is `Terminal`. Replace its `file-data:_CFURLString` with `file:///Applications/Ghostty.app/` and its `file-label` with `Ghostty`. Its slot stays the same.
   3. If there's no Terminal entry and no Ghostty entry, insert a Ghostty tile at index 0.
   4. `defaults import`, then `killall Dock`, but only if something changed.
   5. If export, edit or import fails, return 1 and leave the domain as it was.
3. Print with `grove_note`, so it shows even in quiet mode: "Manual step: allow Ghostty in System Settings › Privacy & Security › Accessibility, so ⌃` opens the quick terminal from any app."

Running it again on a finished setup changes nothing and doesn't restart the Dock.

## 10. Testing

**`tests/modules_terminal.bats`.** Uses fake `ghostty` and `macchina` commands, a temporary Dock domain, and a temp HOME:
- `check` returns 3 when Ghostty is missing, when macchina is missing, and when the Dock has Terminal.
- `check` returns 1 when validation fails, and shows the message.
- `apply` swaps Terminal for Ghostty in the same slot and keeps every other entry in order.
- `apply` puts Ghostty first when Terminal is absent.
- `apply` run twice changes nothing the second time, and `killall` isn't called.
- `apply` fails, and the domain is unchanged, when the import fails.
- `apply` prints the Accessibility step, also under `GROVE_QUIET=1`.

**macchina hook** (in `modules_zsh.bats`), using a fake `macchina` that prints a marker:
- it runs for `TERM_PROGRAM=ghostty` on a terminal and exports `GROVE_FETCHED=1`;
- it stays quiet when `GROVE_FETCHED=1` is inherited, when `GROVE_NO_FETCH=1`, when `TERM_PROGRAM` is something else, and when macchina is missing.

**Prompt choice:** `STARSHIP_CONFIG` points to the plain file under `TERM_PROGRAM=Apple_Terminal` and is unset under `ghostty`.

**`tests/theme.bats`:**
- the palette check from §5;
- the two Starship files differ only in symbols;
- `config/.gitignore` tracks `ghostty/config` and the macchina files.

**Real tools, run when they're installed and skipped otherwise:**
- `ghostty +validate-config` on the real config;
- `starship print-config` with no warnings for both files;
- `macchina --doctor` with no errors.

**Rollout on this Mac:**
1. `grove install` (Homebrew installs the apps, `90-terminal` swaps the Dock).
2. The user allows Ghostty under Accessibility.
3. Check:
   - `grove check` all ok;
   - a new Ghostty window shows the summary and the icon prompt;
   - ⌃` works;
   - the Dock reads Ghostty, Safari, System Settings;
   - Terminal.app shows the plain prompt.
