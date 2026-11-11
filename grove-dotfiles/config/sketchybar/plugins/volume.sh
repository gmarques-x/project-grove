#!/bin/bash
# Grove bar · volume: a speaker filled with the level (volume_change gives it in INFO), struck out on mute.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# An icon alone: the speaker and its waves filled from the left with the
# level, in tenths; struck out when muted.
if [ "$(sb_timeout 2 osascript -e "output muted of (get volume settings)" 2>/dev/null)" = true ]; then
  icon=vol-mute
else
  # volume_change gives the level in INFO; a reload or the first run doesn't.
  level="${INFO:-$(sb_timeout 2 osascript -e "output volume of (get volume settings)" 2>/dev/null)}"
  icon="vol-$(sb_vol_level "$level")"
fi
"$SB" --set volume icon.background.image="$(sb_icon "$icon")"
