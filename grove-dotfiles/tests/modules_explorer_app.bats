# shellcheck disable=SC2016,SC1090,SC1091,SC2154,SC2030,SC2031
# 94-explorer-app: builds Grove Explorer and installs it, against fake swift,
# codesign, security, openssl, iconutil, sips and ps and temp folders. The
# fake keychain is a file, as in modules_keys_app.bats: keychain-identity holds
# the hash of "Grove Code Signing" when it's there, and signed-with the
# identity the app was last signed with ("-" is ad hoc).
load helpers

XA_MODULE=94-explorer-app

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$XA_MODULE"
  . "$MODULE_DIR/module.sh"
}

# A throwaway git copy of a source tree, so a fake swift can build into it and
# a test can change a tracked file. Only what is tracked: the app's resources
# folder is git-ignored, and the module is what fills it.
git_copy() {
  local f
  mkdir -p "$2"
  while IFS= read -r -d '' f; do
    mkdir -p "$2/$(dirname "$f")"
    cp -p "$1/$f" "$2/$f"
  done < <(git -C "$1" ls-files -z .)
  git -C "$2" init -q
  git -C "$2" add -A
}

setup() {
  grove_test_setup
  export GROVE_APP_SRC="$BATS_TEST_TMPDIR/explorer-src"
  export GROVE_THEMES_SRC="$BATS_TEST_TMPDIR/themes-src"
  git_copy "$GROVE_ROOT/../grove-explorer/app" "$GROVE_APP_SRC"
  git_copy "$GROVE_ROOT/../grove-themes/app" "$GROVE_THEMES_SRC"
  export GROVE_APPS_DIR="$BATS_TEST_TMPDIR/Applications"
  mkdir -p "$GROVE_APPS_DIR"
  # ~/.config is the tracked config (a copy here), as 05-config leaves it.
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  APP="$GROVE_APPS_DIR/Grove Explorer.app"
  STAMP="$APP/Contents/Resources/source.stamp"
  RESOURCES="$GROVE_APP_SRC/Sources/GroveExplorer/Resources"
  # swift: Package.swift stops a build without the two resources, so does this.
  stub swift '
echo "$*" >> "$BATS_TEST_TMPDIR/swift-args"
if [ -n "$FAKE_SWIFT_FAIL" ]; then echo "error: boom.swift:1: cannot find x" >&2; exit 1; fi
# A source file saved while the build runs (the build itself is of the old text).
if [ -n "$FAKE_SWIFT_EDITS" ]; then echo "// saved while building" >> Package.swift; fi
for f in seti.woff grove-icon-theme.json; do
  [ -f "Sources/GroveExplorer/Resources/$f" ] || { echo "error: resources are missing ($f)" >&2; exit 1; }
done
mkdir -p .build/release && printf "#!/bin/sh\n" > .build/release/GroveExplorer && chmod +x .build/release/GroveExplorer'
  stub codesign '
if [ -n "$FAKE_SIGN_FAIL" ] && [ "$1" = --force ]; then echo "$3: errSecInternalComponent" >&2; exit 1; fi
if [ "$1" = -dvv ]; then
  echo "Executable=$2/Contents/MacOS/GroveExplorer" >&2
  case "$(cat "$BATS_TEST_TMPDIR/signed-with" 2>/dev/null)" in
    "") echo "$2: code object is not signed at all" >&2; exit 1 ;;
    -) echo "Signature=adhoc" >&2 ;;
    *) printf "Authority=Grove Code Signing\nTeamIdentifier=not set\n" >&2 ;;
  esac
  exit 0
fi
echo "$*" >> "$BATS_TEST_TMPDIR/codesign-args"
# What was in the bundle when it was signed: nothing may be added afterwards.
[ "$1" = --force ] && (cd "$4" && find . -type f | LC_ALL=C sort) > "$BATS_TEST_TMPDIR/signed-files"
[ "$1" = --force ] && [ "$2" = --sign ] && echo "$3" > "$BATS_TEST_TMPDIR/signed-with"
exit 0'
  XA_HASH=F68B51349BDD56C6A96FA6D0AAA8119A7B9F93B7
  stub security '
