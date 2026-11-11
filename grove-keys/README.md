# grove-keys

Grove Keys is the keyboard app of Project Grove. It turns Caps Lock into Hyper (Cmd+Ctrl+Option+Shift; tap it alone and it sends Escape), launches apps with Hyper plus a key, shows a keyboard window and a cheat sheet, writes AeroSpace's config from one file, and draws the menus behind the Grove bar: the Grove menu, the palette, and the front app's own menus.

How to use it is in the manual: [Hotkeys](../docs/manual/05-hotkeys.md) and [The Grove menu](../docs/manual/03-the-grove-menu.md). This page is about how it is put together.

## Reaching it

The app has no Dock icon, and its icon in the native menu bar is hidden behind the Grove bar. Use the bar instead:

- the **pine** opens the Grove menu; its Grove Keys submenu has Open Grove Keys (the keyboard window), Show cheat sheet and Pause Hyper, plus a line for any missing permission;
- the **app name** opens the front app's menus, read through Accessibility (the Global Menu).

The bar and the hotkeys do this by opening links, which also work from a terminal (`open grovekeys://palette`):

| Link | What it does |
| --- | --- |
| `grovekeys://grove-menu` | The Grove menu at the pointer |
| `grovekeys://app-menu` | The front app's menus at the pointer |
| `grovekeys://palette` | The palette (Hyper + Space) |
| `grovekeys://cheatsheet` | The searchable cheat sheet (Hyper + K) |
| `grovekeys://menu/<id>` | Runs one row of the Grove menu, or pops that submenu at the pointer |
| `grovekeys://menu` | Grove Keys' own submenu at the pointer |

## The files

Bindings are in `~/.config/grove-keys/keys.toml` (tracked as `grove-dotfiles/config/grove-keys/keys.toml`). Edit it by hand or in the Grove Keys window; both write the same file. Every save renders `~/.config/aerospace/aerospace.toml` from `keys.toml` and `aerospace.base.toml` (settings and window rules), and reloads AeroSpace. `aerospace.toml` is generated and untracked: edit the other two. A mistake in `keys.toml` shows as `keys.toml line N: ...` under the tabs, and the last good config keeps running.

No app is pinned to a workspace. The monitor each workspace goes to is this Mac's own business, so it lives in `~/.config/grove-keys/monitors.toml`, which git ignores: a `[monitors]` table with lines like `1 = "main"` (`"main"`, `"secondary"`, `"built-in"` or a display's name). The Monitors group in the window creates the file on the first change; no file means every workspace stays where AeroSpace puts it. It is rendered into `aerospace.toml` with the rest, and a mistake in it shows as `monitors.toml line N: ...`.

The Grove menu's rows are in `~/.config/grove/menu.toml` (tracked) and `menu.local.toml` beside it (yours, untracked); the format is explained at the top of `menu.toml`.

Design: `grove-dotfiles/docs/specs/2026-11-10-grove-keys-design.md`, `2026-11-11-global-menu-design.md` and `2026-11-11-grove-menu-design.md` in the same folder.

## Install

```
grove install keys-app
```

It builds the app with `swift` (Command Line Tools are enough), signs it with the Grove Code Signing certificate, installs `~/Applications/Grove Keys.app`, renders `aerospace.toml` and starts the app at login with a LaunchAgent (`com.projectgrove.keys`, restarted if it crashes). `grove check` notices when the source of the app, or of `grove-themes/app` which it depends on, changed and says it needs work.

## Signing

The first `grove install keys-app` makes a self-signed code-signing certificate, "Grove Code Signing", in your login keychain (valid for ten years; only `codesign` may use its key without asking), and every build is signed with it. macOS ties Accessibility and Input Monitoring to the app's signature: an ad hoc signature changes with every rebuild, so the permissions were lost each time, while a certificate signature stays the same. Grant the permissions once and they survive rebuilds. If macOS asks whether `codesign` may use the key, choose Always Allow. `grove check` says the app needs work when it isn't signed by this certificate.

## Permissions

Grove Keys asks for two permissions in System Settings > Privacy & Security, and `grove install keys-app` opens the panes that are missing:

- Accessibility, to send the Escape tap, to run launchers, and to read and press the front app's menus.
- Input Monitoring, to see Caps Lock and the keys pressed with it.

Until both are granted nothing is remapped and Caps Lock stays Caps Lock. The app writes what it has been granted to `$GROVE_STATE/keys.json`, which `grove check` reads. The Caps Lock to F18 mapping is made with `hidutil` and lasts only while the app runs.

## Tests

```
cd grove-keys/app && swift test         the Swift package
cd grove-dotfiles && bats tests/modules_keys_app.bats   the grove module
```
