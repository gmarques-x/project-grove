#!/bin/bash
# Grove bar · Bluetooth, an icon beside Wi-Fi: off, on, or on with a device connected, as Grove Keys reads it (bluetooth_change). A click opens the Wi-Fi panel, Bluetooth under it (Grove Keys).
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

# An icon alone: the rune, struck out when off. Grove Keys reads Bluetooth
# (system_profiler is too slow for the bar) and writes the word to a file,
# then sends bluetooth_change; this only reads that file.
"$SB" --set bt icon.background.image="$(sb_icon "$(sb_bluetooth)")"