echo "$*" >> "$BATS_TEST_TMPDIR/security-args"
case "$1" in
  find-identity)
    printf "\nPolicy: Code Signing\n  Matching identities\n"
    n=0
    if [ -s "$BATS_TEST_TMPDIR/keychain-identity" ]; then
      while read -r h err; do
        n=$((n + 1))
        printf "  %d) %s \"Grove Code Signing\" (%s)\n" "$n" "$h" "${err:-CSSMERR_TP_NOT_TRUSTED}"
      done < "$BATS_TEST_TMPDIR/keychain-identity"
    fi
    printf "     %d identities found\n" "$n" ;;
  import)
    [ -f "$2" ] || exit 1
    if [ -n "$FAKE_IMPORT_FAIL" ]; then echo "security: SecKeychainItemImport: User interaction is not allowed." >&2; exit 1; fi
    echo F68B51349BDD56C6A96FA6D0AAA8119A7B9F93B7 >> "$BATS_TEST_TMPDIR/keychain-identity" ;;
esac
exit 0'
  stub openssl '
echo "$*" >> "$BATS_TEST_TMPDIR/openssl-args"
[ "$1" = rand ] && { echo 00112233445566778899aabbccddeeff; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in -keyout|-out) echo pem > "$2" ;; esac
  shift
done
exit 0'
  stub sips 'echo "$*" >> "$BATS_TEST_TMPDIR/sips-args"; while [ $# -gt 0 ]; do [ "$1" = --out ] && cp "$BATS_TEST_TMPDIR/stubs/sips" "$2"; shift; done'
  stub iconutil 'echo "$*" >> "$BATS_TEST_TMPDIR/iconutil-args"; while [ $# -gt 0 ]; do [ "$1" = -o ] && echo icns > "$2"; shift; done'
  # Grove Explorer: not running unless FAKE_EXPLORER_RUNNING; never the real ps.
  stub fake-ps '[ -n "$FAKE_EXPLORER_RUNNING" ] && echo "  733 $GROVE_APPS_DIR/Grove Explorer.app/Contents/MacOS/GroveExplorer"; exit 0'
  # Nothing may stop or start the app: these only note that they were called.
  for tool in kill killall pkill open osascript launchctl; do
    stub "$tool" "echo \"$tool \$*\" >> \"\$BATS_TEST_TMPDIR/forbidden-args\""
  done
  export GROVE_PS="$BATS_TEST_TMPDIR/stubs/fake-ps"
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/stubs/swift"
  export GROVE_CODESIGN="$BATS_TEST_TMPDIR/stubs/codesign"
  export GROVE_SECURITY="$BATS_TEST_TMPDIR/stubs/security"
  export GROVE_OPENSSL="$BATS_TEST_TMPDIR/stubs/openssl"
  # The identity is there unless a test removes it.
  echo "$XA_HASH" > "$BATS_TEST_TMPDIR/keychain-identity"
  mkdir -p "$GROVE_STATE"
}

# xa_ready: what a finished apply leaves.
xa_ready() {
  load_module
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  printf '#!/bin/sh\n' > "$APP/Contents/MacOS/GroveExplorer"
  chmod +x "$APP/Contents/MacOS/GroveExplorer"
  _xa_source_hash > "$STAMP"
  echo "$XA_HASH" > "$BATS_TEST_TMPDIR/signed-with"
}

plist() { plutil -extract "$1" raw "$APP/Contents/Info.plist"; }

@test "explorer-app: about names it" {
  load_module
  [ "$(about)" = "Grove Explorer, the file browser" ]
}

@test "explorer-app: failed without swift" {
  load_module
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/no-such-swift"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"command line tools"* ]] || false
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"command line tools"* ]] || false
}

