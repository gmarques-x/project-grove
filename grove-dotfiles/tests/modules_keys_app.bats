# shellcheck disable=SC2016,SC1090,SC1091,SC2154,SC2030,SC2031
# 96-keys-app: builds Grove Keys, installs it and starts it at login, against
# fake swift, codesign, security, openssl, iconutil, sips, launchctl, hidutil
# and open and temp folders. The fake keychain is a file: keychain-identity
# holds the hash of "Grove Code Signing" when it's there, and signed-with the
# identity the app was last signed with ("-" is ad hoc).
load helpers

KA_MODULE=96-keys-app

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$KA_MODULE"
  . "$MODULE_DIR/module.sh"
}

# A throwaway git copy of a source tree, so a fake swift can build into it and
# a test can change a tracked file.
git_copy() {
  mkdir -p "$2"
  rsync -a --exclude .build "$1/" "$2/"
  git -C "$2" init -q
  git -C "$2" add -A
}

setup() {
  grove_test_setup
  export GROVE_APP_SRC="$BATS_TEST_TMPDIR/keys-src"
  export GROVE_THEMES_SRC="$BATS_TEST_TMPDIR/themes-src"
  git_copy "$GROVE_ROOT/../grove-keys/app" "$GROVE_APP_SRC"
  git_copy "$GROVE_ROOT/../grove-themes/app" "$GROVE_THEMES_SRC"
  export GROVE_APPS_DIR="$BATS_TEST_TMPDIR/Applications"
  export GROVE_AGENTS_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  mkdir -p "$GROVE_APPS_DIR" "$GROVE_AGENTS_DIR"
  # ~/.config is the tracked config (a copy here): keys.toml and the base.
  ln -s "$GROVE_CONFIG" "$HOME/.config"
  APP="$GROVE_APPS_DIR/Grove Keys.app"
  AGENT="$GROVE_AGENTS_DIR/com.projectgrove.keys.plist"
  AEROSPACE_TOML="$HOME/.config/aerospace/aerospace.toml"
  UID_="$(id -u)"
  # The "app": renders keys.toml to the output file (the real one renders
  # keys.toml + the base; here the keys file stands in for the result).
  cat > "$BATS_TEST_TMPDIR/fake-groovekeys" <<'FAKE'
#!/bin/bash
[ "$1" = --render-aerospace ] || exit 0
echo "GroveKeys $*" >> "$BATS_TEST_TMPDIR/groovekeys-args"
if [ -n "$FAKE_RENDER_FAIL" ]; then echo "keys.toml line 14: unknown key" >&2; exit 1; fi
out="${GROVE_KEYS_RENDER_OUT:-$HOME/.config/aerospace/aerospace.toml}"
mkdir -p "$(dirname "$out")"
{ echo "# rendered"; cat "$HOME/.config/grove-keys/keys.toml"; } > "$out"
FAKE
  stub swift '
echo "$*" >> "$BATS_TEST_TMPDIR/swift-args"
if [ -n "$FAKE_SWIFT_FAIL" ]; then echo "error: boom.swift:1: cannot find x" >&2; exit 1; fi
mkdir -p .build/release && cp "$BATS_TEST_TMPDIR/fake-groovekeys" .build/release/GroveKeys && chmod +x .build/release/GroveKeys'
  stub codesign '
if [ -n "$FAKE_SIGN_FAIL" ] && [ "$1" = --force ]; then echo "$3: errSecInternalComponent" >&2; exit 1; fi
if [ "$1" = -dvv ]; then
  echo "Executable=$2/Contents/MacOS/GroveKeys" >&2
  case "$(cat "$BATS_TEST_TMPDIR/signed-with" 2>/dev/null)" in
    "") echo "$2: code object is not signed at all" >&2; exit 1 ;;
    -) echo "Signature=adhoc" >&2 ;;
    *) printf "Authority=Grove Code Signing\nTeamIdentifier=not set\n" >&2 ;;
  esac
  exit 0
