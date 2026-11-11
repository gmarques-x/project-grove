# Project Grove: grove-dotfiles

Project Grove is a complete macOS desktop overhaul built on the [Everforest](https://github.com/sainnhe/everforest) color scheme by sainnhe. Its principal font is JetBrains Mono, with SF Pro as the companion. This folder, `grove-dotfiles`, sets up a fresh Mac from one command: tools, fonts, shell, git, GitHub, Finder, and the colors to match. Run it again any time; anything already done is left alone.

## Start on a fresh Mac

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

It waits for Apple's Command Line Tools (finish the dialog that appears), clones the repo to `~/Developer/project-grove`, and runs `grove install`. If that folder already exists but isn't project-grove, it stops without touching anything; set `GROVE_CLONE_DIR` to clone somewhere else.

`grove install` asks you for:

- your name, email and GitHub username (nothing is suggested; type each one)
- your Mac password, for Homebrew's first install
- an SSH key passphrase, only if you don't have a key yet
- a browser login for GitHub

## Do not delete the repo

> **`~/.config` IS the folder `project-grove/grove-dotfiles/config`.** It is a link, not a copy.
>
> - Deleting or re-cloning the repo deletes everything in `~/.config`.
> - Never run `git clean` in the repo (`-x` and `-X` both remove ignored files such as `local.env`).

Your personal values (name, email, GitHub username) live in `~/.config/grove/local.env`, which git ignores. Anything Grove replaces is moved, never deleted, to `~/.local/state/grove/backup/`.

## Undo

Grove only makes links and moves files aside, so it can be undone by hand:

1. Remove the links: `~/.config`, `~/.zshenv`, `~/.ssh/config` and `~/.local/bin/grove` (`rm` on a link removes only the link).
2. Move the files back from `~/.local/state/grove/backup/<run>/`. Paths inside a run folder are relative to `$HOME` (`<run>/.zshrc` goes back to `~/.zshrc`).

Your app settings stay in the repo's `config/` folder; copy them back into a new `~/.config` if you want them.

## The `grove` command

| Command | What it does |
| --- | --- |
| `grove install [module…]` | Sets things up. With no names, runs every module that needs work. |
| `grove check` | Reports each module as ok or not. Changes nothing. |
| `grove update` | Brings an installed setup up to date. |
| `grove list` | Lists the modules. |

Options: `--yes` asks nothing and skips anything that needs you (including your name and email, until a run that can ask); `--quiet` prints less.

## Modules

| Module | What it does |
| --- | --- |
| `05-config` | Makes `~/.config` a link to the tracked config and renders its generated files (`grove-themes render`) |
| `10-xcode-tools` | Xcode command line tools |
| `20-homebrew` | Homebrew and the Brewfile |
| `30-fonts` | JetBrains Mono, SF Pro and your own fonts (see Fonts) |
| `40-ssh` | ssh config, ed25519 key and agent |
| `50-git` | git identity and commit signing |
| `60-github` | GitHub login and SSH signing key |
| `70-zsh` | zsh config, Starship prompt and the `grove` and `grove-themes` commands |
| `80-macos-finder` | Finder settings (the sidebar is a manual step) |
| `85-macos-wallpaper` | Desktop wallpaper: `grove-wallpapers/wallpaper-<set>-<scheme>.png` for the current scheme on every screen (other Spaces are a manual step); the set is `project-grove`, or `avatar` after `grove-themes wallpaper avatar` |
| `90-terminal` | Ghostty in the Dock (in Terminal's place), its config, and fastfetch |
| `95-vscode` | VS Code: Everforest, Grove Icons and JetBrains Mono, settings linked from the tracked config |
| `96-keys-app` | Grove Keys in the menu bar: Caps Lock as Hyper, the keyboard window, and the AeroSpace config it renders; builds the app, installs it to ~/Applications and starts it at login |
| `97-themes-app` | Grove Themes in the menu bar: builds the app, installs it to ~/Applications and starts it at login |
| `98-aerospace` | AeroSpace tiles the desktop: numbered workspaces, Option shortcuts and JankyBorders in the scheme's colours (Accessibility is a manual step) |
| `99-sketchybar` | The Grove top bar: SketchyBar (trusted felixkratz/formulae tap) as a floating bar on a strip that hides the auto-hidden menu bar; workspaces, the front app and system status in the scheme's colours |

**Chrome** is themed by an unpacked extension that grove-themes renders to `~/.config/chrome-theme`; load it once (see `grove-themes/README.md`).

## Fonts

| Role | Font | Used for | License |
| --- | --- | --- | --- |
| Principal | **JetBrains Mono** and **JetBrains Mono NL** (2.304, 32 static TTFs) | Terminal, editor, code | SIL Open Font License 1.1 |
| Companion | **SF Pro**, **SF Pro Text**, **SF Pro Display**, **SF Pro Rounded** (47 files) | Interface and reading text | Apple font license |

`grove install fonts` copies them to `~/Library/Fonts` (no admin password) and registers them with macOS, which this version of macOS needs before apps can use a font. Downloads are cached in `~/Library/Caches/grove/fonts` and fetched again only when the server has a newer file.

- JetBrains Mono is checked against a fixed SHA-256. The variable and web fonts in the release are left out, so font menus don't show duplicates.
- SF Pro is unpacked from Apple's installer without running it, after checking that the package is signed by Apple. Apple updates the download in place, so a fixed checksum wouldn't last.
- Font files are never committed, because of their licenses.

To add a font:

1. **From a download:** add a line to `modules/30-fonts/fonts.txt`: a name, a URL (`.zip`, `.dmg`, `.pkg`, `.ttf` or `.otf`), how to verify it, and which files to take. The comments at the top of the file explain each field. Other Apple fonts work like SF Pro, for example:
   ```
   SF Mono|https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg|apple-signed|*.pkg/Payload/Library/Fonts/*
   ```
2. **From files you have:** drop `.ttf` or `.otf` files into `modules/30-fonts/local/`. They aren't committed.

## Terminal and shell

**Ghostty** is the terminal: Everforest Dark Medium, JetBrains Mono 12, a solid window. Its config is `config/ghostty/config`. New windows open at 150 × 40 (columns × rows).

- **Quick terminal:** ⌃` drops a terminal down from the top of the screen, from any app. macOS only lets you grant this, so do it once: **System Settings › Privacy & Security › Accessibility**, then turn on Ghostty.
- **Dock:** `grove install` gives Ghostty Terminal's place in the Dock. Terminal.app stays installed.
- **Prompt:** the Starship prompt shows icons in Ghostty. Terminal.app can't draw them, so it gets the same prompt without icons (`config/starship-plain.toml`).
- **Summary:** every new window starts with a fastfetch summary: the Project Grove image beside your Mac's stats in a box. The image needs a Ghostty window at least 140 columns wide; narrower windows and Terminal.app show a text drawing instead, and windows under 125 columns show just the stats. Shells started from that window stay quiet. Turn it off with `export GROVE_NO_FETCH=1` in `config/zsh/.zshenv`. The config is `config/fastfetch/`.

The shell has completions (menu selection, case-insensitive), suggestions from your history in grey (→ accepts), syntax highlighting, and these replacements:

| Type | Runs | |
| --- | --- | --- |
| `ls` | `eza -l`, folders first, then files, each A→Z | the original: `\ls` |
| `ll` | the same, with hidden files | |
| `lt` | a two-level tree | |
| `cat` | `bat` (line numbers, git changes; long files open in a pager) | the original: `\cat` |
| `cd` | zoxide: works like `cd`, and `cd proj` jumps to your most-used match | the original: `builtin cd` |
| `cls` | clears the screen and reloads the shell, like a new window (summary included) | |
| `y` or `finder` | yazi, a file manager in the terminal; when you quit, the shell moves to the folder you were in | plain: `yazi` |
| ⌃R / ⌃T / ⌥C | fzf: search history / pick files / jump to a folder | |

`rg` is ripgrep. `grep` is unchanged.

**yazi** lists like `ls` (folders first, A→Z, hidden files off; `.` shows them) in the same colors as eza. Its top bar is drawn like the prompt (`config/yazi/init.lua`), with a line under it, and the hovered row is a rounded pill. Its config is `config/yazi/`. It previews images in Ghostty, plus PDFs, archives and SVGs. Video thumbnails and HEIC/RAW images are left out, since they need ffmpeg and ImageMagick. Terminal.app shows plain previews and can't draw the file icons.

## Adding a module

Make a folder `modules/NN-name/` with a `module.sh` that defines three functions:

- `about` prints a one-line description.
- `check` reports the state and never changes anything. It returns `0` when ok, `3` when it needs work, `4` when it needs you.
- `apply` makes the change. It only runs when `check` didn't return `0`.

The number sets the order modules run in.

## Credits

- [Everforest](https://github.com/sainnhe/everforest) by sainnhe (MIT)
- Prompt colors come from the Everforest zsh port
- [Starship](https://starship.rs) for the prompt
