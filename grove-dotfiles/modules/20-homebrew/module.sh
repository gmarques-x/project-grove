# shellcheck shell=bash
# 20-homebrew: Homebrew itself, then everything in the Brewfile.

about() { echo "Homebrew and the Brewfile"; }

_brew() { echo "${GROVE_BREW:-/opt/homebrew/bin/brew}"; }

check() {
  local brew
  brew="$(_brew)"
  [ -x "$brew" ] || return 4
  "$brew" bundle check --file "$GROVE_ROOT/Brewfile" >/dev/null 2>&1 && return 0
  return 3
}

apply() {
  local brew
  brew="$(_brew)"
  if [ ! -x "$brew" ]; then
    # shellcheck disable=SC2016
    grove_info 'installing Homebrew: /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      || { grove_fail "the Homebrew installer failed"; return 1; }
    [ -x "$brew" ] || { grove_fail "Homebrew is still missing at $brew"; return 1; }
  fi
  PATH="$(dirname "$brew"):$PATH"
  export PATH
  "$brew" bundle install --no-upgrade --file "$GROVE_ROOT/Brewfile"
}