@test "explorer-app: needs work when the app is missing" {
  xa_ready
  rm -rf "$APP"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when the stamp differs from the source hash" {
  xa_ready
  echo stale > "$STAMP"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when the app has no stamp" {
  xa_ready
  rm "$STAMP"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when a tracked file in grove-explorer/app changed" {
  xa_ready
  echo "// changed" >> "$GROVE_APP_SRC/Sources/GroveExplorerCore/Entry.swift"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when grove-themes/app (the dependency) changed" {
  xa_ready
  run check
  [ "$status" -eq 0 ]
  echo "// changed" >> "$GROVE_THEMES_SRC/Package.swift"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when the Grove Icons font or map changed" {
  xa_ready
  echo x >> "$GROVE_CONFIG/vscode/grove-icons/grove-icon-theme.json"
  run check
  [ "$status" -eq 3 ]
  _xa_source_hash > "$STAMP"
  echo x >> "$GROVE_CONFIG/vscode/grove-icons/seti.woff"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: the hash counts the module and the version (both are in the bundle's Info.plist)" {
  load_module
  local all
  all="$(_xa_hash_input)"
  [[ "$all" == *"  modules/94-explorer-app/module.sh"* ]] || false
  [[ "$all" == *"  VERSION"* ]] || false
  [[ "$all" == *"  config/vscode/grove-icons/seti.woff"* ]] || false
  [[ "$all" == *"  config/vscode/grove-icons/grove-icon-theme.json"* ]] || false
  [[ "$all" == *"  Sources/GroveExplorer/main.swift"* ]] || false
  [[ "$all" == *"  Sources/GroveUI/GroveIcon.swift"* ]] || false
}

@test "explorer-app: an untracked build folder or the copied resources don't change the hash" {
  load_module
  before="$(_xa_source_hash)"
  mkdir -p "$GROVE_APP_SRC/.build" "$GROVE_THEMES_SRC/.build" "$RESOURCES"
  echo x > "$GROVE_APP_SRC/.build/x"
  echo x > "$GROVE_THEMES_SRC/.build/x"
  echo x > "$RESOURCES/seti.woff"
  [ "$(_xa_source_hash)" = "$before" ]
}

@test "explorer-app: the default source hash goes through the real source paths" {
  load_module
  unset GROVE_APP_SRC GROVE_THEMES_SRC
  run _xa_source_hash
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 40 ]
  [ "$(_xa_src)" = "$GROVE_ROOT/../grove-explorer/app" ]
  [ "$(_xa_themes_src)" = "$GROVE_ROOT/../grove-themes/app" ]
}

@test "explorer-app: needs work when the app is signed ad hoc" {
  xa_ready
  echo - > "$BATS_TEST_TMPDIR/signed-with"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when the app isn't signed" {
  xa_ready
  rm "$BATS_TEST_TMPDIR/signed-with"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: needs work when its config isn't linked" {
  xa_ready
  rm "$HOME/.config"
  run check
  [ "$status" -eq 3 ]
  # A folder of the same name that isn't the tracked one doesn't count.
  mkdir -p "$HOME/.config/grove-explorer"
  cp "$GROVE_CONFIG/grove-explorer/explorer.toml" "$HOME/.config/grove-explorer/"
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: ok when built, current, signed and its config linked" {
  xa_ready
  run check
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "explorer-app: ok while the app is open (it has no agent to be loaded)" {
  xa_ready
  export FAKE_EXPLORER_RUNNING=1
  run check
  [ "$status" -eq 0 ]
}

@test "explorer-app: check changes nothing" {
  xa_ready
  echo stale > "$STAMP"
  before="$(find "$BATS_TEST_TMPDIR" "$GROVE_CONFIG" -not -name '*-args' | sort)"
  run check
  [ "$status" -eq 3 ]
  after="$(find "$BATS_TEST_TMPDIR" "$GROVE_CONFIG" -not -name '*-args' | sort)"
  [ "$before" = "$after" ]
  [ ! -e "$BATS_TEST_TMPDIR/swift-args" ]
}

@test "explorer-app: apply builds release, assembles, signs and installs" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/swift-args")" = "build -c release" ]
  [ -x "$APP/Contents/MacOS/GroveExplorer" ]
  [ -f "$APP/Contents/Resources/AppIcon.icns" ]
  plutil -lint "$APP/Contents/Info.plist" >/dev/null
  grep -q -- "^--force --sign $XA_HASH .*/Grove Explorer.app$" "$BATS_TEST_TMPDIR/codesign-args"
  [ "$(cat "$STAMP")" = "$(_xa_source_hash)" ]
  # No build folder is left beside the app.
  [ "$(ls -A "$GROVE_APPS_DIR")" = "Grove Explorer.app" ]
  run check
  [ "$status" -eq 0 ]
}

