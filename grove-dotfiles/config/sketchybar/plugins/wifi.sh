#!/bin/bash
# Grove bar · the connection, an icon: Wi-Fi by signal, a cable or a tunnel through the default route, or off. A click opens its popup (network_popup.sh).
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

# An icon alone: the Wi-Fi fan with one to three arcs by signal, a plug on
# a cable, a shield on a tunnel, a struck-out fan when offline.
iface="$(sb_timeout 2 route -n get default 2>/dev/null | awk '/interface:/ { print $2 }')"
conn="$( { [ -n "$iface" ] && sb_timeout 2 ipconfig getsummary "$iface" 2>/dev/null; } | sb_conn "$iface")"
case "$conn" in
  wifi)
    # The signal in dBm from CoreWLAN (needs no Location permission).
    rssi="$(sb_timeout 2 osascript -l JavaScript -e 'ObjC.import("CoreWLAN"); var i = $.CWWiFiClient.sharedWiFiClient.interface; i.isNil() ? "" : String(i.rssiValue)' 2>/dev/null)"
    icon="wifi-$(sb_wifi_level "$rssi")" ;;
  eth) icon=eth ;;
  vpn) icon=vpn ;;
  *) icon=wifi-off ;;
esac
"$SB" --set wifi icon.background.image="$(sb_icon "$icon")"
