# shellcheck shell=bash
# 95-vscode: VS Code's settings are a link to config/vscode/settings.json, and
# sainnhe's Everforest and Grove Icons (config/vscode/grove-icons, at its
# package.json version) are installed. Homebrew installs VS Code itself.
# Tests point GROVE_CODE at a fake code and GROVE_VSCODE_USER at a temp folder.

about() { echo "VS Code: Everforest, Grove Icons, JetBrains Mono"; }

_VSC_EVERFOREST=sainnhe.everforest
_VSC_ICONS_ID=grove.grove-icons

# _vsc_code: the code command. Homebrew may not be on PATH yet in a fresh
# install run, so also look next to brew.
_vsc_code() {
  local c
  if [ -n "${GROVE_CODE:-}" ]; then printf '%s' "$GROVE_CODE"; return 0; fi
  if c="$(command -v code 2>/dev/null)"; then printf '%s' "$c"; return 0; fi
  c="$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")/code"
  [ -x "$c" ] || return 1
  printf '%s' "$c"
}

_vsc_settings() {
  printf '%s/settings.json' "${GROVE_VSCODE_USER:-$HOME/Library/Application Support/Code/User}"
}

_vsc_icons() { printf '%s/vscode/grove-icons' "$GROVE_CONFIG"; }

_vsc_icons_version() { plutil -extract version raw -o - "$(_vsc_icons)/package.json"; }

# _vsc_installed WANT: 0 when the extension list has WANT, ignoring case. WANT
# is id@version, or a bare id for any version.
_vsc_installed() {
  local want line
  want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  while IFS= read -r line; do
    line="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"
    case "$want" in
      *@*) [ "$line" = "$want" ] && return 0 ;;
      *) [ "${line%%@*}" = "$want" ] && return 0 ;;
    esac
  done <<EOF
$("$(_vsc_code)" --list-extensions --show-versions 2>/dev/null)
EOF
  return 1
}

check() {
  if ! _vsc_code >/dev/null; then
    grove_fail "VS Code's code command is missing; run grove install homebrew"
    return 1
  fi
  grove_link_check "$GROVE_CONFIG/vscode/settings.json" "$(_vsc_settings)" || return 3
  _vsc_installed "$_VSC_EVERFOREST" || return 3
  _vsc_installed "$_VSC_ICONS_ID@$(_vsc_icons_version)" || return 3
  return 0
}
