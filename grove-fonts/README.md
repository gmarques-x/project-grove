# grove-fonts

Fonts for Project Grove.

| Role      | Font                                                    | Used for                          | License                   |
|-----------|---------------------------------------------------------|-----------------------------------|---------------------------|
| Principal | **JetBrains Mono** and **JetBrains Mono NL**            | Terminal, editor, code            | SIL Open Font License 1.1 |
| Companion | **SF Pro**, **SF Pro Text**, **SF Pro Display**, **SF Pro Rounded** | Interface and reading text | Apple font license        |

## Install

```sh
~/Developer/project-grove/grove-fonts/install-fonts.sh
```

Fonts are copied to `~/Library/Fonts` for the current user and then registered with macOS. On this version of macOS, copying alone does not make a font show up right away, so the script registers each file and confirms it is active. No admin password is needed.

Running the script again is safe: identical files are skipped, and downloads are cached in `~/Library/Caches/grove-fonts` (set `GROVE_FONTS_CACHE` to use another folder). A cached file is downloaded again only when the server has a newer version.

| Option      | What it does                                                       |
|-------------|--------------------------------------------------------------------|
| `--dry-run` | Show what would happen, change nothing                             |
| `--check`   | Report whether every font is installed and active, change nothing  |
| `--force`   | Reinstall every file, even if identical                            |
| `--quiet`   | Print only errors and one summary line                             |
| `--list`    | List the configured fonts                                          |

Only tools that ship with macOS are used (`curl`, `unzip`, `shasum`, `pkgutil`, `diskutil`, `osascript`), so it works before Homebrew or the Command Line Tools are installed.

## Calling it from another script

The grove-dotfiles installer is meant to call this script. It can be run from any directory:

```sh
"$GROVE_ROOT/grove-fonts/install-fonts.sh" --quiet
```

| Exit code | Meaning                                                    |
|-----------|------------------------------------------------------------|
| 0         | All fonts installed and active                             |
| 1         | An error: download, verification, copy or registration    |
| 2         | Bad arguments, or not running on macOS                     |
| 3         | `--check` only: something is missing or out of date        |

Errors go to stderr. Colors are turned off automatically when output is not a terminal.

## Adding fonts

There are two ways:

1. **From a download.** Add a line to the `FONTS` list at the top of `install-fonts.sh` with a name, URL, verification and file pattern. Downloads can be `.zip`, `.dmg`, `.pkg`, `.ttf` or `.otf`. The comments in the script explain each field.
2. **From files you already have.** Drop `.ttf` or `.otf` files into `grove-fonts/local/`. The script installs them as well.

Other Apple fonts work the same way as SF Pro. For example, SF Mono or New York:

```
"SF Mono|https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg|apple-signed|*.pkg/Payload/Library/Fonts/*"
"New York|https://devimages-cdn.apple.com/design/resources/download/NY.dmg|apple-signed|*.pkg/Payload/Library/Fonts/*"
```

## What gets installed

**JetBrains Mono** (release v2.304, checked against a fixed SHA-256): the 32 static TTF files, 8 weights from Thin to ExtraBold, each upright and italic, in two families:

- **JetBrains Mono**, with coding ligatures (`->`, `!=`, `>=` drawn as single glyphs)
- **JetBrains Mono NL**, the same design without ligatures

The variable-font and webfont files in the release are left out. Installing both static and variable versions of the same family shows duplicate entries in font menus.

**SF Pro** (downloaded from Apple at install time): all 47 files from Apple's package, the same set Apple's own installer adds. Apple updates this download in place, so instead of a fixed checksum the script checks that the package is signed by Apple. It unpacks the package without running Apple's installer, so nothing goes into the system-wide `/Library/Fonts`.

- **SF Pro**: variable font with all weights and widths (Compressed, Condensed, Expanded)
- **SF Pro Text**: static faces tuned for sizes below 20 pt
- **SF Pro Display**: static faces tuned for 20 pt and up
- **SF Pro Rounded**: rounded static faces

Apple's license allows these fonts to be used for mock-ups of software for Apple platforms. Don't commit the font files to a dotfiles repository. Let the script download them from Apple.

## Files

- `install-fonts.sh`: the installer
- `lib/register-fonts.js`: registers fonts with macOS and checks they are active (run by the installer through `osascript`)
- `local/`: put your own font files here