@test "explorer-app: the bundle holds the Grove Icons font and map" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  cmp "$APP/Contents/Resources/seti.woff" "$GROVE_CONFIG/vscode/grove-icons/seti.woff"
  cmp "$APP/Contents/Resources/grove-icon-theme.json" "$GROVE_CONFIG/vscode/grove-icons/grove-icon-theme.json"
}

@test "explorer-app: apply puts the Grove Icons into the source before it builds (Package.swift needs them)" {
  load_module
  [ ! -e "$RESOURCES" ]
  run apply
  [ "$status" -eq 0 ]
  cmp "$RESOURCES/seti.woff" "$GROVE_CONFIG/vscode/grove-icons/seti.woff"
  cmp "$RESOURCES/grove-icon-theme.json" "$GROVE_CONFIG/vscode/grove-icons/grove-icon-theme.json"
}

@test "explorer-app: everything in the bundle is there before it is signed (the stamp too)" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(cd "$APP" && find . -type f | LC_ALL=C sort)" = "$(cat "$BATS_TEST_TMPDIR/signed-files")" ]
  grep -qx './Contents/Resources/source.stamp' "$BATS_TEST_TMPDIR/signed-files"
}

@test "explorer-app: the Info.plist names the app, its version and the groveexplorer URL scheme" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(plist CFBundleIdentifier)" = com.projectgrove.explorer ]
  [ "$(plist CFBundleName)" = "Grove Explorer" ]
  [ "$(plist CFBundleDisplayName)" = "Grove Explorer" ]
  [ "$(plist CFBundleExecutable)" = GroveExplorer ]
  [ "$(plist CFBundleIconFile)" = AppIcon ]
  [ "$(plist CFBundlePackageType)" = APPL ]
  [ "$(plist CFBundleShortVersionString)" = "$(cat "$GROVE_ROOT/VERSION")" ]
  [ "$(plist CFBundleVersion)" = "$(cat "$GROVE_ROOT/VERSION")" ]
  [ "$(plist LSMinimumSystemVersion)" = 14.0 ]
  [ "$(plist NSHighResolutionCapable)" = true ]
  [ "$(plist CFBundleURLTypes.0.CFBundleURLName)" = com.projectgrove.explorer ]
  [ "$(plist CFBundleURLTypes.0.CFBundleURLSchemes.0)" = groveexplorer ]
}

@test "explorer-app: the app is an ordinary one, in ⌘Tab (no LSUIElement)" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  run plist LSUIElement
  [ "$status" -ne 0 ]
  ! grep -q LSUIElement "$APP/Contents/Info.plist"
}

@test "explorer-app: the Info.plist says in a sentence why each folder is asked for" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  local key text
  for key in NSDesktopFolderUsageDescription NSDocumentsFolderUsageDescription NSDownloadsFolderUsageDescription \
    NSRemovableVolumesUsageDescription NSNetworkVolumesUsageDescription NSFileProviderDomainUsageDescription; do
    text="$(plist "$key")"
    [[ "$text" == "Grove Explorer "*. ]] || { echo "$key: $text"; false; }
  done
  [ "$(plist NSAppleEventsUsageDescription)" = "Grove Explorer asks Finder to show Get Info for the files you select." ]
}

@test "explorer-app: the Info.plist declares the favourite drag type the app exports" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(plist UTExportedTypeDeclarations.0.UTTypeIdentifier)" = com.projectgrove.explorer.favourite ]
  [ "$(plist UTExportedTypeDeclarations.0.UTTypeConformsTo.0)" = public.data ]
  # The same identifier as the app's `UTType(exportedAs:)`.
  grep -q 'UTType(exportedAs: "com.projectgrove.explorer.favourite")' "$GROVE_ROOT/../grove-explorer/app/Sources/GroveExplorer/DragDrop.swift"
  [ "$(grep -c 'UTType(exportedAs:' -r "$GROVE_ROOT/../grove-explorer/app/Sources" | awk -F: '{ n += $2 } END { print n }')" -eq 1 ]
}

