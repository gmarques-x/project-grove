# shellcheck shell=bash
# 80-macos-finder: the recorded Finder settings (settings.txt), the empty
# favorite-tags list and the List view block (StandardViewSettings.plist).
# Tests redirect the domains with GROVE_FINDER_DOMAIN / GROVE_GLOBAL_DOMAIN.

about() { echo "Finder settings"; }

_finder_domain() { printf '%s' "${GROVE_FINDER_DOMAIN:-com.apple.finder}"; }
_finder_global() { printf '%s' "${GROVE_GLOBAL_DOMAIN:-NSGlobalDomain}"; }

# _finder_settings_tmp: print the path of a temp copy of settings.txt with the
# domains substituted. settings.txt itself stays literal.
_finder_settings_tmp() {
  local tmp f g
  f="$(_finder_domain)"
  g="$(_finder_global)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/grove-finder.XXXXXX")" || return 1
  if ! sed -e "s/^com\.apple\.finder\([[:space:]]\)/$f\1/" \
    -e "s/^NSGlobalDomain\([[:space:]]\)/$g\1/" \
    "$MODULE_DIR/settings.txt" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s' "$tmp"
}

# _finder_json KEY: the live value of KEY in the Finder domain as JSON (empty if unset).
_finder_json() {
  defaults export "$(_finder_domain)" - 2>/dev/null \
    | plutil -extract "$1" json -o - - 2>/dev/null
}

_finder_tags_ok() { [ "$(_finder_json FavoriteTagNames)" = '[""]' ]; }

_finder_view_ok() {
  local live want
  live="$(defaults export "$(_finder_domain)" - 2>/dev/null \
    | plutil -extract StandardViewSettings xml1 -o - - 2>/dev/null \
    | plutil -convert json -r -o - - 2>/dev/null)" || return 1
  want="$(plutil -convert json -r -o - "$MODULE_DIR/StandardViewSettings.plist")" || return 1
  [ -n "$live" ] && [ "$live" = "$want" ]
}

check() {
  local tmp rc=0
  tmp="$(_finder_settings_tmp)" || return 1
  grove_defaults_check "$tmp" || rc=$?
  rm -f "$tmp"
  [ "$rc" -eq 0 ] || return 3
  _finder_tags_ok || return 3
  _finder_view_ok || return 3
  return 0
}

# The sidebar is a manual step, so this always prints (not via grove_info).
_finder_checklist() {
  grove_you "Finder sidebar: set by hand in Finder > Settings > Sidebar"
  printf '  shown:  Applications, Home, Developer, Documents, Downloads, iCloud Drive, Macintosh HD\n'
  printf '  hidden: Recents, Shared, AirDrop, Desktop\n'
}

apply() {
  local tmp n changed=0
  tmp="$(_finder_settings_tmp)" || return 1
  n="$(grove_defaults_apply "$tmp")" || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  [ "$n" -eq 0 ] || changed=1
  if ! _finder_tags_ok; then
    defaults write "$(_finder_domain)" FavoriteTagNames -array "" || return 1
    changed=1
  fi
  if ! _finder_view_ok; then
    defaults write "$(_finder_domain)" StandardViewSettings "$(cat "$MODULE_DIR/StandardViewSettings.plist")" || return 1
    changed=1
  fi
  if [ "$changed" -eq 1 ]; then
    killall Finder 2>/dev/null || true
  fi
  _finder_checklist
}
