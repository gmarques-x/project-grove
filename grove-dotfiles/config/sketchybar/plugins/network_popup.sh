#!/bin/bash
# Grove bar · the Wi-Fi icon's popup: how the Mac is online (net.name, net.ip, net.router, net.dns), the default interface's totals since boot (net.total) and the top five apps (net.app.1…5); nettop gets 2 s. The chart's rows are fed by net_sample.sh.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

iface="$(sb_timeout 2 route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
conn="$( { [ -n "$iface" ] && sb_timeout 2 ipconfig getsummary "$iface" 2>/dev/null; } | sb_conn "$iface")"
case "$conn" in
  wifi)
    # macOS gives the network's name only to apps allowed Location: Grove Keys
    # writes it to $GROVE_STATE/wifi-name when it may; without it, "Wi-Fi".
    name="$(head -1 "${GROVE_STATE:-$HOME/.local/state/grove}/wifi-name" 2>/dev/null)"
    name="${name:-Wi-Fi}" ;;
  eth) name="Ethernet" ;;
  vpn) name="VPN" ;;
  *) name="Offline" ;;
esac
args=(--set net.name label="$name")
# row NAME VALUE: shown with its value, hidden without one.
row() {
  if [ -n "$2" ]; then args+=(--set "net.$1" drawing=on label="$2"); else args+=(--set "net.$1" drawing=off); fi
}
ip=""; router=""
if [ -n "$iface" ]; then
  ip="$(sb_timeout 2 ipconfig getifaddr "$iface" 2>/dev/null)"
  router="$(sb_timeout 2 ipconfig getoption "$iface" router 2>/dev/null)"
fi
row ip "$ip"
row router "$router"
row dns "$( { sb_timeout 2 scutil --dns 2>/dev/null || true; } | sb_dns)"
total=""
if [ -n "$iface" ]; then
  read -r tin tout <<< "$(netstat -ibn 2>/dev/null | sb_iface_bytes "$iface")"
  [ -z "$tin" ] || total="↓ $(sb_bytes "$tin")  ↑ $(sb_bytes "$tout")"
fi
if [ -n "$total" ]; then args+=(--set net.total drawing=on label="$total"); else args+=(--set net.total drawing=off); fi
# -n: no name lookups. With them nettop takes 5 s here, over its limit; without, 10 ms.
apps="$(sb_timeout 2 nettop -P -L 1 -x -n -J bytes_in,bytes_out 2>/dev/null | sb_top_apps 5)"
i=0
if [ -z "$apps" ]; then
  i=1
  args+=(--set net.app.1 drawing=on label="top apps unavailable")
else
  while IFS=$'\t' read -r name ain aout; do
    i=$((i + 1))
    args+=(--set "net.app.$i" drawing=on label="$name  ↓ $(sb_bytes "$ain")  ↑ $(sb_bytes "$aout")")
  done <<< "$apps"
fi
for ((j = i + 1; j <= 5; j++)); do args+=(--set "net.app.$j" drawing=off); done
"$SB" "${args[@]}"