@test "explorer-app: an open app is not stopped; apply says to reopen it" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  export FAKE_EXPLORER_RUNNING=1
  run apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Grove Explorer is open: quit and reopen it to use the new build"* ]] || false
  # The bundle on disk is the new build all the same.
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" = "#!/bin/sh" ]
  [ ! -e "$BATS_TEST_TMPDIR/forbidden-args" ]
}

@test "explorer-app: apply never starts the app, and says nothing about reopening one that is closed" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"reopen"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/forbidden-args" ]
}

@test "explorer-app: apply links the config folder when ~/.config isn't the tracked one" {
  load_module
  rm "$HOME/.config"
  mkdir -p "$HOME/.config"
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.config/grove-explorer")" = "$GROVE_CONFIG/grove-explorer" ]
  run check
  [ "$status" -eq 0 ]
}

@test "explorer-app: apply leaves a linked ~/.config as it is" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.config")" = "$GROVE_CONFIG" ]
  [ ! -L "$GROVE_CONFIG/grove-explorer" ]
  [ ! -d "$GROVE_STATE/backup" ]
}

@test "explorer-app: apply creates the signing identity when it's missing (as 96-keys-app does)" {
  load_module
  : > "$BATS_TEST_TMPDIR/keychain-identity"
  run apply
  [ "$status" -eq 0 ]
  grep -q '^import .* -T /usr/bin/codesign$' "$BATS_TEST_TMPDIR/security-args"
  grep -q -- "^--force --sign $XA_HASH " "$BATS_TEST_TMPDIR/codesign-args"
}

@test "explorer-app: a failed identity import stops apply and leaves the installed app" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  : > "$BATS_TEST_TMPDIR/keychain-identity"
  export FAKE_IMPORT_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *'could not make the "Grove Code Signing" certificate'* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" = old ]
  [ ! -e "$BATS_TEST_TMPDIR/swift-args" ]
}

@test "explorer-app: a failed build leaves the installed app and its stamp" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  echo oldstamp > "$STAMP"
  export FAKE_SWIFT_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: boom.swift:1: cannot find x"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" = old ]
  [ "$(cat "$STAMP")" = oldstamp ]
  [ "$(ls -A "$GROVE_APPS_DIR")" = "Grove Explorer.app" ]
}

@test "explorer-app: a failed signature shows codesign's error and keeps the installed app" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  echo oldstamp > "$STAMP"
  export FAKE_SIGN_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"errSecInternalComponent"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" = old ]
  [ "$(cat "$STAMP")" = oldstamp ]
  [ "$(ls -A "$GROVE_APPS_DIR")" = "Grove Explorer.app" ]
}

@test "explorer-app: the stamp is the hash of the source as it was before the build" {
  load_module
  before="$(_xa_source_hash)"
  export FAKE_SWIFT_EDITS=1
  run apply
  [ "$status" -eq 0 ]
  # What was built is the text from before the edit: the stamp says so, and
  # check then sees that the app is behind its source.
  [ "$(cat "$STAMP")" = "$before" ]
  [ "$(_xa_source_hash)" != "$before" ]
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: a new bundle that can't be put in place brings the old one back" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  echo oldstamp > "$STAMP"
  # mv fails only for the new bundle going to its place.
  stub mv '
case "$1" in
  */old/*) ;;
  */.grove-explorer.*/Grove\ Explorer.app) [ "$2" = "$GROVE_APPS_DIR/Grove Explorer.app" ] && { echo "mv: $2: Operation not permitted" >&2; exit 1; } ;;
esac
exec /bin/mv "$@"'
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"could not put Grove Explorer.app in place"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" = old ]
  [ "$(cat "$STAMP")" = oldstamp ]
  [ "$(ls -A "$GROVE_APPS_DIR")" = "Grove Explorer.app" ]
}

