# grove-dotfiles · Terminal and shell (Ghostty, Starship, macchina, zsh tools)

**Status:** approved design, 2026-11-09
**Builds on:** [2026-11-09-grove-dotfiles-foundation-design.md](2026-11-09-grove-dotfiles-foundation-design.md)

## 1. Goal

Ghostty becomes the Project Grove terminal:
- Everforest Dark Medium, a solid window, JetBrains Mono 14 with ligatures;
- a ⌃` quick terminal that drops down from any app;
- it takes Terminal's place in the Dock, and Terminal.app stays installed as a fallback.

The Starship prompt keeps its layout and colors and gains icons, which Ghostty draws without a patched font. macchina shows a short Everforest summary in every new window. zsh gets completions, autosuggestions, syntax highlighting and fzf. ripgrep, zoxide, bat and eza are installed, and `ls`, `ll`, `lt`, `cat` and `cd` use them.

On a fresh Mac, `grove install` sets all of this up. On this Mac, running it again moves Terminal's Dock slot to Ghostty and changes nothing else.

**Success looks like this:**
- `grove check` reports `90-terminal` ok.
- A new Ghostty window shows the macchina summary, then the prompt with icons.
- ⌃` toggles the quick terminal, once Ghostty is allowed under Accessibility.
- The Dock reads Ghostty, Safari, System Settings.
- Terminal.app still works, with the icon-free prompt and no broken glyphs.
- `ll` lists everything, hidden files included, folders first and then files, each A→Z. `ls` lists the same way without the hidden files.

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
| Shell tools | Homebrew installs them and zsh loads them directly; the classic commands are replaced through aliases | Chosen by the user. No plugin manager to maintain. |
| Structure | One module, `90-terminal`; configs live in `config/`; Homebrew installs the apps | `~/.config` already links into the repo, so only checks and the Dock need code. |

## 3. Out of scope

- Light variants and following macOS Appearance (D2).
- Editor module.
- Ghostty themes for other variants.
- Granting the Accessibility permission. macOS allows only the user to do that, so it's a printed manual step.

## 4. Layout

```
grove-dotfiles/
├── Brewfile                          + cask "ghostty", + brew "macchina", + the shell tools (§10)
├── theme/
│   └── everforest-dark-medium        palette: upstream colors + Grove additions
├── config/
│   ├── .gitignore                    + !/ghostty/, + !/macchina/, + !/bat/, + !/eza/
│   ├── bat/config
│   ├── eza/theme.yml
│   ├── ghostty/config
│   ├── macchina/macchina.toml
│   ├── macchina/themes/grove.toml
│   ├── macchina/grove.ascii          the tree mark
│   ├── starship.toml                 prompt with icons
│   ├── starship-plain.toml           prompt without icons (Terminal.app)
│   └── zsh/conf.d/
│       ├── 20-aliases.zsh            + the eza and bat aliases
│       ├── 30-completion.zsh
│       ├── 40-tools.zsh              zoxide and fzf
│       ├── 85-autosuggest.zsh
│       ├── 90-prompt.zsh             chooses the Starship config, then inits Starship
│       ├── 95-macchina.zsh           the summary on new windows
│       └── 98-highlight.zsh          syntax highlighting, loaded last
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

The test in `tests/theme.bats` collects every `#RRGGBB` in `config/ghostty/config`, both Starship files, `config/macchina/themes/grove.toml`, `config/eza/theme.yml` and `config/zsh/conf.d/*.zsh`. It fails if any of them is missing from the palette file, ignoring case.

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

*Revised 2026-11-09 at the user's request: the two-line prompt became a one-line bar.*

### `config/starship.toml` (Ghostty)

The prompt is one line: a bar of colored blocks with rounded ends, then `❯`.

| Order | Block | Background | Text |
| --- | --- | --- | --- |
| — | left end `` (U+E0B6) | — | aqua `#83C092` |
| 1 | `username` (always shown) | aqua `#83C092` | bg0 `#2D353B` |
| 2 | `directory` (read-only adds `󰌾`, U+F033E) | green `#A7C080` | bg0 |
| 3 | `git_branch` (`` U+E0A0) + `git_status` (`? ! +`, ahead/behind) | yellow `#DBBC7F` | bg0 |
| 4 | `cmd_duration` (`󰔛` U+F051B), only for slow commands | bg3 `#475258` | fg `#D3C6AA` |
| 5 | `status` (`✗ N`), only after a failure | red `#E67E80` | bg0 |
| 6 | `time` (`%H:%M`) | orange `#E69875` | bg0 |
| — | right end `` (U+E0B4) | — | orange |

The blocks touch. Only the two ends of the bar are rounded. `❯` follows a space, in fg, and turns red `#E67E80` after an error. The git blocks disappear outside a repo.

### `config/starship-plain.toml` (Terminal.app)

The same blocks, colors and order, without Nerd Font glyphs. The ends are square: a space on the block's own color. There's no branch icon or timer icon, and read-only shows ` (read-only)`.