fi
echo "$*" >> "$BATS_TEST_TMPDIR/codesign-args"
[ "$1" = --force ] && [ "$2" = --sign ] && echo "$3" > "$BATS_TEST_TMPDIR/signed-with"
exit 0'
  KA_HASH=F68B51349BDD56C6A96FA6D0AAA8119A7B9F93B7
  # security: find-identity lists the fake identities, one "HASH [ERROR]" line
  # each in keychain-identity (the error is CSSMERR_TP_NOT_TRUSTED, as for a
  # self-signed one, unless the line names another); import appends one and
  # notes the folder the .p12 was in.
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
    printf "     %d identities found\n" "$n"
    printf "\n  Valid identities only\n     0 valid identities found\n" ;;
  import)
    [ -f "$2" ] || exit 1
    dirname "$2" > "$BATS_TEST_TMPDIR/p12-dir"
    if [ -n "$FAKE_IMPORT_FAIL" ]; then echo "security: SecKeychainItemImport: User interaction is not allowed." >&2; exit 1; fi
    echo F68B51349BDD56C6A96FA6D0AAA8119A7B9F93B7 >> "$BATS_TEST_TMPDIR/keychain-identity" ;;
esac
exit 0'
  # openssl: writes the files it is asked for and keeps a copy of the config.
  stub openssl '
echo "$*" >> "$BATS_TEST_TMPDIR/openssl-args"
[ "$1" = rand ] && { echo 00112233445566778899aabbccddeeff; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    -keyout|-out) echo pem > "$2" ;;
    -config) cp "$2" "$BATS_TEST_TMPDIR/openssl.cnf" ;;
  esac
  shift
done
exit 0'
  stub sips 'echo "$*" >> "$BATS_TEST_TMPDIR/sips-args"; while [ $# -gt 0 ]; do [ "$1" = --out ] && cp "$BATS_TEST_TMPDIR/stubs/sips" "$2"; shift; done'
  stub iconutil 'echo "$*" >> "$BATS_TEST_TMPDIR/iconutil-args"; while [ $# -gt 0 ]; do [ "$1" = -o ] && echo icns > "$2"; shift; done'
  stub open 'echo "$*" >> "$BATS_TEST_TMPDIR/open-args"'
  # hidutil prints a mapping unless FAKE_NO_MAPPING (a cleared one is empty arrays).
  stub hidutil '
if [ -n "$FAKE_NO_MAPPING" ]; then printf "(\n)\n"; exit 0; fi
printf "(\n        {\n        HIDKeyboardModifierMappingDst = 30064771181;\n        HIDKeyboardModifierMappingSrc = 30064771129;\n    }\n)\n"'
  stub launchctl '
echo "$*" >> "$BATS_TEST_TMPDIR/launchctl-args"
linger="$BATS_TEST_TMPDIR/linger"
fails="$BATS_TEST_TMPDIR/bootstrap-fails"
case "$1" in
  print)
    [ -e "$BATS_TEST_TMPDIR/loaded" ] && exit 0
    n="$(cat "$linger" 2>/dev/null || echo 0)"
    [ "$n" -gt 0 ] || exit 1
    echo $((n - 1)) > "$linger" ;;
  bootstrap)
    [ "$(cat "$linger" 2>/dev/null || echo 0)" -eq 0 ] || exit 5
    n="$(cat "$fails" 2>/dev/null || echo "${FAKE_BOOTSTRAP_FAILS:-0}")"
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$fails"; exit 5; fi
    touch "$BATS_TEST_TMPDIR/loaded" ;;
  bootout) rm -f "$BATS_TEST_TMPDIR/loaded"; echo "${FAKE_LINGER:-0}" > "$linger" ;;
  *) : ;;
esac'
  # AeroSpace: not running unless FAKE_AEROSPACE_RUNNING; never the real one.
  stub fake-ps '[ -n "$FAKE_AEROSPACE_RUNNING" ] && echo "  412 /Applications/AeroSpace.app/Contents/MacOS/AeroSpace"; exit 0'
  stub aerospace '
echo "$*" >> "$BATS_TEST_TMPDIR/aerospace-args"
if [ -n "$FAKE_RELOAD_FAIL" ]; then echo "unknown key foo" >&2; exit 1; fi'
  export GROVE_PS="$BATS_TEST_TMPDIR/stubs/fake-ps"
  export GROVE_AEROSPACE="$BATS_TEST_TMPDIR/stubs/aerospace"
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/stubs/swift"
  export GROVE_CODESIGN="$BATS_TEST_TMPDIR/stubs/codesign"
  export GROVE_SECURITY="$BATS_TEST_TMPDIR/stubs/security"
  export GROVE_OPENSSL="$BATS_TEST_TMPDIR/stubs/openssl"
  # The identity is there unless a test removes it.
  echo "$KA_HASH" > "$BATS_TEST_TMPDIR/keychain-identity"
  export GROVE_LAUNCHCTL="$BATS_TEST_TMPDIR/stubs/launchctl"
  export GROVE_HIDUTIL="$BATS_TEST_TMPDIR/stubs/hidutil"
  mkdir -p "$GROVE_STATE"
}

