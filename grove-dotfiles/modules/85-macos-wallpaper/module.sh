# shellcheck shell=bash
# 85-macos-wallpaper: every screen shows grove-wallpapers/wallpaper-project-grove-dark-medium.png,
# read straight from the repo (the installer clones all of project-grove).
# macOS sets only the Space each screen is showing; other Spaces are a manual step.
# Tests point GROVE_WALLPAPER_DIR elsewhere and fake osascript.

about() { echo "Desktop wallpaper"; }

_wp_file() {
  local dir="${GROVE_WALLPAPER_DIR:-$(cd "$GROVE_ROOT/.." && pwd -P)/grove-wallpapers}"
  printf '%s/wallpaper-project-grove-dark-medium.png' "$dir"
}

# _wp_pictures: each screen's picture path, one per line.
_wp_pictures() {
  osascript - 2>/dev/null <<'EOF'
tell application "System Events"
  set out to ""
  repeat with d in every desktop
    set out to out & (picture of d) & linefeed
  end repeat
  return out
end tell
EOF
}

_wp_missing() {
  [ -r "$(_wp_file)" ] && return 1
  grove_fail "wallpaper not found: $(_wp_file)"
  return 0
}

check() {
  local want pics
  _wp_missing && return 1
  want="$(_wp_file)"
  pics="$(_wp_pictures)" || return 4
  [ -n "$pics" ] || return 3
  [ "$(printf '%s\n' "$pics" | sed '/^$/d' | sort -u)" = "$want" ] || return 3
  return 0
}

apply() {
  _wp_missing && return 1
  if ! osascript - "$(_wp_file)" >/dev/null 2>&1 <<'EOF'
on run argv
  tell application "System Events" to set picture of every desktop to POSIX file (item 1 of argv)
end run
EOF
  then
    grove_you "allow your terminal to control System Events (System Settings > Privacy & Security > Automation), then run grove install again"
    return 4
  fi
  grove_note "Wallpaper set on every screen. Other Spaces keep theirs: set them by hand in System Settings > Wallpaper."
}
