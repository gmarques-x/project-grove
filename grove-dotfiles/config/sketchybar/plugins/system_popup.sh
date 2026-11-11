#!/bin/bash
# Grove bar · the CPU and memory popup's rows (sys.*): load averages, each core's load by type, the busiest processes, memory used and its parts, swap and pressure, the largest processes, the uptime. plugins/popup.sh runs it before showing the popup, plugins/cpu.sh every 4 s while it is open; the charts and the user · system row are cpu.sh's.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Each core's load takes a moment to measure (two readings 0.15 s apart): it
# runs beside the rest. cpu.sh passes what it measured in SB_CORES ("-": none).
if [ -z "${SB_CORES:-}" ]; then exec 3< <(sb_core_loads 0.15); fi

args=()
# row NAME VALUE: shown with its value, hidden without one.
row() {
  if [ -n "$2" ]; then args+=(--set "sys.$1" drawing=on label="$2"); else args+=(--set "sys.$1" drawing=off); fi
}
ctl="$(sysctl vm.loadavg kern.boottime vm.swapusage kern.memorystatus_vm_pressure_level hw.memsize hw.physicalcpu \
  hw.perflevel0.physicalcpu hw.perflevel0.name hw.perflevel1.physicalcpu hw.perflevel1.name 2>/dev/null)"
procs="$(ps -Aceo pcpu,rss,comm 2>/dev/null)"

row load "$(sb_loadavg <<< "$ctl" | sed 's/ /  /g')"

# list PREFIX ROWS: up to five muted rows, the rest hidden.
list() {
  local i=0 j line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    i=$((i + 1)); args+=(--set "$1.$i" drawing=on label="$line")
  done <<< "$2"
  for ((j = i + 1; j <= 5; j++)); do args+=(--set "$1.$j" drawing=off); done
}
list sys.proc "$(sb_top_cpu 5 <<< "$procs" | while IFS=$'\t' read -r name pct; do echo "$(sb_name "$name")  $pct%"; done)"

size="$(sb_sysctl hw.memsize <<< "$ctl")"
read -r used app wired comp <<< "$( { vm_stat 2>/dev/null || true; } | sb_mem_parts)"
if [ -n "$used" ] && [ -n "$size" ]; then
  row used "$(sb_gb "$used") of $(sb_gb "$size") GB"
  row parts "app $(sb_gb "$app") · wired $(sb_gb "$wired") · compressed $(sb_gb "$comp")"
else
  row used ""; row parts ""
fi
swap="$(sb_swap <<< "$ctl")"
pressure="$(sb_pressure <<< "$ctl")"
row swap "${swap:+$(sb_bytes "$swap")}${swap:+${pressure:+ · }}${pressure:+pressure $pressure}"
list sys.memproc "$(sb_top_mem 5 <<< "$procs" | while IFS=$'\t' read -r name bytes; do echo "$(sb_name "$name")  $(sb_bytes "$bytes")"; done)"

boot="$(sb_boot <<< "$ctl")"
row up "${boot:+$(sb_duration $((${SB_NOW:-$(date +%s)} - boot)))}"

# The cores last: their measure is the slowest thing here.
cores="${SB_CORES:-}"
if [ -z "$cores" ]; then read -r cores <&3 || true; exec 3<&-; fi
perf=""; eff=""; all=""
if [ -n "$cores" ] && [ "$cores" != - ]; then
  types="$(sb_timeout 2 ioreg -p IODeviceTree -r -k cluster-type -d 1 2>/dev/null | sb_core_types)"
  while IFS=$'\t' read -r kind loads; do
    case "$kind" in P) perf="$loads" ;; E) eff="$loads" ;; *) all="$loads" ;; esac
  done <<< "$(sb_core_rows "$types" <<< "$cores")"
fi
row perf "${perf// /  }"
row eff "${eff// /  }"
# Without each type's loads, how many cores of each there are (and all the
# cores' loads on one row, when only the types are missing).
if [ -z "$perf$eff" ]; then
  if [ -n "$all" ]; then row cores "${all// /  }"; else row cores "$(sb_cores <<< "$ctl")"; fi
else
  row cores ""
fi
"$SB" "${args[@]}"
