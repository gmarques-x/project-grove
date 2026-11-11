#!/bin/bash
# Grove bar · volume: the level (volume_change gives it in INFO), or mute.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Hover: clickable items get a soft fill under the pointer.
NAME="${NAME:-}"
case "${SENDER:-}" in
  mouse.entered) "$SB" --set "$NAME" background.drawing=on background.color="${HOVER_FILL:-$BG1}"; exit 0 ;;
  mouse.exited) "$SB" --set "$NAME" background.drawing=off; exit 0 ;;
esac

if [ "$(sb_timeout 2 osascript -e "output muted of (get volume settings)" 2>/dev/null)" = true ]; then
  "$SB" --set volume label=mute
else
  # volume_change gives the level in INFO; a reload or the first run doesn't.
  level="${INFO:-$(sb_timeout 2 osascript -e "output volume of (get volume settings)" 2>/dev/null)}"
  "$SB" --set volume label="$(sb_pct "$level")"
fi
