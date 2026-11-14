# 93-claude-mod: the grove mod in grove-dotfiles

Date: 2026-11-14. Status: draft, waiting for the owner's yes.
Follows: `2026-11-14-grove-claude-mod-design.md` (the mod itself, built and
seen live in a Claude Code session from its dev-mods folder).

## Goal

Make the `grove` Claude Code mod (the Agents pane in the grove-lab MOTD look,
the status line, and the scheme-following colors) part of grove-dotfiles. That way
`grove install` sets it up on any Mac, and every Claude Code session loads it
straight from the checkout.

## Layout

The folder is `config/grove-claude`, not `config/claude`: `~/.config` links to
`config/`, and a `~/.config/claude` could be read by Claude Code as its own.

```
config/grove-claude/
  .claude-plugin/marketplace.json   # a local marketplace named "grove"
  grove/                            # the mod, moved from dev-mods as it is
    .claude-plugin/plugin.json
    hooks/{hooks.json,register.tsx,logic.ts,motd.ts,grove.test.tsx}
    types/index.d.ts
    README.md                       # what it is, /grove-agents, the colors
```

- `marketplace.json` lists one plugin, `{ "name": "grove", "source": "./grove" }`.
  A marketplace that is a folder, with a relative source, is **read from that
  folder itself**, not from the copy Claude Code caches, so an edit plus
  `/reload-plugins` shows up with no reinstall. This is the same idea as
  `~/.config` linking into the checkout.
- `config/.gitignore` (an allowlist) gains `!/grove-claude/` and
  `/grove-claude/grove/.claude-plugin/types/`, the
  declarations the engine lays beside a loaded mod (generated, ~14k lines).

## Changes to the mod while moving it

- **The palette path comes from where the mod sits.** Today it defaults to
  `~/Developer/project-grove/grove-dotfiles`. It becomes
  `$.plugin.root/../../..` (the grove-dotfiles root), so it works from any checkout.
  `GROVE_DOTFILES` and `GROVE_STATE` still override it, and tests use them.
- The `preview` test stays, as a way to see the pane without a session.
- No change in behaviour otherwise.

## The module: `modules/93-claude-mod/module.sh`

Slot 93: 98 is AeroSpace; 91–93 are free, and nothing else depends on this one.

- `about`: `Claude Code: the grove mod (Agents pane, Grove look)`.
- **Prerequisite:** `claude` on PATH (native install in `~/.local/bin`, not
  Homebrew). If it is missing, `check` returns **4 (needs you)**. Under
  `grove install --yes` the module is then skipped and the rest goes on. Run
  interactively, `apply` prints how to install Claude Code and returns 1, as
  the other needs-you modules stop there.
- `check`, which only reads:
  1. `claude plugin marketplace list --json` has a marketplace named `grove`
     with `"source": "directory"` and `path` = `$GROVE_CONFIG/grove-claude`
     (pwd -P clean, as with the wallpaper). Confirmed against the real CLI
     under a temporary HOME. And:
  2. `claude plugin list --json` has `grove@grove` with `enabled: true` and
     `readFromFolder` = `$GROVE_CONFIG/grove-claude/grove`, the folder each
     session really runs.
  Both → 0 (ok); otherwise 3 (needs work). The JSON is read with `jq`
  (Brewfile).
- `apply`:
  1. If a `grove` marketplace exists with another path: refuse (return 1,
     `grove_fail` names it). This works like `grove_link` refusing a link
     that points elsewhere.
  2. `claude plugin marketplace add "$GROVE_CONFIG/grove-claude"` if not there.
  3. `claude plugin install grove@grove --scope user` if not installed, and
     `claude plugin enable grove@grove` if installed but disabled.
  4. Re-run `check`; non-zero → return 1.
- `GROVE_CLAUDE_BIN` overrides the `claude` command (for the tests' stub). It
  works like `GROVE_VSCODE_USER` in 95-vscode.
- The module **never edits `~/.claude/settings.json` itself**. The `claude`
  commands write it, so other keys (enabledPlugins, impeccable's marketplace,
  model, theme) are left alone.

## Colors: the MOTD palette is exempt (owner's choice, option 1)

- `hooks/motd.ts` keeps the MOTD's own seasonal leaf, particle, accent, trunk and
  ground colors, copied from grove-lab's `/etc/update-motd.d/10-grove`. They
  are deliberately not Everforest, as with the fastfetch art. A header comment
  in `motd.ts` says so.
- `tests/theme.bats` (the non-template test near :285):
  - **adds** `config/grove-claude/grove/hooks/logic.ts` against Dark Medium. Its
    built-in fallback palette must stay real Everforest.
  - A comment beside the list names `motd.ts` as left out on purpose, and why.
- Everything else in the pane (text, labels, bars' track, the background)
  already comes from the current scheme's palette file at run time.

## Moving off dev-mods

The session-only copy in `~/.claude/dev-mods/<session>/grove/` must not load
next to the installed one, because two plugins named `grove` would clash. Once
`grove install` has installed it, that copy is deleted (asked first).

## Tests (bats, `tests/claude-mod.bats`)

Using a stub `claude` (via `GROVE_CLAUDE_BIN`) that records its calls and
answers from a small JSON state file:

- `check` is 0 when the marketplace path and the enabled plugin both match.
- `check` is 3 when the marketplace is missing, the plugin is missing, or it's disabled.
- `check`/`apply` are 4 with a note when `claude` isn't found.
- `apply` adds the marketplace and installs; it then passes `check`.
- `apply` only enables a disabled plugin (no reinstall).
- `apply` refuses a `grove` marketplace pointing at another folder.
- `apply` never writes `~/.claude/settings.json` directly (the stub's HOME
  stays untouched by the module itself).
- The mod's own suite: `claude plugin test config/grove-claude/grove` passes (skipped
  when `claude` is missing). `claude plugin validate` passes too.
- theme.bats: `logic.ts` uses only Dark Medium colors.

## Not in scope

- Publishing the mod (a public GitHub repo for others). The mod can be shared
  later. project-grove is public already, so the marketplace in it would be
  installable by others, but that's a separate decision.
- Desktop-app theme and backdrop scene (later, from the first spec).

## Done when

- `grove check` shows 93-claude-mod ok on this Mac.
- A new Claude Code session (no dev-mods) shows the Agents pane on the first agent.
- Full bats suite green, run in the background (~12 min).
