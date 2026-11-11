#!/bin/bash
# Grove bar · the network sampler (net.sample, not drawn): every two seconds the default route's down and up rates go to the Wi-Fi popup's chart (net.graph.down, net.graph.up).
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

state="${TMPDIR:-/tmp}/grove-sketchybar-net"
now="${SB_NOW:-$(date +%s)}"
iface="$(sb_timeout 2 route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
read -r nin nout <<< "$(netstat -ibn 2>/dev/null | sb_iface_bytes "$iface")"
read -r piface pin pout pt < "$state" 2>/dev/null || true
down="$SB_NONE"; up="$SB_NONE"; vdown=0; vup=0
if [ -n "$iface" ] && [ "$iface" = "$piface" ] && [ -n "$pt" ]; then
  secs=$((now - pt))
  down="$(sb_rate_delta "$pin" "$nin" "$secs")"
  up="$(sb_rate_delta "$pout" "$nout" "$secs")"
  case "$pin$pout$nin$nout" in
    *[!0-9]*) ;;
    *) if [ "$secs" -gt 0 ] && [ "$nin" -ge "$pin" ] && [ "$nout" -ge "$pout" ]; then
         vdown="$(sb_graph_value $(((nin - pin) / secs)))"
         vup="$(sb_graph_value $(((nout - pout) / secs)))"
       fi ;;
  esac
fi
[ -n "$iface" ] && [ -n "$nin" ] && echo "$iface $nin $nout $now" > "$state"
"$SB" --set net.graph.down label="$down" --set net.graph.up label="$up" \
  --push net.graph.down "$vdown" --push net.graph.up "$vup"
