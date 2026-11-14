# shellcheck shell=bash
# 93-claude-mod: the grove mod for Claude Code (the Agents pane in the grove-lab
# MOTD look, the status line, colors that follow Grove Themes). config/grove-claude
# is a local marketplace named "grove"; grove@grove is installed from it, and
# Claude Code reads the plugin straight from config/grove-claude/grove.
# The claude commands write ~/.claude/settings.json; this module never does.
# Claude Code is a native install (~/.local/bin), not Homebrew's.
# Tests point GROVE_CLAUDE_BIN at a fake claude.

about() { echo "Claude Code: the grove mod (Agents pane, Grove look)"; }

_CM_PLUGIN=grove@grove

# _cm_claude: the claude command, or 1 when Claude Code isn't installed.
_cm_claude() {
  local c
  if [ -n "${GROVE_CLAUDE_BIN:-}" ]; then
    [ -x "$GROVE_CLAUDE_BIN" ] || return 1
    printf '%s' "$GROVE_CLAUDE_BIN"; return 0
  fi
  if c="$(command -v claude 2>/dev/null)"; then printf '%s' "$c"; return 0; fi
  c="$HOME/.local/bin/claude"
  [ -x "$c" ] || return 1
  printf '%s' "$c"
}

# _cm_market: the marketplace folder, with no links in its path.
_cm_market() { (cd "$GROVE_CONFIG/grove-claude" 2>/dev/null && pwd -P); }

# _cm_market_path CLAUDE: the folder the "grove" marketplace points at, or nothing.
_cm_market_path() {
  "$1" plugin marketplace list --json 2>/dev/null \
    | jq -r '.[] | select(.name == "grove") | .path // .installLocation // empty' 2>/dev/null
}

# _cm_plugin_state CLAUDE: "<enabled> <readFromFolder>" for grove@grove, or nothing.
_cm_plugin_state() {
  "$1" plugin list --json 2>/dev/null \
    | jq -r --arg id "$_CM_PLUGIN" '.[] | select(.id == $id) | "\(.enabled) \(.readFromFolder // "")"' 2>/dev/null
}

_cm_install_hint() {
  grove_note "Claude Code isn't installed: install it (https://claude.com/claude-code), then run grove install claude-mod"
}

check() {
  local claude want
  claude="$(_cm_claude)" || return 4
  want="$(_cm_market)" || { grove_fail "config/grove-claude is missing"; return 1; }
  [ "$(_cm_market_path "$claude")" = "$want" ] || return 3
  [ "$(_cm_plugin_state "$claude")" = "true $want/grove" ] || return 3
  return 0
}

apply() {
  local claude want have state
  claude="$(_cm_claude)" || { _cm_install_hint; return 1; }
  want="$(_cm_market)" || { grove_fail "config/grove-claude is missing"; return 1; }

  have="$(_cm_market_path "$claude")"
  if [ -n "$have" ] && [ "$have" != "$want" ]; then
    grove_fail "a Claude Code marketplace named grove already points at $have; remove it with: claude plugin marketplace remove grove"
    return 1
  fi
  if [ -z "$have" ]; then
    "$claude" plugin marketplace add "$want" >/dev/null || { grove_fail "claude could not add the grove marketplace"; return 1; }
  fi

  state="$(_cm_plugin_state "$claude")"
  case "$state" in
    "") "$claude" plugin install "$_CM_PLUGIN" --scope user >/dev/null \
          || { grove_fail "claude could not install $_CM_PLUGIN"; return 1; } ;;
    false\ *) "$claude" plugin enable "$_CM_PLUGIN" >/dev/null \
          || { grove_fail "claude could not enable $_CM_PLUGIN"; return 1; } ;;
  esac

  check || { grove_fail "$_CM_PLUGIN isn't running from $want/grove (claude plugin list shows where it is read from)"; return 1; }
}
