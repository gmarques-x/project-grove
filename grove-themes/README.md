# grove-themes

Switches the desktop between the six Everforest schemes. The colour-carrying configs in `grove-dotfiles/config/` are tracked as `*.tmpl` templates; `grove-themes` fills in the palette from `grove-dotfiles/theme/` and writes the real (untracked) config files.

Schemes: `dark-hard`, `dark-medium` (the default), `dark-soft`, `light-hard`, `light-medium`, `light-soft`.

```
grove-themes list                  the six schemes, the current one marked
grove-themes current               the current scheme's name
grove-themes set SCHEME            render the configs for SCHEME and remember it
grove-themes log [-n N]            the last N switches (default 5), newest first
grove-themes render [--scheme S] [--config DIR]
                                   write the configs (default: the current scheme, $GROVE_ROOT/config)
--json                             machine-readable output on list, current, set and log
```

The current scheme is kept in `$GROVE_STATE/theme` (default `~/.local/state/grove/theme`). `grove install` links the command into `~/.local/bin` and renders the configs. 
`list --json` also carries `palettes`: for each scheme its `name` (e.g. `Dark Medium`), `appearance` (`dark` or `light`) and `colors` (`bg0 bg1 bg2 bg3 fg grey1 red orange yellow green aqua blue purple`, as `#RRGGBB`).

Every `set` whose configs rendered is logged to `$GROVE_STATE/theme-log.jsonl` (`{"time", "scheme", "exit", "steps"}`, the last 50 kept). `log` prints it newest first, one `<time> <scheme> exit=<n>` line per switch, or `{"entries": [...]}` with `--json`; damaged lines are skipped.

Tests: `bats tests`.

## The menu bar app

`app/` is Grove Themes, a SwiftUI menu bar app that shows the six schemes in a dropdown and a gallery window and switches them by running `grove-themes set` (so it needs the CLI installed). It is a Swift package: `swift test` in `app/` runs its unit tests, and `swift build -c release` builds the `GroveThemes` executable.

`grove install themes-app` (module `97-themes-app`) builds it, assembles and ad hoc signs `~/Applications/Grove Themes.app` (no Dock icon; `Resources/Info.plist` sets `LSUIElement`) and starts it at login with the LaunchAgent `~/Library/LaunchAgents/com.projectgrove.themes.plist`. It rebuilds when the tracked files under `app/` change. The first switch from the app triggers macOS's Automation prompt; allow it once.