# keys_state ACCESSIBILITY INPUT_MONITORING MAPPING: the app's keys.json.
keys_state() {
  printf '{\n  "accessibility" : %s,\n  "input_monitoring" : %s,\n  "mapping" : %s\n}\n' "$1" "$2" "$3" > "$GROVE_STATE/keys.json"
}

# ka_ready: what a finished apply leaves.
ka_ready() {
  load_module
  mkdir -p "$APP/Contents/MacOS"
  cp "$BATS_TEST_TMPDIR/fake-groovekeys" "$APP/Contents/MacOS/GroveKeys"
  chmod +x "$APP/Contents/MacOS/GroveKeys"
  _ka_source_hash > "$GROVE_STATE/keys-app.stamp"
  _ka_agent_plist > "$AGENT"
  touch "$BATS_TEST_TMPDIR/loaded"
  "$APP/Contents/MacOS/GroveKeys" --render-aerospace
  keys_state true true true
  echo "$KA_HASH" > "$BATS_TEST_TMPDIR/signed-with"
  : > "$BATS_TEST_TMPDIR/groovekeys-args"
}

@test "keys-app: about names it" {
  load_module
  [ "$(about)" = "Grove Keys in the menu bar" ]
}

@test "keys-app: failed without swift" {
  load_module
  export GROVE_SWIFT="$BATS_TEST_TMPDIR/no-such-swift"
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"command line tools"* ]] || false
}

@test "keys-app: needs work when the app is missing" {
  ka_ready
  rm -rf "$APP"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when the source changed" {
  ka_ready
  echo stale > "$GROVE_STATE/keys-app.stamp"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when a tracked file in grove-keys/app changed" {
  ka_ready
  echo "// changed" >> "$GROVE_APP_SRC/Sources/GroveKeysCore/Shortcut.swift"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when grove-themes/app (the dependency) changed" {
  ka_ready
  run check
  [ "$status" -eq 0 ]
  echo "// changed" >> "$GROVE_THEMES_SRC/Package.swift"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: an untracked build folder doesn't change the hash" {
  load_module
  before="$(_ka_source_hash)"
  mkdir -p "$GROVE_APP_SRC/.build" "$GROVE_THEMES_SRC/.build"
  echo x > "$GROVE_APP_SRC/.build/x"
  echo x > "$GROVE_THEMES_SRC/.build/x"
  [ "$(_ka_source_hash)" = "$before" ]
}

@test "keys-app: the default source hash goes through the real grove-themes path" {
  load_module
  unset GROVE_APP_SRC GROVE_THEMES_SRC
  run _ka_source_hash
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 40 ]
  [ "$(_ka_themes_src)" = "$GROVE_ROOT/../grove-themes/app" ]
  [ "$(_ka_src)" = "$GROVE_ROOT/../grove-keys/app" ]
}

@test "keys-app: needs work when the agent file differs" {
  ka_ready
  echo other > "$AGENT"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when the agent isn't loaded" {
  ka_ready
  rm "$BATS_TEST_TMPDIR/loaded"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when aerospace.toml is stale" {
  ka_ready
  echo "# old" > "$AEROSPACE_TOML"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when aerospace.toml is missing" {
  ka_ready
  rm "$AEROSPACE_TOML"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: needs work when keys.toml changed since the render" {
  ka_ready
  echo '# an edit' >> "$HOME/.config/grove-keys/keys.toml"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: the check renders to a temp file, not to aerospace.toml" {
  ka_ready
  echo "# old" > "$AEROSPACE_TOML"
  run check
  [ "$(cat "$AEROSPACE_TOML")" = "# old" ]
  grep -q -- '--render-aerospace' "$BATS_TEST_TMPDIR/groovekeys-args"
}

@test "keys-app: fails with the red line when keys.toml can't be rendered" {
  ka_ready
  export FAKE_RENDER_FAIL=1
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"keys.toml line 14: unknown key"* ]] || false
}

