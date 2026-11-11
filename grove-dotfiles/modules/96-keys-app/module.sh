# shellcheck shell=bash
# 96-keys-app: Grove Keys, the menu bar app in grove-keys/app, is built with
# swift, assembled into ~/Applications/Grove Keys.app, signed with the
# self-signed "Grove Code Signing" identity in the login keychain (made once,
# here) and started at login by a LaunchAgent. It also renders ~/.config/aerospace/
# aerospace.toml from keys.toml and the base (GroveKeys --render-aerospace).
# A stamp holds a hash of the tracked source files of the app and of
# grove-themes/app (its package dependency), so check notices when the app is
# out of date.
# Tests point GROVE_SWIFT, GROVE_LAUNCHCTL, GROVE_CODESIGN, GROVE_SECURITY,
# GROVE_OPENSSL, GROVE_HIDUTIL,
# GROVE_AEROSPACE, GROVE_PS (as 98-aerospace's), GROVE_APPS_DIR and
# GROVE_AGENTS_DIR at fakes and temp folders (GROVE_APP_SRC and
# GROVE_THEMES_SRC at copies of the sources, because swift builds into them).

about() { echo "Grove Keys in the menu bar"; }

_KA_LABEL=com.projectgrove.keys
_KA_IDENTITY="Grove Code Signing"

_ka_swift() { printf '%s' "${GROVE_SWIFT:-swift}"; }
_ka_launchctl() { printf '%s' "${GROVE_LAUNCHCTL:-launchctl}"; }
# The key's access list trusts /usr/bin/codesign by path, so use exactly that.
_ka_codesign() { printf '%s' "${GROVE_CODESIGN:-/usr/bin/codesign}"; }
_ka_security() { printf '%s' "${GROVE_SECURITY:-/usr/bin/security}"; }
_ka_openssl() { printf '%s' "${GROVE_OPENSSL:-/usr/bin/openssl}"; }
_ka_keychain() { printf '%s/Library/Keychains/login.keychain-db' "$HOME"; }
_ka_apps() { printf '%s' "${GROVE_APPS_DIR:-$HOME/Applications}"; }
_ka_app() { printf '%s/Grove Keys.app' "$(_ka_apps)"; }
_ka_agent() { printf '%s/%s.plist' "${GROVE_AGENTS_DIR:-$HOME/Library/LaunchAgents}" "$_KA_LABEL"; }
_ka_stamp() { printf '%s/keys-app.stamp' "$GROVE_STATE"; }
_ka_hidutil() { printf '%s' "${GROVE_HIDUTIL:-hidutil}"; }
_ka_config() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}"; }
_ka_keys_toml() { printf '%s/grove-keys/keys.toml' "$(_ka_config)"; }
_ka_aerospace_toml() { printf '%s/aerospace/aerospace.toml' "$(_ka_config)"; }
_ka_bin() { printf '%s/Contents/MacOS/GroveKeys' "$(_ka_app)"; }
_ka_domain() { printf 'gui/%s' "$(id -u)"; }

# _ka_aerospace: the aerospace CLI, found as 98-aerospace finds it.
_ka_aerospace() {
  if [ -n "${GROVE_AEROSPACE:-}" ]; then printf '%s' "$GROVE_AEROSPACE"; return 0; fi
  command -v aerospace 2>/dev/null && return 0
  printf '%s/aerospace' "$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")"
}

# _ka_aerospace_running: the same test as 98-aerospace's _as_running.
_ka_aerospace_running() {
  "${GROVE_PS:-ps}" -axo pid=,comm= 2>/dev/null | grep -q '/AeroSpace\.app/Contents/MacOS/AeroSpace$'
}

_ka_src() {
  if [ -n "${GROVE_APP_SRC:-}" ]; then printf '%s' "$GROVE_APP_SRC"; return 0; fi
  printf '%s/../grove-keys/app' "$GROVE_ROOT"
}

# The package depends on grove-themes/app through the tracked symlink
# grove-keys/deps/grove-themes; the hash reads the real tree.
_ka_themes_src() {
  if [ -n "${GROVE_THEMES_SRC:-}" ]; then printf '%s' "$GROVE_THEMES_SRC"; return 0; fi
  printf '%s/../grove-themes/app' "$GROVE_ROOT"
}

# _ka_tree_hash DIR: sorted tracked paths and contents under DIR. .build/ is
# untracked, so it never counts.
_ka_tree_hash() {
  (
    cd "$1" || exit 1
    git ls-files | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(shasum < "$f" | cut -d' ' -f1)" "$f"
    done
  )
}

