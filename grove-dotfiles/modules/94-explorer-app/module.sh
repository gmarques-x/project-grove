# shellcheck shell=bash
# 94-explorer-app: Grove Explorer, the file browser in grove-explorer/app, is
# built with swift, assembled into ~/Applications/Grove Explorer.app and signed
# with the "Grove Code Signing" identity (96-keys-app's, made there or here),
# so the folders macOS has allowed stay allowed across rebuilds. It is an
# ordinary app: nothing starts it at login, and this module never opens or
# stops it. A stamp inside the bundle holds a hash of what it was built from,
# so check notices when the app is out of date.
# Tests point GROVE_SWIFT, GROVE_CODESIGN, GROVE_SECURITY, GROVE_OPENSSL,
# GROVE_PS and GROVE_APPS_DIR at fakes and temp folders (GROVE_APP_SRC and
# GROVE_THEMES_SRC at copies of the sources, because swift builds into them).

about() { echo "Grove Explorer, the file browser"; }

_XA_IDENTITY="Grove Code Signing"

_xa_swift() { printf '%s' "${GROVE_SWIFT:-swift}"; }
# The key's access list trusts /usr/bin/codesign by path, so use exactly that.
_xa_codesign() { printf '%s' "${GROVE_CODESIGN:-/usr/bin/codesign}"; }
# With neither GROVE_APPS_DIR nor HOME there is no such folder: the expansion
# stops there, and _xa_app fails rather than name "/Grove Explorer.app".
_xa_apps() { printf '%s' "${GROVE_APPS_DIR:-${HOME:?}/Applications}"; }
_xa_app() {
  local apps
  apps="$(_xa_apps)" || return 1
  [ -n "$apps" ] || return 1
  printf '%s/Grove Explorer.app' "$apps"
}
# The stamp is in the bundle (spec §12): it is sealed by the signature and
# goes when the app goes.
_xa_stamp() { printf '%s/Contents/Resources/source.stamp' "$(_xa_app)"; }
# The Grove Icons font and map, the ones the VS Code theme uses.
_xa_icons() { printf '%s/vscode/grove-icons' "$GROVE_CONFIG"; }
# The app reads ~/.config/grove-explorer (explorer.toml, explorer.local.toml).
_xa_config() { printf '%s/.config/grove-explorer' "$HOME"; }

_xa_src() {
  if [ -n "${GROVE_APP_SRC:-}" ]; then printf '%s' "$GROVE_APP_SRC"; return 0; fi
  printf '%s/../grove-explorer/app' "$GROVE_ROOT"
}

# The package depends on grove-themes/app (GroveUI) through the tracked symlink
# grove-explorer/deps/grove-themes; the hash reads the real tree.
_xa_themes_src() {
  if [ -n "${GROVE_THEMES_SRC:-}" ]; then printf '%s' "$GROVE_THEMES_SRC"; return 0; fi
  printf '%s/../grove-themes/app' "$GROVE_ROOT"
}

# _xa_keys_app FUNCTION ARGS...: one of 96-keys-app's helpers (the signing
# identity, the icon set), run in a subshell so its check and apply never
# replace this module's.
_xa_keys_app() (
  # shellcheck source=/dev/null
  . "$MODULE_DIR/../96-keys-app/module.sh" || exit 1
  "$@"
)

# _xa_tree_hash DIR: sorted tracked paths and contents under DIR. .build/ and
# the app's copied resources are untracked, so they never count.
_xa_tree_hash() {
  (
    cd "$1" || exit 1
    git ls-files | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(shasum < "$f" | cut -d' ' -f1)" "$f"
    done
  )
}

# _xa_file_hash FILE NAME: one line of the same shape for a single file.
_xa_file_hash() { printf '%s  %s\n' "$(shasum < "$1" | cut -d' ' -f1)" "$2"; }

# _xa_hash_input: everything the bundle is made from: the app's tracked files,
# its dependency's, the Grove Icons font and map, and this module with the
# version (both end up in the Info.plist).
_xa_hash_input() {
  local a t
  a="$(_xa_tree_hash "$(_xa_src)")" || return 1
  t="$(_xa_tree_hash "$(_xa_themes_src)")" || return 1
  printf 'grove-explorer/app\n%s\ngrove-themes/app\n%s\ngrove-dotfiles\n' "$a" "$t"
  _xa_file_hash "$(_xa_icons)/seti.woff" config/vscode/grove-icons/seti.woff
  _xa_file_hash "$(_xa_icons)/grove-icon-theme.json" config/vscode/grove-icons/grove-icon-theme.json
  _xa_file_hash "$MODULE_DIR/module.sh" modules/94-explorer-app/module.sh
  _xa_file_hash "$GROVE_ROOT/VERSION" VERSION
}

