# grove-themes

Switches the desktop between the six Everforest schemes. The colour-carrying configs in `grove-dotfiles/config/` are tracked as `*.tmpl` templates; `grove-themes` fills in the palette from `grove-dotfiles/theme/` and writes the real (untracked) config files.

Schemes: `dark-hard`, `dark-medium` (the default), `dark-soft`, `light-hard`, `light-medium`, `light-soft`.

```
grove-themes list                  the six schemes, the current one marked
grove-themes current               the current scheme's name
grove-themes set SCHEME            render the configs for SCHEME and remember it
grove-themes log [-n N]            the last N switches (default 5), newest first
grove-themes logo [grove|avatar]   the terminal logo, or switch it
grove-themes wallpaper [grove|avatar]
                                   the wallpaper set, or switch it
grove-themes render [--scheme S] [--config DIR]
                                   write the configs (default: the current scheme, $GROVE_ROOT/config)
--json                             machine-readable output on list, current, set, log, logo and wallpaper
```

The current scheme is kept in `$GROVE_STATE/theme` (default `~/.local/state/grove/theme`). `grove install` links the command into `~/.local/bin` and renders the configs. 
`list --json` also carries `palettes`: for each scheme its `name` (e.g. `Dark Medium`), `appearance` (`dark` or `light`) and `colors` (`bg0 bg1 bg2 bg3 fg grey1 red orange yellow green aqua blue purple`, then the three roles `border on_accent dim`, as `#RRGGBB`).

Every `set` whose configs rendered is logged to `$GROVE_STATE/theme-log.jsonl` (`{"time", "scheme", "exit", "steps"}`, the last 50 kept). `log` prints it newest first, one `<time> <scheme> exit=<n>` line per switch, or `{"entries": [...]}` with `--json`; damaged lines are skipped.

## The terminal logo

New terminal windows show a logo beside the fastfetch box: `grove` (the Project Grove lockup, the default) or `avatar` (the GitHub avatar's tree-ring drawing). The choice is kept in `$GROVE_STATE/fetch-logo` and applies to every scheme; `logo NAME` renders the configs with it (nothing changes if any template fails), then saves it and logs a `logo` step. `list --json` carries `logo` and `logos`. The images are `grove-dotfiles/config/fastfetch/{grove,avatar}.png` and their `-light-<contrast>` variants.

## The wallpaper

Every scheme has two wallpapers in `grove-wallpapers/`: `wallpaper-project-grove-<scheme>.png` (the default) and `wallpaper-avatar-<scheme>.png` (the avatar's drawing). The set is kept in `$GROVE_STATE/wallpaper` (`grove` or `avatar`) and every `set` uses it. `wallpaper NAME` checks the current scheme's picture exists, saves the choice, then runs only the wallpaper step (every screen and Space) and logs it; the configs are left alone. If macOS refuses the Automation prompt the step says needs-you, but the choice is kept for the next switch. `list --json` carries `wallpaper` and `wallpapers`.

## Chrome (one-time setup)

Chrome can't be themed by policy on macOS, so Grove renders an unpacked theme extension to `~/.config/chrome-theme`. Load it once: open `chrome://extensions`, turn on Developer mode, choose Load unpacked, and pick `~/.config/chrome-theme` (⌘⇧. shows hidden folders in the picker). After that, `grove-themes set` rewrites its colours, and Chrome picks them up the next time it starts. Chrome compiles the theme into `Cached Theme.pak` in that folder and reuses it at every start, so `set` removes it and Chrome rebuilds the theme from the new colours (each scheme also has its own extension version, `1.0.N`). `set` can't tell whether the theme is loaded (macOS keeps Chrome's profile private), so it reports `chrome` as next-launch whenever the theme was rendered.

The wallpaper step sets the picture on every Space, not only the visible ones: after `osascript` it backs up macOS's wallpaper store (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`), rewrites every Space's entry with `lib/wallpaper_store.py` and restarts WallpaperAgent.

Tests: `bats tests`.

## The menu bar app

`app/` is Grove Themes, a SwiftUI menu bar app that shows the six schemes in a dropdown and a gallery window and switches them by running `grove-themes set` (so it needs the CLI installed). It is a Swift package: `swift test` in `app/` runs its unit tests, and `swift build -c release` builds the `GroveThemes` executable.

`grove install themes-app` (module `97-themes-app`) builds it, assembles and ad hoc signs `~/Applications/Grove Themes.app` (no Dock icon; `Resources/Info.plist` sets `LSUIElement`) and starts it at login with the LaunchAgent `~/Library/LaunchAgents/com.projectgrove.themes.plist`. It rebuilds when the tracked files under `app/` change. The first switch from the app triggers macOS's Automation prompt; allow it once.
