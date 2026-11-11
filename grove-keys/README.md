# grove-keys

Grove Keys is a menu bar app that turns Caps Lock into Hyper (Cmd+Ctrl+Option+Shift), launches apps with Hyper plus a key, shows a keyboard window and a cheat sheet, and writes AeroSpace's config from one file. Tap Caps Lock alone and it sends Escape.

The file is `~/.config/grove-keys/keys.toml` (tracked as `grove-dotfiles/config/grove-keys/keys.toml`). Edit it by hand or in the Grove Keys window; both write the same file. Every save renders `~/.config/aerospace/aerospace.toml` from `keys.toml` and `aerospace.base.toml` (settings and window rules), and reloads AeroSpace. `aerospace.toml` is generated and untracked: edit the other two. A mistake in `keys.toml` shows as `keys.toml line N: ...` under the tabs, and the last good config keeps running.

Design: `grove-dotfiles/docs/specs/2026-11-10-grove-keys-design.md`.

## Install

```
grove install keys-app
```

It builds the app with `swift` (Command Line Tools are enough), signs it with the Grove Code Signing certificate, installs `~/Applications/Grove Keys.app`, renders `aerospace.toml` and starts the app at login with a LaunchAgent (`com.projectgrove.keys`, restarted if it crashes). `grove check` notices when the source of the app, or of `grove-themes/app` which it depends on, changed and says it needs work.

## Signing

The first `grove install keys-app` makes a self-signed code-signing certificate, "Grove Code Signing", in your login keychain (valid for ten years; only `codesign` may use its key without asking), and every build is signed with it. macOS ties Accessibility and Input Monitoring to the app's signature: an ad hoc signature changes with every rebuild, so the permissions were lost each time, while a certificate signature stays the same. Grant the permissions once and they survive rebuilds. If macOS asks whether `codesign` may use the key, choose Always Allow. `grove check` says the app needs work when it isn't signed by this certificate.

## Permissions

Grove Keys asks for two permissions in System Settings > Privacy & Security, and `grove install keys-app` opens the panes that are missing:

- Accessibility, to send the Escape tap and to run launchers.
- Input Monitoring, to see Caps Lock and the keys pressed with it.

Until both are granted nothing is remapped and Caps Lock stays Caps Lock. The app writes what it has been granted to `$GROVE_STATE/keys.json`, which `grove check` reads. The Caps Lock to F18 mapping is made with `hidutil`.

## Tests

```
cd grove-keys/app && swift test         the Swift package
cd grove-dotfiles && bats tests/modules_keys_app.bats   the grove module
```
