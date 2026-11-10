# grove-dotfiles · VS Code in Everforest (module `95-vscode`)

**Status:** design for review, 2026-11-10
**Builds on:** [2026-11-09-grove-terminal-design.md](2026-11-09-grove-terminal-design.md) (Ghostty's font and colors, which VS Code follows)

## 1. Goal

VS Code (installed by the Brewfile's `cask "visual-studio-code"`) looks like the rest of Grove: Everforest Dark Medium colors, file icons in the palette, and the same font and terminal colors as Ghostty. grove installs and checks all of it, so a fresh Mac gets the same editor.

**Success looks like this:**
- Opening VS Code shows Everforest Dark (medium contrast) with Grove Icons, with no setup by hand.
- Every file icon is drawn in an Everforest color.
- The editor and the built-in terminal use JetBrains Mono 12.
- The built-in terminal shows the same 16 colors as Ghostty, so `ls`, `bat`, the prompt and fastfetch look the same in both.
- `grove check` reports `95-vscode` ok.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Scope | Theme plus the Grove look: colors, icons, font, terminal colors | Chosen by the user. Editor behaviour is out of scope (§3). |
| Color theme | **sainnhe's Everforest** (`sainnhe.everforest`, Marketplace): `Everforest Dark`, `everforest.darkContrast` = `medium`, every other option at the extension's default (sidebars `material`) | Same author and palette as the rest of Grove. The sidebar style can be tried live later (`flat`, `high-contrast`). |
| Icons | **Grove Icons**, our own icon theme: VS Code's built-in Seti icons (font + icon list) with each Seti color replaced by an Everforest color (§6) | No Everforest icon theme exists. Same approach as yazi's icons, chosen by the user over Material icons and plain Seti. |
| Icons in the repo | The built theme is committed (`config/vscode/grove-icons/`). `build.py` remakes it from the installed VS Code's Seti and isn't run by install | Install stays offline for the icons and never depends on Python packages. |
| Font | `JetBrains Mono`, size 12, editor and terminal; ligatures on in the editor | Matches Ghostty (which shows JetBrains Mono's ligatures by default). Installed by `30-fonts`. |
| Terminal colors | `workbench.colorCustomizations` for `[Everforest Dark]`: the 16 `terminal.ansi*` colors and `terminal.foreground`, exactly Ghostty's palette (bright black = grey1). The terminal background is left to the theme | Same output in both terminals; the panel keeps one background. |
| Settings file | `config/vscode/settings.json`, **linked** to `~/Library/Application Support/Code/User/settings.json` | The way every other Grove config works. A setting changed in VS Code's UI is written into the checkout and shows up in `git status`, to keep or discard. |
| Installing extensions | `code --install-extension sainnhe.everforest` and `code --install-extension <grove-icons>.vsix`, where grove zips the vsix from the committed folder at apply time (`/usr/bin/zip`) | `code` installs only by id or vsix, and a vsix needs nothing beyond built-in tools. |
| Icon updates | Grove Icons' `package.json` version is the source of truth; `build.py` bumps it whenever its output changes. check wants exactly that version installed | An older Grove Icons left installed is caught and replaced. |
| Light schemes | Out of scope. Grove Icons drops Seti's `light` section | Grove is Dark Medium today. |

## 3. Out of scope

- Editor behaviour: format on save, rulers, minimap, telemetry, keybindings.
- Other extensions, and syncing extensions or settings across machines (VS Code's Settings Sync stays off unless the user turns it on).
- Everforest Light and the other contrasts (the wallpapers have variants for them; VS Code doesn't yet).
- Removing extensions the user installs themselves (grove only checks its two).

## 4. Layout

```
grove-dotfiles/
├── config/
│   ├── .gitignore                      + !/vscode/
│   └── vscode/
│       ├── settings.json               the settings (§5)
│       └── grove-icons/                the icon theme extension (§6)
│           ├── package.json            id grove.grove-icons, version, iconThemes entry
│           ├── grove-icon-theme.json   Seti's icon list, recolored
│           ├── seti.woff               Seti's font, unchanged
│           ├── NOTICE                  MIT notices for Seti UI and VS Code's theme-seti
│           └── build.py                remakes the folder from VS Code's Seti (not run by install)
├── modules/95-vscode/module.sh         check / apply (§7)
├── README.md                           + 95-vscode row
└── tests/modules_vscode.bats           §8, and theme.bats gains the new files
```

`config/` is also `~/.config`, so the folder appears as `~/.config/vscode` too. VS Code doesn't look there, so that is harmless.

## 5. Settings (`config/vscode/settings.json`)

```jsonc
{
  "workbench.colorTheme": "Everforest Dark",
  "workbench.iconTheme": "grove-icons",
  "everforest.darkContrast": "medium",

  "editor.fontFamily": "JetBrains Mono",
  "editor.fontSize": 12,
  "editor.fontLigatures": true,
  "terminal.integrated.fontFamily": "JetBrains Mono",
  "terminal.integrated.fontSize": 12,

  // Ghostty's palette (config/ghostty/config).
  "workbench.colorCustomizations": {
    "[Everforest Dark]": {
      "terminal.foreground": "#D3C6AA",
      "terminal.ansiBlack": "#475258",       "terminal.ansiBrightBlack": "#859289",
      "terminal.ansiRed": "#E67E80",         "terminal.ansiBrightRed": "#E67E80",
      "terminal.ansiGreen": "#A7C080",       "terminal.ansiBrightGreen": "#A7C080",
      "terminal.ansiYellow": "#DBBC7F",      "terminal.ansiBrightYellow": "#DBBC7F",
      "terminal.ansiBlue": "#7FBBB3",        "terminal.ansiBrightBlue": "#7FBBB3",
      "terminal.ansiMagenta": "#D699B6",     "terminal.ansiBrightMagenta": "#D699B6",
      "terminal.ansiCyan": "#83C092",        "terminal.ansiBrightCyan": "#83C092",
      "terminal.ansiWhite": "#D3C6AA",       "terminal.ansiBrightWhite": "#D3C6AA"
    }
  }
}
```

## 6. Grove Icons

- **Source:** `/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/theme-seti/icons/` (`vs-seti-icon-theme.json`, `seti.woff`). VS Code 1.145.2 ships 383 icons in 23 colors.
- **Recoloring (`build.py`):** each Seti `fontColor` is replaced by an Everforest Dark Medium color:
  - colors with clear saturation go to the accent nearest in hue: red, orange, yellow, green, aqua, blue or purple;
  - greys go to grey0, grey1 or fg by lightness, so the plain-file icon stays quiet and light icons stay light.
  The mapping is printed when `build.py` runs, and the user approves the result in VS Code before merge.
- **Kept as is:** every file, extension, language and folder association, the font and its glyphs. The `light` section is dropped (§2).
- **Credits:** Seti UI by Jesse Weed and VS Code's theme-seti by Microsoft are both MIT; `NOTICE` carries both notices. The icon theme's id is `grove-icons`, its label "Grove Icons".

## 7. Module `95-vscode`

`about`: "VS Code: Everforest, Grove Icons, JetBrains Mono".

The `code` command is looked for on `PATH`, then next to brew (like `90-terminal` does for fastfetch), so a fresh run finds it before Homebrew is on `PATH`. Tests point `GROVE_CODE` at a fake `code` and `GROVE_VSCODE_USER` at a temporary settings folder.

**check** (changes nothing):
1. VS Code isn't installed (no `code`): `failed`. The Brewfile installs it, so this means `20-homebrew` didn't run or failed.
2. `settings.json` isn't the link to `config/vscode/settings.json`: needs work.
3. `code --list-extensions --show-versions` lacks `sainnhe.everforest`, or lacks `grove.grove-icons@<version in package.json>`: needs work.
4. Otherwise ok.

**apply:**
1. Link the settings with `grove_link` (an existing settings file is backed up first, as everywhere in grove).
2. Install `sainnhe.everforest` if missing. Without a network connection this fails with VS Code's own message, and the module reports failed.
3. If Grove Icons is missing or another version: zip `config/vscode/grove-icons/` into a vsix in a temporary folder (with the `extension.vsixmanifest` and `[Content_Types].xml` a vsix needs), run `code --install-extension <vsix> --force`, remove the temporary folder.
4. Note: "VS Code picks up the theme the next time it opens."

## 8. Testing

Bats, written before the code (red first), with a fake `code` that records its arguments and answers `--list-extensions` from a file:
- `theme.bats`: `config/vscode/settings.json` and `grove-icons/grove-icon-theme.json` are added to "every config color comes from the palette".
- settings: valid JSON once comments are stripped; sets the §5 keys; its 17 terminal colors equal Ghostty's `foreground` and `palette` 0–15.
- icons: the icon list parses, every definition has a palette `fontColor`, the icon count equals Seti's when VS Code is installed (skip otherwise), `package.json`'s iconThemes path exists, and `NOTICE` names Seti UI and Microsoft.
- check: failed without `code`; needs work for a missing link, a missing Everforest, a missing or older Grove Icons; ok when all are in place.
- apply: links the settings and backs up an existing file; installs only what's missing; the vsix it builds holds `extension/package.json`, `extension/grove-icon-theme.json`, `extension/seti.woff` and the manifest; a failing `code` makes the module fail.
- README lists `95-vscode`, like the other modules.

## 9. This Mac

VS Code 1.145.2 is installed and has never been opened, so there is no settings file or extension to back up. On the build branch, `grove install 95-vscode` sets it up and the user looks at it live (icon colors, sidebar style) before saying "merge it".
