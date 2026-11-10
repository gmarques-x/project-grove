# grove-themes · one command switches the whole desktop between the six Everforest schemes

**Status:** design for review, 2026-11-10
**Covers:** sub-projects 1 (six palettes, configs as templates) and 2 (the `grove-themes` CLI). Sub-project 3, the menu bar + window GUI with the Project Grove look, gets its own spec once this ships; it will drive this CLI through `--json`.

## 1. Goal

You pick one of the six Everforest schemes (Dark or Light, each Hard, Medium or Soft) and the whole desktop follows: Ghostty, the prompt and zsh colors, eza, bat, yazi, fastfetch, VS Code, macOS light/dark mode, the highlight color and the wallpaper. Nothing changes on its own.

**Success looks like this:**
- `grove-themes set light-soft` switches everything it can on the spot and names what follows later (yazi: next launch).
- `git status` stays clean after any number of switches.
- A fresh `grove install` gives today's look (Dark Medium), or whatever scheme was last chosen on that Mac.
- Rendering Dark Medium reproduces today's config files byte for byte.
- `grove check` stays all ok.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Trigger | Only when you pick a scheme (CLI now, GUI later). No following macOS, no schedule | Chosen by the user. |
| What switches | The Grove app configs (§5), macOS light/dark mode, the highlight color (and accent), the wallpaper | Chosen by the user. |
| How configs change | **Templates + generated files**: colour-carrying configs become tracked templates that name colours; grove-themes renders them for the chosen scheme into untracked files at today's paths | Chosen by the user: git stays clean, apps read the same paths. |
| Current scheme | `~/.local/state/grove/theme` holds one of the six names; missing means `dark-medium` | Per Mac, outside the repo. |
| Scheme names | `dark-hard`, `dark-medium`, `dark-soft`, `light-hard`, `light-medium`, `light-soft` | Same as the wallpaper files. |
| CLI language | bash 3.2, tested with bats, like grove | One toolchain; the GUI calls the CLI. |
| Where it lives | `project-grove/grove-themes/` (CLI now, GUI later); palettes and templates stay in `grove-dotfiles/` | The configs are grove's; the switcher is its own app. |
| Accent color | Apple's accent is set to **Green** for every scheme (Apple offers 8 fixed accents); the **highlight** color (selected text) follows each scheme's `bg_visual` | Accent chosen by the user; it's approximate by nature, highlight can be exact. |
| VS Code settings | Generated like the rest. If the generated file was edited since grove-themes wrote it (VS Code's settings screen), the edited copy is saved to the backup folder and reported before it is replaced | Never lose a change silently; settings to keep go in the template. |
| Light fastfetch image | A dark-ink version of the Grove image per light scheme (`grove-light-hard.png`, `grove-light-medium.png`, `grove-light-soft.png`), each made with the light wallpapers' recolor on that scheme's bg0 | The paper-tone image almost vanishes on a light terminal. |

## 3. Out of scope

- The GUI (sub-project 3).
- Following macOS appearance, schedules, per-app schemes.
- Apps Grove doesn't configure, and Spaces macOS doesn't let a script reach (wallpaper on other Spaces stays manual, as today).
- Live reload of open yazi windows (yazi has no reload; it says "next launch").

## 4. Palettes (`grove-dotfiles/theme/`)

- Six files `everforest-<dark|light>-<hard|medium|soft>`, same format as today's `everforest-dark-medium` (`name = #RRGGBB`), values from upstream (`artifacts/everforest-palette.json`, verified against the plugin source). Each has every upstream background and foreground name.
- **Grove additions** in every file:
  - `fill`: `#596763` in the dark schemes (as today), the scheme's `bg5` in the light ones.
  - Terminal roles `term0`…`term15`, upstream's mapping: black = `bg3` (dark) / `fg` (light), red, green, yellow, blue, magenta = purple, cyan = aqua, white = `fg` (dark) / `bg3` (light); bright 8–15 equal 0–7, except `term8` = `grey1` (Grove's readable bright black).
- `theme.bats` today checks the Dark Medium file against upstream; it checks all six.

## 5. Templates and generated files

