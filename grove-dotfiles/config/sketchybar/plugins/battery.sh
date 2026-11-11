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

level="$(pmset -g batt 2>/dev/null | sb_battery)"
if [ -z "$level" ]; then "$SB" --set battery drawing=off; else "$SB" --set battery drawing=on label="$level"; fi
