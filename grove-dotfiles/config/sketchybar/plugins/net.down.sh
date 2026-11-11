#!/bin/bash
# Grove bar · net.down and net.up: the default interface's rate since the last sample (kept in $TMPDIR/grove-sketchybar-net); a first sample or an interface change shows —.
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

state="${TMPDIR:-/tmp}/grove-sketchybar-net"
now="${SB_NOW:-$(date +%s)}"
iface="$(sb_timeout 2 route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
read -r nin nout <<< "$(netstat -ibn 2>/dev/null | sb_iface_bytes "$iface")"
read -r piface pin pout pt < "$state" 2>/dev/null || true
down="$SB_NONE"; up="$SB_NONE"
if [ -n "$iface" ] && [ "$iface" = "$piface" ] && [ -n "$pt" ]; then
  down="$(sb_rate_delta "$pin" "$nin" "$((now - pt))")"
  up="$(sb_rate_delta "$pout" "$nout" "$((now - pt))")"
fi
[ -n "$iface" ] && [ -n "$nin" ] && echo "$iface $nin $nout $now" > "$state"
"$SB" --set net.down label="$down" --set net.up label="$up"