A test checks that both files set the same tables, styles and toggles, and that the plain file has no Nerd Font glyphs. Other tests render both prompts in a temp repo and check the block order.

### Choosing the file (`conf.d/90-prompt.zsh`)

When `TERM_PROGRAM` is `Apple_Terminal`, it exports `STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship-plain.toml"`. Everywhere else, Starship uses its default path, `~/.config/starship.toml`. Then it runs `starship init zsh`.

## 8. macchina

**`config/macchina/macchina.toml`:**
- `theme = "grove"`;
- `show` lists, in this order: `Host`, `Machine`, `OperatingSystem`, `Kernel`, `Processor`, `Memory`, `Battery`, `Uptime`, `Shell`, `Terminal`, `Packages`.

**`config/macchina/themes/grove.toml`:**
- key color green `#A7C080`, separator color grey1 `#859289`, values in fg `#D3C6AA`;
- bars (memory, battery) in aqua `#83C092` on bg3 `#475258`;
- custom ASCII art from `~/.config/macchina/grove.ascii`, colored green.

**`config/macchina/grove.ascii`:** the Grove logo as 24-bit color pixel art, at most 10 lines and 20 columns, shown to the left of the stats.
- Each character is two pixels drawn with half blocks (`▀ ▄ █`): the tree's left half in aqua and right half in green, a yellow moon, dark bg_green background pines, and a bg3 ground line.
- The picture is kept as a letter grid in `theme/grove-logo.txt`, one palette color per letter. `theme/render-logo.py` writes the `.ascii` file from it.
- A test checks that the committed file matches the grid.
- The theme no longer sets `custom_ascii.color`, because the colors are in the file. *(Revised 2026-11-09 at the user's request; the first version was a one-color text tree.)*

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

## 10. Shell

### Installs

The Brewfile adds `zsh-completions`, `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf`, `ripgrep`, `zoxide`, `bat` and `eza`. zsh loads them from `$HOMEBREW_PREFIX/share`, falling back to `/opt/homebrew/share`. Every `conf.d` file checks that its tool is there, and does nothing without it.

### `conf.d` files, in load order

| File | Contents |
| --- | --- |
| `20-aliases.zsh` | The aliases below. |
| `30-completion.zsh` | Adds `share/zsh-completions` to `fpath`, then runs `compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"` and sets the completion cache to `$XDG_CACHE_HOME/zsh/zcompcache`. Menu selection is on (`zstyle ':completion:*' menu select`), and matching ignores case. |
| `40-tools.zsh` | `eval "$(zoxide init zsh --cmd cd)"` and `source <(fzf --zsh)`. |
| `85-autosuggest.zsh` | Sources zsh-autosuggestions with `ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#859289'` (grey1). → accepts a suggestion, which is the plugin's default. |
| `98-highlight.zsh` | Sources zsh-syntax-highlighting, last of all. It sets `ZSH_HIGHLIGHT_STYLES`: command, builtin, alias and function green `#A7C080`; `unknown-token` red `#E67E80`; strings yellow `#DBBC7F`; `path` underlined; comments grey1 `#859289`. |

### Aliases (`20-aliases.zsh`)

| Alias | Runs |
| --- | --- |
| `ls` | `eza -l --group-directories-first --sort=name --git` plus icons |
| `ll` | `eza -la --group-directories-first --sort=name --git` plus icons |
| `lt` | `eza --tree --level=2 --group-directories-first` plus icons |
| `cat` | `bat --paging=never` |
| `cd` | zoxide, through `--cmd cd` in `40-tools.zsh`: it works like `cd`, and `cd proj` jumps to the most-used match |

- "Plus icons" means `--icons=auto`, except when `TERM_PROGRAM` is `Apple_Terminal`.
- `--sort=name` ignores case.
- The `eza` and `bat` aliases are defined only when the tool is installed.
- The originals stay reachable as `\ls`, `\cat` and `builtin cd`.
- `grep` isn't replaced. `rg` is available under its own name.

### Colors and locations

- **bat:** `config/bat/config` sets `--theme=ansi` (the terminal's Everforest colors) and `--style=numbers,changes,header`.
- **eza:** `config/eza/theme.yml`, with palette colors for file types, permissions, sizes, dates and git status. `EZA_CONFIG_DIR="$XDG_CONFIG_HOME/eza"` is exported in `.zshenv`, because on macOS eza otherwise looks in `~/Library/Application Support`.
- **zoxide:** `_ZO_DATA_DIR="$XDG_DATA_HOME/zoxide"` is exported in `.zshenv`, for the same reason.
- **fzf:** `FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'`, and `FZF_DEFAULT_OPTS` sets palette colors: background bg0, text fg, selection background bg_visual, matches green, prompt aqua, pointer red, borders bg3. Both are set in `40-tools.zsh`.

### Completion safety

`compinit` warns about folders other users can write to. If `compaudit` lists Homebrew's `share/zsh` folders, `70-zsh` `apply` runs `chmod go-w` on exactly those folders, as Homebrew's docs recommend, and `check` returns 3 until they're fixed. The check is never suppressed with `compinit -u` or `-i`.

## 11. Testing

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
- `config/.gitignore` tracks `ghostty/config`, the macchina files, `bat/config` and `eza/theme.yml`.

**Shell** (in `modules_zsh.bats`, using an interactive zsh with a temp HOME):
- `ls`, `ll` and `lt` expand as in §10. `ll` and `ls` include `--icons=auto` under `ghostty` and leave it out under `Apple_Terminal`.
- `ll` in a real folder lists hidden files, folders before files, each A→Z, ignoring case. This runs with the real `eza` when it's installed and is skipped otherwise.
- `cd` is zoxide's function, and `builtin cd` still reaches the builtin.
- `compinit` prints no warning and writes its dump under `$XDG_CACHE_HOME/zsh/`. No `.zcompdump` appears in `$HOME` or `$ZDOTDIR`.
- Syntax highlighting is the last plugin loaded. The test checks that `98-highlight.zsh` sorts last in `conf.d`.
- Each `conf.d` file prints nothing and doesn't fail when its tool is missing.
- `70-zsh` `check` returns 3 when `compaudit` reports Homebrew folders, and `apply` fixes their permissions. Tested with a fake `compaudit` result.

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

## 12. Results (rollout on this Mac, 2026-11-09)

- `grove install` ran in Terminal. Afterwards `grove check` reports all ten modules ok.
- **Dock:** Ghostty (`com.mitchellh.ghostty`), Safari, System Settings. Terminal's tile was swapped in place, and its old bookmark was dropped.
- **Completion:** `70-zsh` removed group write from `/opt/homebrew/share` (compaudit had flagged it, mode 775). New shells load both `share/zsh-completions` and `share/zsh/site-functions`, without a compinit prompt.
- **Ghostty's template:** Ghostty had created a comment-only `config.ghostty` template in Application Support. It was left in place, as designed.
- **Measured while building:**
  - macchina 6.4 can't read the battery on macOS 27, so that readout is skipped;
  - eza 0.23.5 reads file names from stdin when it gets no path and stdin isn't a terminal.
- **Still to confirm by eye in Ghostty:** the summary, the prompt bar, ⌃` (needs the Accessibility grant; on the Portuguese layout the key may sit elsewhere), and the Terminal.app fallback.

## 13. Look revision (2026-11-09, from the user's reference screenshot)

The user asked for the spacing and organization of a reference Ghostty screenshot, keeping Grove's fonts and colors. This section replaces the matching parts of §6–§8.

**Ghostty:** `window-padding-x = 24` and `window-padding-y = 20`. The summary starts one empty line below the top, because `95-macchina.zsh` prints a newline first.

**macchina:**
- `show` lists, in this order: Host, Machine, Kernel, OperatingSystem, DesktopEnvironment, WindowManager, Packages, Terminal, Shell, LocalIP, Backlight, Resolution, Uptime, Processor, ProcessorLoad, Memory, Battery. Readouts this Mac can't report are skipped.
- The stats sit in a box (`border = "plain"`) titled ` Grove `, with an inner margin of 2×1.
- Each label has a Nerd Font icon. The separator is the cube glyph (U+F1B2) in grey1.
- Bars use `▮`. The palette row (`type = "Dark"`, `●`) shows the terminal's eight colors.
- The logo is drawn at `scale: 2` (set in `theme/grove-logo.txt`): 36 columns × 20 lines beside the box.

**Prompt:**
- The order is user ( U+F179), folder, git, time ( U+F017).
- Blocks are joined by powerline arrows (U+E0B0). A two-arrow fade (green → yellow → orange) leads into the time block.
- The ends are rounded. `add_newline = true`, so there's an empty line between commands.
- The duration and exit-code blocks are gone, and `❯` still turns red after a failure.
- `starship-plain.toml` keeps the same blocks with square ends and no arrows.

**`cls`:** `clear && GROVE_FETCHED= exec zsh -l`. It reloads the shell as a new window would, summary included.

**Logo and font revision (2026-11-09, user request):**
- **Font:** Ghostty's `font-size` is 12, the size the user settled on in the app.
- **Logo:** replicates the README banner's logo block at 56 columns × 20 lines.
  - **Pine:** three drooping tiers with a camouflage texture (aqua base, green highlights, bg_green shadows), a light edge under each tier, and a flared trunk.
  - **Lettering:** a grey1 divider, then "Project" in a small serif and "Grove" in a bold slab serif, both in fg.
  - **Tagline:** "A complete macOS desktop overhaul." is printed as real text in grey2, centered on the last line after an empty one.
  - **Source:** `theme/grove-logo.txt` holds the grid (`scale: 1`), with `caption:` and `caption-color:` lines for the tagline.