@test "explorer-app: the old bundle is never removed before the new one is in place" {
  xa_ready
  echo old > "$APP/Contents/MacOS/GroveExplorer"
  # rm may only ever be given the build folder, never the installed app.
  stub rm '
for a in "$@"; do
  [ "$a" = "$GROVE_APPS_DIR/Grove Explorer.app" ] && echo "rm $*" >> "$BATS_TEST_TMPDIR/rm-of-the-app"
done
exec /bin/rm "$@"'
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/rm-of-the-app" ]
  [ "$(cat "$APP/Contents/MacOS/GroveExplorer")" != old ]
  [ "$(ls -A "$GROVE_APPS_DIR")" = "Grove Explorer.app" ]
}

@test "explorer-app: without HOME and GROVE_APPS_DIR nothing is built, checked or removed at /" {
  load_module
  unset GROVE_APPS_DIR
  run env -u HOME bash -c '. "$1"; _xa_apps' _ "$MODULE_DIR/module.sh"
  [ "$status" -ne 0 ]
  [ -z "$output" ] || [[ "$output" == *"HOME"* ]] || false
  # remove gives up before any rm (it would otherwise be "/Grove Explorer.app").
  stub rm 'echo "rm $*" >> "$BATS_TEST_TMPDIR/rm-args"; exec /bin/rm "$@"'
  HOME= run remove
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/rm-args" ]
  HOME= run apply
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/swift-args" ]
}

@test "explorer-app: codesign defaults to /usr/bin/codesign (the key trusts it by path)" {
  load_module
  unset GROVE_CODESIGN
  [ "$(_xa_codesign)" = /usr/bin/codesign ]
}

@test "explorer-app: remove takes the app away and leaves the config and the session" {
  xa_ready
  echo '{}' > "$GROVE_STATE/explorer-session.json"
  echo '# mine' > "$GROVE_CONFIG/grove-explorer/explorer.local.toml"
  run remove
  [ "$status" -eq 0 ]
  [ ! -e "$APP" ]
  [ -f "$GROVE_STATE/explorer-session.json" ]
  [ -f "$HOME/.config/grove-explorer/explorer.toml" ]
  [ "$(cat "$HOME/.config/grove-explorer/explorer.local.toml")" = "# mine" ]
  [ ! -e "$BATS_TEST_TMPDIR/forbidden-args" ]
  run check
  [ "$status" -eq 3 ]
}

@test "explorer-app: remove is fine when the app isn't there" {
  load_module
  run remove
  [ "$status" -eq 0 ]
}

@test "explorer-app: the README lists the module" {
  grep -q '^| `94-explorer-app` | Grove Explorer, the file browser: builds the app and installs it to ~/Applications (it is opened like any app; nothing starts it at login) |$' "$GROVE_ROOT/README.md"
}

@test "explorer-app: AeroSpace tiles the window (no float rule names the app, and its title isn't the Grove window's)" {
  ! grep -q "com.projectgrove.explorer" "$GROVE_ROOT/config/aerospace/aerospace.base.toml"
  grep -q 'Window("Grove Explorer", id: "explorer")' "$GROVE_ROOT/../grove-explorer/app/Sources/GroveExplorer/ExplorerApp.swift"
}

@test "explorer-app: the Grove menu has the Files row, which opens the app" {
  local menu="$GROVE_ROOT/config/grove/menu.toml"
  [ "$(grep -A3 '^\[files\]$' "$menu")" = '[files]
title = "Files"
icon = "folder"
run = "open -a '"'"'Grove Explorer'"'"'"' ]
  # After Appearance (its last row is Light Soft), before Grove Keys.
  [ "$(grep '^\[[a-z-]*\]$' "$menu" | tr '\n' ' ')" = "[appearance] [files] [keys] [update] [learn] [about] [system] [global-menu] " ]
  cmp "$menu" "$GROVE_ROOT/../grove-keys/app/Tests/GroveKeysCoreTests/Fixtures/menu.toml"
}
