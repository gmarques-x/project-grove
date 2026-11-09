# shellcheck shell=bash
# 30-fonts: the fonts grove-fonts installs.

about() { echo "fonts from grove-fonts"; }

_fonts_script() { echo "$GROVE_ROOT/../grove-fonts/install-fonts.sh"; }

check() {
  local script rc
  script="$(_fonts_script)"
  [ -f "$script" ] || { grove_fail "install-fonts.sh not found at $script"; return 1; }
  "$script" --check --quiet; rc=$?
  case "$rc" in
    0) return 0 ;;
    3) return 3 ;;
    *) return 1 ;;
  esac
}

apply() {
  local script
  script="$(_fonts_script)"
  [ -f "$script" ] || { grove_fail "install-fonts.sh not found at $script"; return 1; }
  "$script" --quiet
}