# _ka_source_hash: one hash over the app's tracked files and its dependency's.
_ka_source_hash() {
  local a t
  a="$(_ka_tree_hash "$(_ka_src)")" || return 1
  t="$(_ka_tree_hash "$(_ka_themes_src)")" || return 1
  printf 'grove-keys/app\n%s\ngrove-themes/app\n%s\n' "$a" "$t" | shasum | cut -d' ' -f1
}

# _ka_agent_plist: the LaunchAgent grove writes. launchd's PATH is minimal and
# the app runs the grove-themes CLI as a child, so the plist sets one.
_ka_agent_plist() {
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_KA_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(_ka_app)/Contents/MacOS/GroveKeys</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
XML
}

# Signing. An ad hoc signature changes with every build, and macOS forgets
# Accessibility and Input Monitoring for a binary it no longer recognises. A
# certificate signature gives the designated requirement
#   identifier com.projectgrove.keys and certificate leaf = H"<cert hash>"
# which stays the same across rebuilds, so the permissions are granted once.

# _ka_identity_hash: the SHA-1 of a usable "Grove Code Signing" identity in
# the login keychain, empty when there's none. A self-signed certificate isn't
# trusted, so it never shows under find-identity -v; this reads the full list,
# allows the one error a self-signed certificate shows (CSSMERR_TP_NOT_TRUSTED)
# and skips rows that are expired, revoked or carry any other error.
_ka_identity_hash() {
  "$(_ka_security)" find-identity -p codesigning "$(_ka_keychain)" 2>/dev/null \
    | awk -v n="\"$_KA_IDENTITY\"" '
        $1 ~ /^[0-9]+\)$/ && index($0, n) {
          if ($0 ~ /EXPIRED|REVOKED/) next
          e = $0; gsub(/CSSMERR_TP_NOT_TRUSTED/, "", e)
          if (e ~ /CSSMERR_/) next
          print $2; exit
        }'
}

# _ka_tool_fail WHAT LOG [HINT]: the red line, the tool's last lines, a hint, all
# on stderr (it runs inside $(_ka_ensure_identity), whose stdout is the hash).
_ka_tool_fail() {
  grove_fail "$1 failed:"
  tail -n 15 "$2" >&2
  [ -z "${3:-}" ] || grove_note "$3" >&2
}

_KA_KEYCHAIN_HINT="unlock the login keychain and run grove install keys-app again"

# _ka_create_identity: a self-signed code-signing certificate (10 years) and
# its key, imported into the login keychain so that only /usr/bin/codesign may
# use the key without asking. It runs in a subshell whose trap deletes the
# temp folder (key, certificate, .p12) however it ends, interrupted included.
# openssl reads the .p12 passphrase from the environment, not the command line.
_ka_create_identity() (
  umask 077
  tmp="$(mktemp -d)" || exit 1
  trap 'rm -rf "$tmp"' EXIT
  trap 'rm -rf "$tmp"; exit 1' INT TERM
  log="$tmp/log"
  cat > "$tmp/cs.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $_KA_IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  if ! GROVE_KA_P12_PASS="$("$(_ka_openssl)" rand -hex 16 2>"$log")"; then
    _ka_tool_fail "openssl rand" "$log"; exit 1
  fi
  export GROVE_KA_P12_PASS
  if ! "$(_ka_openssl)" req -x509 -newkey rsa:2048 -nodes -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
      -days 3650 -config "$tmp/cs.cnf" >"$log" 2>&1; then
    _ka_tool_fail "openssl req" "$log"; exit 1
  fi
  if ! "$(_ka_openssl)" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" \
      -passout env:GROVE_KA_P12_PASS -name "$_KA_IDENTITY" >"$log" 2>&1; then
    _ka_tool_fail "openssl pkcs12" "$log"; exit 1
  fi
  if ! "$(_ka_security)" import "$tmp/id.p12" -k "$(_ka_keychain)" -P "$GROVE_KA_P12_PASS" \
      -T /usr/bin/codesign >"$log" 2>&1; then
    _ka_tool_fail "security import" "$log" "$_KA_KEYCHAIN_HINT"; exit 1
  fi
)

# _ka_ensure_identity: print the identity's hash, making it first if needed.
_ka_ensure_identity() {
  local hash
  hash="$(_ka_identity_hash)"
  if [ -z "$hash" ]; then
    _ka_create_identity && hash="$(_ka_identity_hash)"
  fi
  [ -n "$hash" ] || return 1
  printf '%s' "$hash"
}

# _ka_signed_by_identity: the installed app's signature names Grove Code Signing.
_ka_signed_by_identity() {
  "$(_ka_codesign)" -dvv "$(_ka_app)" 2>&1 | grep -qx "Authority=$_KA_IDENTITY"
}

_ka_loaded() { "$(_ka_launchctl)" print "$(_ka_domain)/$_KA_LABEL" >/dev/null 2>&1; }

