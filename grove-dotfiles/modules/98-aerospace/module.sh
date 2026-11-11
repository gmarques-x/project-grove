# shellcheck shell=bash
# 98-aerospace: AeroSpace tiles the desktop and starts JankyBorders (its config
# is aerospace.toml, which Grove Keys renders from keys.toml and config/aerospace/
# aerospace.base.toml; module 96-keys-app writes it).
# Homebrew installs both. Seams: GROVE_AEROSPACE and GROVE_BORDERS (command
# paths), GROVE_PS (default ps), GROVE_POLL_SECONDS, GROVE_START_SECONDS; defaults and open from PATH.

about() { echo "AeroSpace tiles the desktop"; }

_AS_PANE='x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility'
_AS_HINT="allow AeroSpace under Accessibility (Device Control and Data Access on newer macOS) in System Settings > Privacy & Security"

# _as_cmd NAME OVERRIDE: the command's path: OVERRIDE when set, else on PATH,
# else next to brew (Homebrew may not be on PATH yet in a fresh install run).
_as_cmd() {
  local c
  if [ -n "$2" ]; then
    [ -x "$2" ] || return 1
    printf '%s' "$2"; return 0
  fi
  if c="$(command -v "$1" 2>/dev/null)"; then printf '%s' "$c"; return 0; fi
  c="$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")/$1"
  [ -x "$c" ] || return 1
  printf '%s' "$c"
}

_as_aerospace() { _as_cmd aerospace "${GROVE_AEROSPACE:-}"; }
_as_borders() { _as_cmd borders "${GROVE_BORDERS:-}"; }

# _as_spans: 0 when "Displays have separate Spaces" is off.
_as_spans() { [ "$(defaults read com.apple.spaces spans-displays 2>/dev/null)" = 1 ]; }

_as_running() {
  "${GROVE_PS:-ps}" -axo pid=,comm= 2>/dev/null | grep -q '/AeroSpace\.app/Contents/MacOS/AeroSpace$'
}

# _as_allowed: the CLI reaches the server only once Accessibility is granted.
_as_allowed() { "$(_as_aerospace)" list-workspaces --focused >/dev/null 2>&1; }

check() {
  if [ ! -f "${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml" ]; then
    grove_fail "AeroSpace has no config yet; run grove install keys-app"
    return 1
  fi
  _as_aerospace >/dev/null || return 3
  _as_borders >/dev/null || return 3
  _as_spans || return 3
  _as_running || return 3
  _as_allowed || return 4
  return 0
}

apply() {
  local n
  if ! _as_aerospace >/dev/null || ! _as_borders >/dev/null; then
    grove_fail "AeroSpace or JankyBorders is missing; run grove install homebrew"
    return 1
  fi
  if ! _as_spans; then
    defaults write com.apple.spaces spans-displays -bool true || {
      grove_fail "could not turn off \"Displays have separate Spaces\""
      return 1
    }
    grove_note "log out once to finish the Spaces change"
  fi
  if ! _as_running; then
    open -a AeroSpace || { grove_fail "could not start AeroSpace"; return 1; }
    # The server takes a moment to answer after it starts.
    n=0
    until _as_allowed || [ "$n" -ge 10 ]; do
      sleep "${GROVE_START_SECONDS:-1}"
      n=$((n + 1))
    done
  fi
  if ! _as_allowed; then
    # Unattended (grove install --yes): say what's needed and move on; the
    # next grove check reports needs you.
    if [ "${GROVE_YES:-0}" = "1" ]; then
      grove_note "$_AS_HINT, then run grove install aerospace"
      return 0
    fi
    open "$_AS_PANE" >/dev/null 2>&1 || true
    grove_info "$_AS_HINT"
    until _as_allowed; do
      sleep "${GROVE_POLL_SECONDS:-5}"
    done
  fi
}