@test "keys-app: fails when input monitoring is off" {
  ka_ready
  keys_state true false false
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Grove Keys needs Input Monitoring: System Settings › Privacy & Security"* ]] || false
}

@test "keys-app: fails when accessibility is off" {
  ka_ready
  keys_state false true false
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Grove Keys needs Accessibility: System Settings › Privacy & Security"* ]] || false
}

@test "keys-app: needs work before the app has reported its permissions" {
  ka_ready
  rm "$GROVE_STATE/keys.json"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: fails when the mapping is missing while enabled" {
  ka_ready
  export FAKE_NO_MAPPING=1
  run check
  [ "$status" -eq 1 ]
  [[ "$output" == *"Caps Lock isn't mapped to F18"* ]] || false
}

@test "keys-app: no mapping is fine while Hyper is disabled" {
  ka_ready
  export FAKE_NO_MAPPING=1
  sed -i '' 's/^enabled = true/enabled = false/' "$HOME/.config/grove-keys/keys.toml"
  grep -q '^enabled = false' "$HOME/.config/grove-keys/keys.toml"
  "$APP/Contents/MacOS/GroveKeys" --render-aerospace
  run check
  [ "$status" -eq 0 ]
}

@test "keys-app: ok when built, current, loaded, rendered, allowed and mapped" {
  ka_ready
  run check
  [ "$status" -eq 0 ]
}

@test "keys-app: check changes nothing" {
  ka_ready
  rm "$BATS_TEST_TMPDIR/loaded"
  before="$(find "$BATS_TEST_TMPDIR" -not -name '*-args' | sort)"
  run check
  [ "$status" -eq 3 ]
  after="$(find "$BATS_TEST_TMPDIR" -not -name '*-args' | sort)"
  [ "$before" = "$after" ]
  run grep -q '^open' "$BATS_TEST_TMPDIR/open-args"
  [ "$status" -ne 0 ]
}

@test "keys-app: agent plist runs the app, restarts on crash only, and has a PATH" {
  load_module
  _ka_agent_plist > "$BATS_TEST_TMPDIR/a.plist"
  [ "$(plutil -extract Label raw "$BATS_TEST_TMPDIR/a.plist")" = com.projectgrove.keys ]
  [ "$(plutil -extract ProgramArguments.0 raw "$BATS_TEST_TMPDIR/a.plist")" = "$APP/Contents/MacOS/GroveKeys" ]
  [ "$(plutil -extract RunAtLoad raw "$BATS_TEST_TMPDIR/a.plist")" = true ]
  [ "$(plutil -extract ProcessType raw "$BATS_TEST_TMPDIR/a.plist")" = Interactive ]
  [ "$(plutil -extract KeepAlive.SuccessfulExit raw "$BATS_TEST_TMPDIR/a.plist")" = false ]
  [ "$(plutil -extract EnvironmentVariables.PATH raw "$BATS_TEST_TMPDIR/a.plist")" = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
}

@test "keys-app: apply builds, assembles, signs, installs, renders and loads" {
  load_module
  keys_state true true true
  run apply
  [ "$status" -eq 0 ]
  [ -x "$APP/Contents/MacOS/GroveKeys" ]
  [ -f "$APP/Contents/Resources/AppIcon.icns" ]
  [ "$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")" = com.projectgrove.keys ]
  [ "$(plutil -extract CFBundleName raw "$APP/Contents/Info.plist")" = "Grove Keys" ]
  [ "$(plutil -extract CFBundleExecutable raw "$APP/Contents/Info.plist")" = GroveKeys ]
  [ "$(plutil -extract LSUIElement raw "$APP/Contents/Info.plist")" = true ]
  grep -q -- "^--force --sign $KA_HASH .*/Grove Keys.app$" "$BATS_TEST_TMPDIR/codesign-args"
  [ "$(cat "$GROVE_STATE/keys-app.stamp")" = "$(_ka_source_hash)" ]
  [ "$(cat "$AGENT")" = "$(_ka_agent_plist)" ]
  [ -f "$AEROSPACE_TOML" ]
  grep -q '^bootstrap gui/'"$UID_ $AGENT"'$' "$BATS_TEST_TMPDIR/launchctl-args"
  run check
  [ "$status" -eq 0 ]
}

@test "keys-app: apply renders after installing, before it loads the agent" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  grep -q -- '--render-aerospace' "$BATS_TEST_TMPDIR/groovekeys-args"
  # The rendered file is the one in ~/.config/aerospace, not a temp file.
  head -1 "$AEROSPACE_TOML" | grep -q '^# rendered'
}

