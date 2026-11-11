#!/bin/bash
# Grove bar · the Grove Keys glyph: grey when it's fine, orange when $GROVE_STATE/keys.json says something is off.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

state="${GROVE_STATE:-$HOME/.local/state/grove}/keys.json"
if [ -r "$state" ] && grep -q false "$state"; then
  "$SB" --set keys icon.color="$ORANGE"
else
  "$SB" --set keys icon.color="$GREY2"
fi
