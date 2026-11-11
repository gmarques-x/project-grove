#!/bin/bash
# Grove bar · cpu and mem: used percentages.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

cpu="$( { top -l 1 -n 0 2>/dev/null || true; } | sb_cpu)"
mem="$( { vm_stat 2>/dev/null || true; } | sb_mem "$(sysctl -n hw.memsize 2>/dev/null)")"
"$SB" --set cpu label="$(sb_pct "$cpu")" --set mem label="$(sb_pct "$mem")"