@test "keys-app: apply reloads a running AeroSpace after rendering" {
  load_module
  export FAKE_AEROSPACE_RUNNING=1
  # The render must be on disk before the reload.
  stub aerospace 'head -1 "$HOME/.config/aerospace/aerospace.toml" > "$BATS_TEST_TMPDIR/seen"; echo "$*" >> "$BATS_TEST_TMPDIR/aerospace-args"'
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/aerospace-args")" = reload-config ]
  [ "$(cat "$BATS_TEST_TMPDIR/seen")" = "# rendered" ]
}

@test "keys-app: apply leaves AeroSpace alone when it isn't running" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/aerospace-args" ]
}

@test "keys-app: apply notes a reload AeroSpace refused and still loads the app" {
  load_module
  export FAKE_AEROSPACE_RUNNING=1 FAKE_RELOAD_FAIL=1
  run apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"AeroSpace didn't take the new config: unknown key foo"* ]] || false
  grep -q '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args"
}

@test "keys-app: a bad keys.toml stops apply before any reload" {
  load_module
  export FAKE_AEROSPACE_RUNNING=1 FAKE_RENDER_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [ ! -e "$BATS_TEST_TMPDIR/aerospace-args" ]
}

@test "keys-app: apply fails with the red line when keys.toml is bad" {
  load_module
  export FAKE_RENDER_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"keys.toml line 14: unknown key"* ]] || false
}

@test "keys-app: apply opens the Privacy panes when permissions are missing" {
  load_module
  keys_state false false false
  run apply
  [ "$status" -eq 0 ]
  grep -qx 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility' "$BATS_TEST_TMPDIR/open-args"
  grep -qx 'x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent' "$BATS_TEST_TMPDIR/open-args"
}

@test "keys-app: apply opens only the pane that is missing" {
  load_module
  keys_state true false false
  run apply
  [ "$status" -eq 0 ]
  run grep -c 'Privacy_Accessibility' "$BATS_TEST_TMPDIR/open-args"
  [ "$output" = 0 ]
  grep -q 'Privacy_ListenEvent' "$BATS_TEST_TMPDIR/open-args"
}

@test "keys-app: apply opens nothing when permissions are granted" {
  load_module
  keys_state true true true
  run apply
  [ "$status" -eq 0 ]
  [ ! -s "$BATS_TEST_TMPDIR/open-args" ] || false
}

@test "keys-app: apply loads a running app's job again (launchd pins it to the old build's code hash)" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  _ka_agent_plist > "$AGENT"
  run apply
  [ "$status" -eq 0 ]
  grep -q "^bootout gui/$UID_/com.projectgrove.keys\$" "$BATS_TEST_TMPDIR/launchctl-args"
  grep -q "^bootstrap gui/$UID_ $AGENT\$" "$BATS_TEST_TMPDIR/launchctl-args"
  run grep -q '^kickstart' "$BATS_TEST_TMPDIR/launchctl-args"
  [ "$status" -ne 0 ]
}

@test "keys-app: apply reloads a loaded agent whose plist changed" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  echo old > "$AGENT"
  run apply
  [ "$status" -eq 0 ]
  [ "$(cat "$AGENT")" = "$(_ka_agent_plist)" ]
  grep -q "^bootout gui/$UID_/com.projectgrove.keys\$" "$BATS_TEST_TMPDIR/launchctl-args"
  [ "$(grep -n '^bootout' "$BATS_TEST_TMPDIR/launchctl-args" | cut -d: -f1)" -lt "$(grep -n '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args" | cut -d: -f1)" ]
}

@test "keys-app: apply waits for a bootout to finish before bootstrapping" {
  load_module
  touch "$BATS_TEST_TMPDIR/loaded"
  echo old > "$AGENT"
  export FAKE_LINGER=3
  run apply
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/loaded" ]
  [ "$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/launchctl-args" | sed 1,/^bootout/d | tr '\n' ' ')" = "print print print print bootstrap " ]
}

