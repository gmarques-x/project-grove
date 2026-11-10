# shellcheck shell=bash
# 97-themes-app: Grove Themes, the menu bar app in grove-themes/app, is built
# with swift, assembled into ~/Applications/Grove Themes.app (ad hoc signed)
# and started at login by a LaunchAgent. A stamp holds a hash of the tracked
# source files, so check notices when the app is out of date.
# Tests point GROVE_SWIFT, GROVE_LAUNCHCTL, GROVE_CODESIGN, GROVE_APPS_DIR and
# GROVE_AGENTS_DIR at fakes and temp folders (GROVE_APP_SRC at a copy of the
# source, because swift builds into it).

about() { echo "Grove Themes in the menu bar"; }

_TA_LABEL=com.projectgrove.themes

_ta_swift() { printf '%s' "${GROVE_SWIFT:-swift}"; }
_ta_launchctl() { printf '%s' "${GROVE_LAUNCHCTL:-launchctl}"; }
_ta_codesign() { printf '%s' "${GROVE_CODESIGN:-codesign}"; }
_ta_apps() { printf '%s' "${GROVE_APPS_DIR:-$HOME/Applications}"; }
_ta_app() { printf '%s/Grove Themes.app' "$(_ta_apps)"; }
_ta_agent() { printf '%s/%s.plist' "${GROVE_AGENTS_DIR:-$HOME/Library/LaunchAgents}" "$_TA_LABEL"; }
_ta_stamp() { printf '%s/themes-app.stamp' "$GROVE_STATE"; }
_ta_domain() { printf 'gui/%s' "$(id -u)"; }

_ta_src() {
  if [ -n "${GROVE_APP_SRC:-}" ]; then printf '%s' "$GROVE_APP_SRC"; return 0; fi
  printf '%s/../grove-themes/app' "$GROVE_ROOT"
}

# _ta_source_hash: a hash over the tracked files under the app source (sorted
# paths and contents). .build/ is untracked, so it never counts.
_ta_source_hash() {
  (
    cd "$(_ta_src)" || exit 1
    git ls-files | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s  %s\n' "$(shasum < "$f" | cut -d' ' -f1)" "$f"
    done | shasum | cut -d' ' -f1
  )
}

# _ta_agent_plist: the LaunchAgent grove writes. launchd's PATH is minimal and
# the app runs the grove-themes CLI as a child, so the plist sets one.
_ta_agent_plist() {
  cat <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_TA_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(_ta_app)/Contents/MacOS/GroveThemes</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
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

_ta_loaded() { "$(_ta_launchctl)" print "$(_ta_domain)/$_TA_LABEL" >/dev/null 2>&1; }

# _ta_wait_gone: launchd can still hold the job for a moment after bootout
# returns, and a bootstrap then fails; wait up to about 2 s for it to go.
_ta_wait_gone() {
  local n=0
  while _ta_loaded && [ "$n" -lt 20 ]; do
    sleep 0.1
    n=$((n + 1))
  done
}

# _ta_bootstrap: load the agent, trying once more after a pause.
_ta_bootstrap() {
  "$(_ta_launchctl)" bootstrap "$(_ta_domain)" "$(_ta_agent)" >/dev/null 2>&1 && return 0
  sleep 0.5
  "$(_ta_launchctl)" bootstrap "$(_ta_domain)" "$(_ta_agent)" >/dev/null 2>&1
}

check() {
  local stamp
  if ! command -v "$(_ta_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Themes needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  [ -x "$(_ta_app)/Contents/MacOS/GroveThemes" ] || return 3
  stamp="$(cat "$(_ta_stamp)" 2>/dev/null)" || return 3
  [ "$stamp" = "$(_ta_source_hash)" ] || return 3
  [ -f "$(_ta_agent)" ] && [ "$(cat "$(_ta_agent)")" = "$(_ta_agent_plist)" ] || return 3
  _ta_loaded || return 3
  return 0
}

# _ta_iconset PNG OUT.icns WORKDIR: sips the PNG to every size and iconutil it.
_ta_iconset() {
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

apply() {
  local src app tmp log stage rc=0 domain changed
  src="$(_ta_src)"
  app="$(_ta_app)"
  domain="$(_ta_domain)"
  if ! command -v "$(_ta_swift)" >/dev/null 2>&1; then
    grove_fail "Grove Themes needs the Xcode command line tools (swift); run grove install xcode-tools"
    return 1
  fi
  mkdir -p "$(_ta_apps)" "$(dirname "$(_ta_agent)")" "$GROVE_STATE" || return 1
  tmp="$(mktemp -d "$(_ta_apps)/.grove-themes.XXXXXX")" || return 1
  log="$tmp/build.log"

  if ! (cd "$src" && "$(_ta_swift)" build -c release) >"$log" 2>&1; then
    grove_fail "swift build failed:"
    tail -n 15 "$log" >&2
    rm -rf "$tmp"
    return 1
  fi

  stage="$tmp/Grove Themes.app"
  mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources" || rc=1
  if [ "$rc" -eq 0 ]; then
    cp "$src/.build/release/GroveThemes" "$stage/Contents/MacOS/GroveThemes" \
      && cp "$src/Resources/Info.plist" "$stage/Contents/Info.plist" \
      && _ta_iconset "$src/Resources/AppIcon.png" "$stage/Contents/Resources/AppIcon.icns" "$tmp" \
      && "$(_ta_codesign)" --force --sign - "$stage" >/dev/null 2>&1 || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    grove_fail "could not assemble or sign Grove Themes.app"
    rm -rf "$tmp"
    return 1
  fi

  # Signed: now replace the installed app and record what it was built from.
  rm -rf "$app"
  mv "$stage" "$app" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  _ta_source_hash > "$(_ta_stamp)" || return 1

  # launchd keeps the definition it loaded, so a changed plist needs a bootout
  # and bootstrap; an unchanged one only needs the process restarted.
  changed=1
  [ -f "$(_ta_agent)" ] && [ "$(cat "$(_ta_agent)")" = "$(_ta_agent_plist)" ] && changed=0
  _ta_agent_plist > "$(_ta_agent)" || return 1
  if _ta_loaded && [ "$changed" -eq 0 ]; then
    "$(_ta_launchctl)" kickstart -k "$domain/$_TA_LABEL" >/dev/null 2>&1 || {
      grove_fail "could not restart Grove Themes"
      return 1
    }
  else
    if _ta_loaded; then
      "$(_ta_launchctl)" bootout "$domain/$_TA_LABEL" >/dev/null 2>&1
      _ta_wait_gone
    fi
    _ta_bootstrap || {
      grove_fail "could not start Grove Themes at login (launchctl bootstrap)"
      return 1
    }
  fi
  grove_note "Grove Themes is in the menu bar and starts at login."
}
