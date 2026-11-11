#!/bin/bash
# Grove bar · battery: a bolt filled with the charge; hidden without a battery. A click opens its popup (battery_popup.sh).
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Hover: the pill under the pointer fills softly.
sb_hover && exit 0

# An icon alone: a bolt filled from the bottom with the charge, in tenths;
# red when it is under 20% and not charging.
read -r level state <<< "$(pmset -g batt 2>/dev/null | sb_battery)"
if [ -z "$level" ]; then
  "$SB" --set battery drawing=off
  exit 0
fi
step=$(((level + 5) / 10))
if [ "$state" != charging ] && [ "$level" -lt 20 ]; then icon="bolt-low-$step"; else icon="bolt-$step"; fi
"$SB" --set battery drawing=on icon.background.image="$(sb_icon "$icon")"