@test "keys-app: apply retries a bootstrap that fails once" {
  load_module
  export FAKE_BOOTSTRAP_FAILS=1
  run apply
  [ "$status" -eq 0 ]
  [ "$(grep -c '^bootstrap' "$BATS_TEST_TMPDIR/launchctl-args")" -eq 2 ]
}

@test "keys-app: apply fails when bootstrap keeps failing" {
  load_module
  export FAKE_BOOTSTRAP_FAILS=5
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"launchctl bootstrap"* ]] || false
}

@test "keys-app: needs work when the app is signed ad hoc" {
  ka_ready
  echo - > "$BATS_TEST_TMPDIR/signed-with"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: ok when the app is signed by Grove Code Signing" {
  ka_ready
  run check
  [ "$status" -eq 0 ]
  grep -q -- "^find-identity -p codesigning" "$BATS_TEST_TMPDIR/security-args"
}

@test "keys-app: needs work when the signing identity is missing" {
  ka_ready
  rm "$BATS_TEST_TMPDIR/keychain-identity"
  run check
  [ "$status" -eq 3 ]
}

@test "keys-app: apply creates the signing identity when it's missing" {
  load_module
  rm "$BATS_TEST_TMPDIR/keychain-identity"
  run apply
  [ "$status" -eq 0 ]
  grep -q -- '^req -x509 -newkey rsa:2048 -nodes .*-days 3650 ' "$BATS_TEST_TMPDIR/openssl-args"
  grep -qx 'CN = Grove Code Signing' "$BATS_TEST_TMPDIR/openssl.cnf"
  grep -qx 'keyUsage = critical,digitalSignature' "$BATS_TEST_TMPDIR/openssl.cnf"
  grep -qx 'extendedKeyUsage = critical,codeSigning' "$BATS_TEST_TMPDIR/openssl.cnf"
  grep -q -- '^pkcs12 -export .*-passout env:GROVE_KA_P12_PASS ' "$BATS_TEST_TMPDIR/openssl-args"
  run grep -q 'pass:' "$BATS_TEST_TMPDIR/openssl-args"
  [ "$status" -ne 0 ]
  grep -q -- "^import .*\.p12 -k $HOME/Library/Keychains/login.keychain-db -P .* -T /usr/bin/codesign\$" "$BATS_TEST_TMPDIR/security-args"
  # The key, certificate and .p12 are gone.
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/p12-dir")" ]
  grep -q -- "^--force --sign $KA_HASH .*/Grove Keys.app$" "$BATS_TEST_TMPDIR/codesign-args"
}

@test "keys-app: apply doesn't recreate an identity that is there" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  run grep -q '^import' "$BATS_TEST_TMPDIR/security-args"
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/openssl-args" ]
}

@test "keys-app: apply signs with the identity's hash" {
  load_module
  echo 0123456789ABCDEF0123456789ABCDEF01234567 > "$BATS_TEST_TMPDIR/keychain-identity"
  run apply
  [ "$status" -eq 0 ]
  grep -q -- "^--force --sign 0123456789ABCDEF0123456789ABCDEF01234567 .*/Grove Keys.app$" "$BATS_TEST_TMPDIR/codesign-args"
}

@test "keys-app: a failed identity import stops apply and leaves the installed app" {
  ka_ready
  echo old > "$APP/Contents/MacOS/GroveKeys"
  rm "$BATS_TEST_TMPDIR/keychain-identity"
  export FAKE_IMPORT_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"Grove Code Signing"* ]] || false
  [[ "$output" == *"security import failed"* ]] || false
  [[ "$output" == *"User interaction is not allowed."* ]] || false
  [[ "$output" == *"unlock the login keychain and run grove install keys-app again"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveKeys")" = old ]
  [ ! -e "$(cat "$BATS_TEST_TMPDIR/p12-dir")" ]
  [ ! -e "$BATS_TEST_TMPDIR/codesign-args" ]
}

@test "keys-app: looks for the identity in the login keychain" {
  ka_ready
  run check
  [ "$status" -eq 0 ]
  grep -qx -- "find-identity -p codesigning $HOME/Library/Keychains/login.keychain-db" "$BATS_TEST_TMPDIR/security-args"
}

