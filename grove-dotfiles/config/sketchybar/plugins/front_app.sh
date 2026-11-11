#!/bin/bash
# Grove bar · the front app's name (front_app_switched gives it in INFO).
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Hover: clickable items get a soft bg1 background under the pointer.
NAME="${NAME:-}"
case "${SENDER:-}" in
  mouse.entered) "$SB" --set "$NAME" background.drawing=on background.color="$BG1"; exit 0 ;;
  mouse.exited) "$SB" --set "$NAME" background.drawing=off; exit 0 ;;
esac

# front_app_switched gives the name in INFO; a reload or the first run doesn't.
name="${INFO:-$(lsappinfo info -only name "$(lsappinfo front 2>/dev/null)" 2>/dev/null | awk -F '"' 'NR == 1 { print $2 }')}"
"$SB" --set front_app label="${name:-$SB_NONE}"
