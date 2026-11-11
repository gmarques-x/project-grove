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

if [ "$(osascript -e "output muted of (get volume settings)" 2>/dev/null)" = true ]; then
  "$SB" --set volume label=mute
else
  "$SB" --set volume label="$(sb_pct "${INFO:-}")"
fi