# _ka_wait_gone: launchd can still hold the job for a moment after bootout
# returns, and a bootstrap then fails; wait up to about 2 s for it to go.
_ka_wait_gone() {
  local n=0
  while _ka_loaded && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}

# _ka_bootstrap: load the agent, trying once more after a pause.
_ka_bootstrap() {
  "$(_ka_launchctl)" bootstrap "$(_ka_domain)" "$(_ka_agent)" >/dev/null 2>&1 && return 0
  sleep 0.5
  "$(_ka_launchctl)" bootstrap "$(_ka_domain)" "$(_ka_agent)" >/dev/null 2>&1
}

# _ka_render_current: 0 when aerospace.toml equals a fresh render, 3 when it
# doesn't (or is missing), 1 (message shown) when keys.toml can't be rendered.
_ka_render_current() {
  local tmp out rc=0
  tmp="$(mktemp -d)" || return 1
  if ! out="$(GROVE_KEYS_RENDER_OUT="$tmp/aerospace.toml" "$(_ka_bin)" --render-aerospace 2>&1)"; then
    grove_fail "${out:-could not render aerospace.toml}"
    rm -rf "$tmp"
    return 1
  fi
  [ -f "$(_ka_aerospace_toml)" ] && cmp -s "$tmp/aerospace.toml" "$(_ka_aerospace_toml)" || rc=3
  rm -rf "$tmp"
  return "$rc"
}

# _ka_hyper_enabled: keys.toml's [hyper] enabled (true when unset).
_ka_hyper_enabled() {
  ! awk '/^\[/ { in_h = ($0 ~ /^\[hyper\]/) } in_h && /^enabled[ \t]*=[ \t]*false/ { f = 1 } END { exit !f }' "$(_ka_keys_toml)" 2>/dev/null
}

# _ka_state KEY: "true" or "false" from keys.json, empty when it's not there.
_ka_state() { plutil -extract "$1" raw "$GROVE_STATE/keys.json" 2>/dev/null; }

check() {
  local stamp rc n
  if ! command -v "$(_ka_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Keys needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  [ -x "$(_ka_app)/Contents/MacOS/GroveKeys" ] || return 3
  stamp="$(cat "$(_ka_stamp)" 2>/dev/null)" || return 3
  [ "$stamp" = "$(_ka_source_hash)" ] || return 3
  [ -n "$(_ka_identity_hash)" ] || return 3
  _ka_signed_by_identity || return 3
  [ -f "$(_ka_agent)" ] && [ "$(cat "$(_ka_agent)")" = "$(_ka_agent_plist)" ] || return 3
  _ka_loaded || return 3
  _ka_render_current
  rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  # The app reports what it has been allowed to do; until it has, wait.
  [ -f "$GROVE_STATE/keys.json" ] || return 3
  rc=0
  if [ "$(_ka_state accessibility)" != true ]; then
    grove_fail "Grove Keys needs Accessibility: System Settings › Privacy & Security"
    rc=1
  fi
  if [ "$(_ka_state input_monitoring)" != true ]; then
    grove_fail "Grove Keys needs Input Monitoring: System Settings › Privacy & Security"
    rc=1
  fi
  [ "$rc" -eq 0 ] || return 1
  if _ka_hyper_enabled; then
    n="$("$(_ka_hidutil)" property --get UserKeyMapping 2>/dev/null | grep -c HIDKeyboardModifierMappingSrc)"
    if [ "${n:-0}" -eq 0 ]; then
      grove_fail "Caps Lock isn't mapped to F18; restart Grove Keys from its menu bar icon, or run grove install keys-app"
      return 1
    fi
  fi
  return 0
}

# _ka_iconset PNG OUT.icns WORKDIR: sips the PNG to every size and iconutil it.
_ka_iconset() {
  local png="$1" out="$2" set="$3/AppIcon.iconset" n
  mkdir -p "$set" || return 1
  for n in 16 32 64 128 256 512 1024; do
    sips -z "$n" "$n" "$png" --out "$set/icon_${n}x${n}.png" >/dev/null || return 1
  done
  # The @2x names are the next size up: 16@2x is 32, and so on up to 512@2x.
  for n in 16 32 128 256 512; do
    cp "$set/icon_$((n * 2))x$((n * 2)).png" "$set/icon_${n}x${n}@2x.png" || return 1
  done
  # 64 and 1024 are only there as the @2x sources; an iconset doesn't name them.
  rm -f "$set/icon_64x64.png" "$set/icon_1024x1024.png"
  iconutil -c icns "$set" -o "$out" >/dev/null
}