- **Which files** (every config with a `#RRGGBB` today): `ghostty/config`, `starship.toml`, `starship-plain.toml`, `fastfetch/config.jsonc`, `eza/theme.yml`, `yazi/theme.toml`, `yazi/init.lua`, `vscode/settings.json`, `zsh/conf.d/{40-tools,85-autosuggest,95-fetch,98-highlight}.zsh`.
- **Template:** the same file with `.tmpl` added (`ghostty/config.tmpl`), each colour written `{{name}}` (`{{bg0}}`). Values that are not colours but change with the scheme use names too: `{{appearance}}` (`dark`/`light`, Ghostty's `window-theme`), `{{fetch_image}}` (`grove.png` for the dark schemes, `grove-light-<contrast>.png` for the light ones), `{{vscode_theme}}` (`Everforest Dark` / `Everforest Light`, also used for the `[{{vscode_theme}}]` block of terminal colours) and `{{contrast}}` (`hard`/`medium`/`soft`, written to both `everforest.darkContrast` and `everforest.lightContrast`).
- **Conversion** (once, by a script kept in `artifacts/`): each Dark Medium hex is replaced by its palette name. Terminal slots (Ghostty `palette = N=`, VS Code `terminal.ansi*`) use `term0`–`term15`. A hex that matches several names (e.g. `#D3C6AA` is `fg`, `statusline2` and terminal white) takes the one the slot means; the script lists every such case for review, and the Dark Medium render test proves the result.
- **Rendering:** `grove-themes` replaces every `{{name}}` with the scheme's value. An unknown name is an error, and nothing is written.
- **Generated files** go to today's paths (`config/ghostty/config`, …) and are gitignored; only the `.tmpl` files are tracked. `config/.gitignore` and the tests that check tracked files change to match.
- **First render:** `05-config` checks that every generated file exists and equals a render of the current scheme (rendered into a temp folder, so check changes nothing), and its apply runs `grove-themes render`. A fresh clone gets its config files before any app module looks for them.
- **Tests:** every template uses only names the palettes define; every template renders for all six schemes; the Dark Medium render equals today's committed files (kept as test fixtures); existing tests that read config files (theme.bats, the module tests) run against a Dark Medium render.

## 6. The CLI (`grove-themes/bin/grove-themes`)

```
grove-themes list              the six schemes, the current one marked
grove-themes current           the current scheme's name
grove-themes set SCHEME        switch (§7)
grove-themes render            write the configs for the current scheme only (used by grove install)
--json                         on list, current and set: machine-readable output for the GUI
```

- `set` with an unknown name lists the six and exits 2, changing nothing.
- `--json` for `set` prints one object: `{"scheme": "...", "steps": [{"name": "ghostty", "result": "live|next-launch|failed", "message": "..."}...]}`.
- Paths come from `GROVE_ROOT` (the grove-dotfiles checkout, default next to `grove-themes/`) and `GROVE_STATE`, like grove. Tests point them, plus `osascript`, `defaults`, `pkill`, at fakes.
- grove-dotfiles' `70-zsh` puts `grove-themes/bin` on `PATH`, as it does for `grove`.

## 7. What `set` does

Steps run in this order. Step 1 is all or nothing; after it, each step runs whatever happened before, and any failure makes `set` exit 1 after the rest have run.

1. **Configs.** Render every template into a temporary folder; on success, move each file over its target, then write the scheme to the state file. On any render error: report it, change nothing, exit 1. Before replacing VS Code's settings, compare them with the copy grove-themes last wrote (`$GROVE_STATE/theme-vscode-settings.json`); if they differ, back the live file up (`grove_backup`) and report where.
2. **Ghostty.** Send `SIGUSR2` to running Ghostty processes (it reloads its config). Whether macOS Ghostty 1.4 honours it gets confirmed in a spike before the plan is written; if it doesn't, this step reports "press ⌘⇧, in Ghostty" instead.
3. **zsh.** Nothing to send: a `precmd` hook in `conf.d` compares the state file with the scheme the shell loaded and re-sources the colour files (`40-tools`, `85-autosuggest`, `98-highlight`) at the next prompt. Reported as "next prompt".
4. **Starship, eza, bat, fastfetch:** read their files on every run; reported as live. **VS Code:** watches its settings; live. **yazi:** next launch.
5. **macOS appearance:** `osascript` sets System Events' dark mode on or off. If Automation isn't allowed: "needs you", with the same message as `85-macos-wallpaper`.
6. **Accent and highlight:** `defaults write -g AppleAccentColor -int 3` (green) and `AppleHighlightColor` "R G B Other" from `bg_visual` (0–1 floats). Apps that are open pick it up when they next redraw or relaunch; reported as such.
7. **Wallpaper:** every screen gets `grove-wallpapers/wallpaper-project-grove-<scheme>.png`. `85-macos-wallpaper` changes to check and set the current scheme's picture, so `grove check` doesn't flag a switched wallpaper.

## 8. Testing

Bats, red first, against a temp home with fakes for `osascript`, `defaults` and `pkill`:
- palettes: all six complete; term roles follow upstream's mapping per scheme; fill per §4.
- render: all templates × six schemes; unknown name fails without writing; Dark Medium equals today's files.
- set: each step's effect and its line in the output; a failing render changes nothing; a failing later step doesn't stop the rest and exits 1; an edited VS Code settings file is backed up; unknown scheme exits 2; `--json` shape.
- zsh hook: a shell started on Dark Medium shows the new highlight colours after the state file changes (zsh test like the existing ones).
- grove-dotfiles: `05-config` renders on a fresh clone; `85-macos-wallpaper` follows the state file; the whole existing suite stays green.

## 9. This Mac

Everything is Dark Medium today and stays so after the refactor (the render equals the current files). The light fastfetch image gets made before light schemes are tried. The user tries each scheme live before "merge it".