_xa_source_hash() {
  local all
  all="$(_xa_hash_input)" || return 1
  printf '%s\n' "$all" | shasum | cut -d' ' -f1
}

# _xa_signed_by_identity: the installed app's signature names Grove Code Signing.
_xa_signed_by_identity() {
  "$(_xa_codesign)" -dvv "$(_xa_app)" 2>&1 | grep -qx "Authority=$_XA_IDENTITY"
}

# _xa_config_linked: ~/.config/grove-explorer/explorer.toml is the tracked
# file, through ~/.config (05-config's link) or a link of the folder itself.
_xa_config_linked() {
  [ "$(_xa_config)/explorer.toml" -ef "$GROVE_CONFIG/grove-explorer/explorer.toml" ]
}

# _xa_running: Grove Explorer is open (any copy of it).
_xa_running() {
  "${GROVE_PS:-ps}" -axo pid=,comm= 2>/dev/null | grep -q '/Grove Explorer\.app/Contents/MacOS/GroveExplorer$'
}

_xa_version() {
  local v=""
  [ -r "$GROVE_ROOT/VERSION" ] && IFS= read -r v < "$GROVE_ROOT/VERSION"
  printf '%s' "${v:-0}"
}

# _xa_info_plist: the app bundle's Info.plist. No LSUIElement: it is an
# ordinary app, in ⌘Tab. The usage strings are what macOS shows the first time
# a folder of that kind is read (spec §11); the Apple events one is for Get
# Info, which Finder shows. The exported type is the one the app drags a
# sidebar favourite as (`UTType(exportedAs:)` in DragDrop.swift). The icon is
# the app's own Resources/AppIcon.png (drawn by assets/app-icons/make.swift).
_xa_info_plist() {
  local version
  version="$(_xa_version)"
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.projectgrove.explorer</string>
  <key>CFBundleName</key><string>Grove Explorer</string>
  <key>CFBundleDisplayName</key><string>Grove Explorer</string>
  <key>CFBundleExecutable</key><string>GroveExplorer</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Grove Explorer shows and manages the files on your Desktop.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Grove Explorer shows and manages the files in your Documents folder.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>Grove Explorer shows and manages the files in your Downloads folder.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Grove Explorer shows and manages the files on disks you plug in.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Grove Explorer shows and manages the files on network disks you connect.</string>
  <key>NSFileProviderDomainUsageDescription</key><string>Grove Explorer shows and manages the files in iCloud Drive and other cloud folders.</string>
  <key>NSAppleEventsUsageDescription</key><string>Grove Explorer asks Finder to show Get Info for the files you select.</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.projectgrove.explorer</string>
      <key>CFBundleURLSchemes</key><array><string>groveexplorer</string></array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.projectgrove.explorer.favourite</string>
      <key>UTTypeDescription</key><string>Grove Explorer favourite</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict>
  </array>
</dict>
</plist>
XML
}

check() {
  local stamp
  if ! command -v "$(_xa_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Explorer needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  [ -x "$(_xa_app)/Contents/MacOS/GroveExplorer" ] || return 3
  stamp="$(cat "$(_xa_stamp)" 2>/dev/null)" || return 3
  [ "$stamp" = "$(_xa_source_hash)" ] || return 3
  _xa_signed_by_identity || return 3
  _xa_config_linked || return 3
  return 0
}

