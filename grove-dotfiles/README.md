# Project Grove: grove-dotfiles

Project Grove is a complete macOS desktop overhaul built on the [Everforest](https://github.com/sainnhe/everforest) color scheme by sainnhe. Its principal font is JetBrains Mono, with SF Pro as the companion. This folder, `grove-dotfiles`, sets up a fresh Mac from one command: tools, fonts, shell, git, GitHub, Finder, and the colors to match. Run it again any time; anything already done is left alone.

## Start on a fresh Mac

Open Terminal and paste:

```sh
curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
```

It waits for Apple's Command Line Tools (finish the dialog that appears), clones the repo to `~/Developer/project-grove`, and runs `grove install`. If that folder already exists but isn't project-grove, it stops without touching anything; set `GROVE_CLONE_DIR` to clone somewhere else.

`grove install` asks you for:

- your name, email and GitHub username (pre-filled from your git config when it has them)
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

Options: `--yes` answers prompts with defaults and skips anything that needs you; `--quiet` prints less.

## Modules

| Module | What it does |
| --- | --- |
| `05-config` | Makes `~/.config` a link to the tracked config |
| `10-xcode-tools` | Xcode command line tools |
| `20-homebrew` | Homebrew and the Brewfile |
| `30-fonts` | Fonts from grove-fonts |
| `40-ssh` | ssh config, ed25519 key and agent |
| `50-git` | git identity and commit signing |
| `60-github` | GitHub login and SSH signing key |
| `70-zsh` | zsh config, Starship prompt and the `grove` command |
| `80-macos-finder` | Finder settings (the sidebar is a manual step) |

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