@test "keys-app: an expired identity is skipped and a new one made" {
  load_module
  echo "0123456789ABCDEF0123456789ABCDEF01234567 CSSMERR_TP_CERT_EXPIRED" > "$BATS_TEST_TMPDIR/keychain-identity"
  [ -z "$(_ka_identity_hash)" ]
  run apply
  [ "$status" -eq 0 ]
  grep -q '^import' "$BATS_TEST_TMPDIR/security-args"
  grep -q -- "^--force --sign $KA_HASH .*/Grove Keys.app$" "$BATS_TEST_TMPDIR/codesign-args"
}

@test "keys-app: an identity with another error is skipped" {
  load_module
  echo "0123456789ABCDEF0123456789ABCDEF01234567 CSSMERR_TP_CERT_REVOKED" > "$BATS_TEST_TMPDIR/keychain-identity"
  [ -z "$(_ka_identity_hash)" ]
  echo "0123456789ABCDEF0123456789ABCDEF01234567 CSSMERR_TP_INVALID_CERTIFICATE" > "$BATS_TEST_TMPDIR/keychain-identity"
  [ -z "$(_ka_identity_hash)" ]
}

@test "keys-app: a failed signature shows codesign's error and keeps the installed app" {
  ka_ready
  echo old > "$APP/Contents/MacOS/GroveKeys"
  export FAKE_SIGN_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"codesign failed"* ]] || false
  [[ "$output" == *"errSecInternalComponent"* ]] || false
  [[ "$output" == *"unlock the login keychain and run grove install keys-app again"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveKeys")" = old ]
}

@test "keys-app: codesign defaults to /usr/bin/codesign" {
  load_module
  unset GROVE_CODESIGN
  [ "$(_ka_codesign)" = /usr/bin/codesign ]
}

@test "keys-app: a failed build leaves the installed app and stamp" {
  ka_ready
  echo old > "$APP/Contents/MacOS/GroveKeys"
  echo oldstamp > "$GROVE_STATE/keys-app.stamp"
  export FAKE_SWIFT_FAIL=1
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"error: boom.swift:1: cannot find x"* ]] || false
  [ "$(cat "$APP/Contents/MacOS/GroveKeys")" = old ]
  [ "$(cat "$GROVE_STATE/keys-app.stamp")" = oldstamp ]
}

@test "keys-app: the README lists the module" {
  grep -q '^| `96-keys-app` | Grove Keys in the menu bar: Caps Lock as Hyper, the keyboard window, and the AeroSpace config it renders; builds the app, installs it to ~/Applications and starts it at login |$' "$GROVE_ROOT/README.md"
}

# ka_defaults FILE: keys.toml without the entries of [launch], which holds
# the user's own launchers. (Monitors are in monitors.toml, untracked.)
ka_defaults() {
  awk '/^\[/ { own = ($0 ~ /^\[launch\]/); print; next } !own' "$1"
}

@test "keys-app: the shipped keys.toml is the app's test fixture, apart from the user's launchers" {
  diff <(ka_defaults "$GROVE_ROOT/config/grove-keys/keys.toml") \
    <(ka_defaults "$GROVE_ROOT/../grove-keys/app/Tests/GroveKeysCoreTests/Fixtures/keys.toml")
}

@test "keys-app: the guard still catches a change outside the launchers" {
  local f="$BATS_TEST_TMPDIR/keys.toml"
  sed 's/^tap_ms = 200/tap_ms = 250/' "$GROVE_ROOT/config/grove-keys/keys.toml" > "$f"
  ! diff -q <(ka_defaults "$f") <(ka_defaults "$GROVE_ROOT/../grove-keys/app/Tests/GroveKeysCoreTests/Fixtures/keys.toml") >/dev/null
}

@test "keys-app: swift test passes" {
  # The real swift: setup puts a fake one first on PATH, which would "build"
  # a fake app into the real source tree.
  local path="/usr/bin:/bin:/usr/sbin:/sbin"
  PATH="$path" command -v swift >/dev/null || skip "swift isn't installed"
  cd "$GROVE_ROOT/../grove-keys/app"
  run env PATH="$path" swift test
  [ "$status" -eq 0 ]
  # The real suite ran (not a fake swift that "builds" into this source tree).
  [[ "$output" == *"Test run with"* ]] || false
}

@test "keys-app: the bundle registers the grovekeys URL scheme for the bar's key glyph" {
  load_module
  _ka_info_plist | grep -q '<key>CFBundleURLTypes</key>'
  _ka_info_plist | grep -q '<string>grovekeys</string>'
  _ka_info_plist | plutil -lint - >/dev/null
}