# _ka_info_plist: the app bundle's Info.plist. The icon is Grove Themes' for now;
# grovekeys:// is how the Grove bar's key glyph opens the menu.
_ka_info_plist() {
  cat <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.projectgrove.keys</string>
  <key>CFBundleName</key><string>Grove Keys</string>
  <key>CFBundleDisplayName</key><string>Grove Keys</string>
  <key>CFBundleExecutable</key><string>GroveKeys</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.projectgrove.keys</string>
      <key>CFBundleURLSchemes</key><array><string>grovekeys</string></array>
    </dict>
  </array>
</dict>
</plist>
XML
}

# _ka_open_panes: open the Privacy pane for each permission keys.json says is
# missing (nothing when the app hasn't reported yet).
_ka_open_panes() {
  local base='x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_'
  [ "$(_ka_state accessibility)" = false ] && open "${base}Accessibility" >/dev/null 2>&1
  [ "$(_ka_state input_monitoring)" = false ] && open "${base}ListenEvent" >/dev/null 2>&1
  return 0
}

apply() {
  local src app tmp log stage rc=0 domain changed out identity
  src="$(_ka_src)"
  app="$(_ka_app)"
  domain="$(_ka_domain)"
  if ! command -v "$(_ka_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Keys needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  mkdir -p "$(_ka_apps)" "$(dirname "$(_ka_agent)")" "$GROVE_STATE" || return 1
  if ! identity="$(_ka_ensure_identity)"; then
    grove_fail "could not make the \"$_KA_IDENTITY\" certificate in the login keychain"
    return 1
  fi
  tmp="$(mktemp -d "$(_ka_apps)/.grove-keys.XXXXXX")" || return 1
  log="$tmp/build.log"

  if ! (cd "$src" && "$(_ka_swift)" build -c release) >"$log" 2>&1; then
    grove_fail "swift build failed:"
    tail -n 15 "$log" >&2
    rm -rf "$tmp"
    return 1
  fi

  stage="$tmp/Grove Keys.app"
  mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources" || rc=1
  if [ "$rc" -eq 0 ]; then
    cp "$src/.build/release/GroveKeys" "$stage/Contents/MacOS/GroveKeys" \
      && _ka_info_plist > "$stage/Contents/Info.plist" \
      && _ka_iconset "$(_ka_themes_src)/Resources/AppIcon.png" "$stage/Contents/Resources/AppIcon.icns" "$tmp" \
      || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    grove_fail "could not assemble Grove Keys.app"
    rm -rf "$tmp"
    return 1
  fi
  if ! "$(_ka_codesign)" --force --sign "$identity" "$stage" >"$tmp/sign.log" 2>&1; then
    _ka_tool_fail "codesign" "$tmp/sign.log" "$_KA_KEYCHAIN_HINT"
    rm -rf "$tmp"
    return 1
  fi

  # Signed: now replace the installed app and record what it was built from.
  rm -rf "$app"
  mv "$stage" "$app" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  _ka_source_hash > "$(_ka_stamp)" || return 1

  # aerospace.toml comes from keys.toml and the base; a bad keys.toml stops here.
  if ! out="$("$(_ka_bin)" --render-aerospace 2>&1)"; then
    grove_fail "${out:-could not render aerospace.toml}"
    return 1
  fi
  # A running AeroSpace keeps the config it loaded until told to reload (the
  # restarted app sees the render as current, so it would not change on its own).
  if _ka_aerospace_running && ! out="$("$(_ka_aerospace)" reload-config 2>&1)"; then
    grove_note "AeroSpace didn't take the new config: ${out:-aerospace reload-config failed}"
  fi

  # launchd keeps the definition it loaded, so a changed plist needs a bootout
  # and bootstrap; an unchanged one only needs the process restarted.
  changed=1
  [ -f "$(_ka_agent)" ] && [ "$(cat "$(_ka_agent)")" = "$(_ka_agent_plist)" ] && changed=0
  _ka_agent_plist > "$(_ka_agent)" || return 1
  if _ka_loaded && [ "$changed" -eq 0 ]; then
    "$(_ka_launchctl)" kickstart -k "$domain/$_KA_LABEL" >/dev/null 2>&1 || {
      grove_fail "could not restart Grove Keys"
      return 1
    }
  else
    if _ka_loaded; then
      "$(_ka_launchctl)" bootout "$domain/$_KA_LABEL" >/dev/null 2>&1
      _ka_wait_gone
    fi
    _ka_bootstrap || {
      grove_fail "could not start Grove Keys at login (launchctl bootstrap)"
      return 1
    }
  fi
  grove_note "Grove Keys is in the menu bar and starts at login."
  if [ "$(_ka_state accessibility)" = false ] || [ "$(_ka_state input_monitoring)" = false ]; then
    if [ "${GROVE_YES:-0}" = "1" ]; then
      grove_note "allow Grove Keys under Accessibility and Input Monitoring in System Settings › Privacy & Security"
    else
      _ka_open_panes
    fi
  fi
}
