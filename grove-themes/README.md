# grove-themes

Switches the desktop between the six Everforest schemes. The colour-carrying configs in `grove-dotfiles/config/` are tracked as `*.tmpl` templates; `grove-themes` fills in the palette from `grove-dotfiles/theme/` and writes the real (untracked) config files.

Schemes: `dark-hard`, `dark-medium` (the default), `dark-soft`, `light-hard`, `light-medium`, `light-soft`.

```
grove-themes list                  the six schemes, the current one marked
grove-themes current               the current scheme's name
grove-themes set SCHEME            render the configs for SCHEME and remember it
grove-themes render [--scheme S] [--config DIR]
                                   write the configs (default: the current scheme, $GROVE_ROOT/config)
--json                             machine-readable output on list, current and set
```

The current scheme is kept in `$GROVE_STATE/theme` (default `~/.local/state/grove/theme`). `grove install` links the command into `~/.local/bin` and renders the configs. Tests: `bats tests`.
