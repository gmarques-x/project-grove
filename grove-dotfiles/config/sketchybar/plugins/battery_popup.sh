#!/bin/bash
# Grove bar · the battery popup's rows (batt.*): the charge and its state, the time macOS estimates, the power source, the watts in or out, health and cycles, the measured capacity, the temperature where the Mac tells it, Low Power Mode. plugins/popup.sh runs it before showing the popup.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

IFS='|' read -r level state time source <<< "$(pmset -g batt 2>/dev/null | sb_batt_status)"
# No battery: the item is hidden, nothing to fill.
[ -n "$level" ] || exit 0
reg="$(sb_timeout 2 ioreg -rn AppleSmartBattery 2>/dev/null)"

args=(--set batt.charge label="$level% · $state")
# row NAME VALUE: shown with its value, hidden without one.
row() {
  if [ -n "$2" ]; then args+=(--set "batt.$1" drawing=on label="$2"); else args+=(--set "batt.$1" drawing=off); fi
}
case "$state" in
  charging) row time "${time:+$time to full}" ;;
  "on battery") row time "${time:+$time left}" ;;
  *) row time "" ;;
esac
if [ "$source" = ac ]; then
  adapter="$(sb_ioreg Name <<< "$reg")"
  watts="$(sb_ioreg Watts <<< "$reg")"
  row source "${adapter:-Power adapter}${watts:+ · $watts W}"
else
  row source "Battery"
fi
# The watts into the battery or out of it, then what the whole Mac draws.
power="$(sb_batt_power <<< "$reg")"
case "$power" in
  '') flow="" ;;
  -0.0 | 0.0) flow="0.0 W" ;;
  -*) flow="${power#-} W discharging" ;;
  *) flow="$power W charging" ;;
esac
load="$(sb_ioreg SystemLoad <<< "$reg")"
[ -z "$load" ] || [ "$load" = 0 ] || flow="${flow:+$flow · }Mac $(sb_watts "$load") W"
row power "$flow"
# Health as System Settings has it (its figure isn't in ioreg on Apple
# silicon), or else the measured capacity over the design's.
health="$(sb_timeout 2 system_profiler SPPowerDataType 2>/dev/null | sb_batt_health)"
max="$(sb_ioreg AppleRawMaxCapacity <<< "$reg")"
design="$(sb_ioreg DesignCapacity <<< "$reg")"
case "$max$design" in *[!0-9]*) max=""; design="" ;; esac
[ -n "$max" ] && [ -n "$design" ] && [ "$design" -gt 0 ] || { max=""; design=""; }
[ -n "$health" ] || health="${max:+$((max * 100 / design))%}"
cycles="$(sb_ioreg CycleCount <<< "$reg")"
row health "$health${health:+${cycles:+ · }}${cycles:+$cycles cycles}"
row full "${max:+$max of $design mAh}"
# Hundredths of a degree, on the Macs that publish it.
temp="$(sb_ioreg Temperature <<< "$reg")"
case "$temp" in '' | *[!0-9]*) row temp "" ;; *) row temp "$((temp / 100)).$((temp % 100 / 10)) °C" ;; esac
mode="$(pmset -g 2>/dev/null | sb_lowpower)"
row mode "${mode:+Low Power $mode}"
"$SB" "${args[@]}"
