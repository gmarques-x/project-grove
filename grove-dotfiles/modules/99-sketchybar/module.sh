# shellcheck shell=bash
# 99-sketchybar: the Grove top bar. SketchyBar comes from the felixkratz/formulae
# tap, which this module trusts and installs from itself (Homebrew refuses
# formulae from untrusted taps, so it can't sit in the Brewfile that
# 20-homebrew installs). Its config is config/sketchybar (05-config's link);
# grove-themes renders colors.sh. The menu bar is auto-hidden, and the bar's
# strip covers it. Spec: docs/specs/2026-11-11-sketchybar-design.md.
# Seams: GROVE_BREW, GROVE_SKETCHYBAR, GROVE_PS, GROVE_THEMES_CLI; defaults and
# killall from PATH.

about() { echo "The Grove top bar (SketchyBar)"; }

_SB_TAP=felixkratz/formulae
_SB_FORMULA=felixkratz/formulae/sketchybar

_sb_brew() { printf '%s' "${GROVE_BREW:-/opt/homebrew/bin/brew}"; }
_sb_config() { printf '%s/sketchybar' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# _sb_bin: the sketchybar command (GROVE_SKETCHYBAR, else next to brew).
_sb_bin() {
  local c="${GROVE_SKETCHYBAR:-$(dirname "$(_sb_brew)")/sketchybar}"
  [ -x "$c" ] || return 1
  printf '%s' "$c"
}

_sb_running() {
  "${GROVE_PS:-ps}" -axo pid=,comm= 2>/dev/null | awk '{ n = $2; sub(/.*\//, "", n); if (n == "sketchybar") f = 1 } END { exit !f }'
}

_sb_hidden() { [ "$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null)" = 1 ]; }

_sb_triggered() {
  grep -q 'aerospace_workspace_change' "${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml" 2>/dev/null
}

_sb_themes() {
  printf '%s' "${GROVE_THEMES_CLI:-$(cd "${GROVE_ROOT:?}/.." && pwd -P)/grove-themes/bin/grove-themes}"
}

check() {
  if [ ! -f "$(_sb_config)/sketchybarrc" ]; then
    grove_fail "no Grove bar config at $(_sb_config); run grove install config"
    return 1
  fi
  if ! _sb_triggered; then
    grove_fail "AeroSpace doesn't tell the bar about workspace changes; run grove install keys-app"
    return 1
  fi
  _sb_bin >/dev/null || return 3
  [ -f "$(_sb_config)/colors.sh" ] || return 3
  _sb_hidden || return 3
  _sb_running || return 3
  return 0
}

apply() {
  if ! _sb_bin >/dev/null; then
    if ! "$(_sb_brew)" trust "$_SB_TAP" >/dev/null 2>&1 || ! "$(_sb_brew)" install "$_SB_FORMULA" >/dev/null 2>&1; then
      grove_fail "could not install SketchyBar from $_SB_TAP"
      return 1
    fi
  fi
  if [ ! -f "$(_sb_config)/colors.sh" ]; then
    "$(_sb_themes)" render >/dev/null 2>&1 || { grove_fail "could not render the bar's colours (grove-themes render)"; return 1; }
  fi
  if ! _sb_hidden; then
    defaults write NSGlobalDomain _HIHideMenuBar -bool true || { grove_fail "could not auto-hide the menu bar"; return 1; }
    killall SystemUIServer >/dev/null 2>&1 || true
  fi
  if ! _sb_running; then
    "$(_sb_brew)" services start "$_SB_FORMULA" >/dev/null 2>&1 || { grove_fail "could not start SketchyBar"; return 1; }
  fi
}
