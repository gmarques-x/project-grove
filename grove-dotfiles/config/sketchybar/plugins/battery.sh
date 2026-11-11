#!/bin/bash
# Grove bar · battery: the level and a charging mark; hidden without a battery.
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

read -r level state <<< "$(pmset -g batt 2>/dev/null | sb_battery)"
if [ -z "$level" ]; then
  "$SB" --set battery drawing=off
  exit 0
fi
if [ "$state" = charging ]; then color="$GREEN"
elif [ "$level" -lt 10 ]; then color="$RED"
elif [ "$level" -lt 20 ]; then color="$YELLOW"
else color="$FG"; fi
"$SB" --set battery drawing=on label="$level%" label.color="$color"
