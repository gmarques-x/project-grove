#!/bin/bash
# Grove bar · the grove-lab VPN, a shield: on, on the way (connecting or disconnecting), or off, as scutil reads the macOS VPN configuration. A click opens its panel (Grove Keys).
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

# An icon alone: grey when off or not set up (scutil exits 1, "No service" on
# standard error, nothing here), yellow on the way, purple when connected.
# The bar only reads the state; Grove Keys' dropdown starts and stops the
# tunnel.
status="$(sb_timeout 2 scutil --nc status "grove-lab" 2>/dev/null)"
"$SB" --set vpn.lab icon.background.image="$(sb_icon "$(printf '%s\n' "$status" | sb_vpn_icon)")"