apply() {
  local src app tmp log stage rc=0 identity icons resources hash old
  src="$(_xa_src)"
  if ! app="$(_xa_app)"; then
    grove_fail "no folder to put Grove Explorer.app in: neither GROVE_APPS_DIR nor HOME is set"
    return 1
  fi
  icons="$(_xa_icons)"
  if ! command -v "$(_xa_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Explorer needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  if [ ! -f "$icons/seti.woff" ] || [ ! -f "$icons/grove-icon-theme.json" ]; then
    grove_fail "the Grove Icons font and map are missing from $icons"
    return 1
  fi
  # ~/.config is 05-config's link as a rule; where it isn't, link the folder.
  if ! _xa_config_linked; then
    grove_link "$GROVE_CONFIG/grove-explorer" "$(_xa_config)" || return 1
  fi
  mkdir -p "$(_xa_apps)" || return 1
  if ! identity="$(_xa_keys_app _ka_ensure_identity)"; then
    grove_fail "could not make the \"$_XA_IDENTITY\" certificate in the login keychain"
    return 1
  fi
  tmp="$(mktemp -d "$(_xa_apps)/.grove-explorer.XXXXXX")" || return 1
  log="$tmp/build.log"

  # Package.swift stops without the two resources (the folder is git-ignored):
  # the same copy as grove-explorer/app/make-resources.sh.
  resources="$src/Sources/GroveExplorer/Resources"
  if ! { mkdir -p "$resources" && cp "$icons/seti.woff" "$icons/grove-icon-theme.json" "$resources/"; }; then
    grove_fail "could not copy the Grove Icons into $resources"
    rm -rf "$tmp"
    return 1
  fi
  # The stamp is the hash of what the build reads: taken before it starts, so
  # a file saved while it runs leaves the app behind its source (check then
  # says so) instead of stamped as built from text it never saw.
  if ! hash="$(_xa_source_hash)"; then
    grove_fail "could not read the sources Grove Explorer is built from"
    rm -rf "$tmp"
    return 1
  fi
  if ! (cd "$src" && "$(_xa_swift)" build -c release) >"$log" 2>&1; then
    grove_fail "swift build failed:"
    tail -n 15 "$log" >&2
    rm -rf "$tmp"
    return 1
  fi

  # The app looks for the font and the map in its own Resources first, so
  # SwiftPM's resource bundle stays behind. The stamp goes in before the
  # signature, which seals everything in the bundle.
  stage="$tmp/Grove Explorer.app"
  mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources" || rc=1
  if [ "$rc" -eq 0 ]; then
    cp "$src/.build/release/GroveExplorer" "$stage/Contents/MacOS/GroveExplorer" \
      && _xa_info_plist > "$stage/Contents/Info.plist" \
      && cp "$icons/seti.woff" "$icons/grove-icon-theme.json" "$stage/Contents/Resources/" \
      && _xa_keys_app _ka_iconset "$src/Resources/AppIcon.png" "$stage/Contents/Resources/AppIcon.icns" "$tmp" \
      && printf '%s\n' "$hash" > "$stage/Contents/Resources/source.stamp" \
      || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    grove_fail "could not assemble Grove Explorer.app"
    rm -rf "$tmp"
    return 1
  fi
  if ! "$(_xa_codesign)" --force --sign "$identity" "$stage" >"$tmp/sign.log" 2>&1; then
    grove_fail "codesign failed:"
    tail -n 15 "$tmp/sign.log" >&2
    grove_note "unlock the login keychain and run grove install explorer-app again" >&2
    rm -rf "$tmp"
    return 1
  fi

  # Signed: now replace the installed app. One that is open keeps running the
  # build it was started from; it is never stopped here. The old bundle is
  # moved aside first and comes back if the new one can't take its place: at
  # no moment is there no app, and the old one is removed only with $tmp.
  old="$tmp/old/Grove Explorer.app"
  if [ -e "$app" ] || [ -L "$app" ]; then
    if ! { mkdir -p "$tmp/old" && mv "$app" "$old"; }; then
      grove_fail "could not move the installed Grove Explorer.app aside; it is left as it was"
      rm -rf "$tmp"
      return 1
    fi
  fi
  if ! mv "$stage" "$app"; then
    if [ ! -e "$old" ] && [ ! -L "$old" ]; then
      grove_fail "could not put Grove Explorer.app in place"
    elif mv "$old" "$app"; then
      grove_fail "could not put Grove Explorer.app in place; the one that was installed is back"
    else
      # Nothing is deleted: the old bundle is still in the build folder.
      grove_fail "could not put Grove Explorer.app in place, nor the old one back: it is in $tmp/old"
      return 1
    fi
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
  if _xa_running; then
    grove_note "Grove Explorer is open: quit and reopen it to use the new build"
  else
    grove_note "Grove Explorer is in ~/Applications: open it from the Grove menu's Files row or the launcher."
  fi
}

# remove: take the app away. Its config (~/.config/grove-explorer) and its
# session ($GROVE_STATE/explorer-session.json) stay. Nothing calls it yet:
# grove has no uninstall command (the manual says how to delete the app by
# hand); it is kept, tested, for when there is one.
remove() {
  local app
  app="$(_xa_app)" || return 1
  rm -rf "$app"
}
