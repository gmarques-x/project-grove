#!/usr/bin/env bats
# The Grove palette and the colors every config uses.
# shellcheck disable=SC2016

load helpers

setup() { grove_test_setup; }

PALETTE_REL=theme/everforest-dark-medium

# palette_hexes: every #RRGGBB in the palette file, uppercased, one per line.
palette_hexes() {
  grep -v '^[[:space:]]*#' "$GROVE_ROOT/$PALETTE_REL" | grep -oE '#[0-9A-Fa-f]{6}' | tr '[:lower:]' '[:upper:]' | sort -u
}

# config_hexes FILE...: every #RRGGBB in the files that exist, uppercased.
config_hexes() {
  local f
  for f in "$@"; do [ -f "$f" ] && grep -oE '#[0-9A-Fa-f]{6}' "$f"; done | tr '[:lower:]' '[:upper:]' | sort -u
  return 0
}

# palette_value NAME: the hex for NAME in the palette.
palette_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\(#[0-9A-Fa-f]\{6\}\).*/\1/p" "$GROVE_ROOT/$PALETTE_REL" | head -1
}

@test "the palette has every upstream Dark Medium color" {
  local pair name want
  for pair in bg_dim=#232A2E bg0=#2D353B bg1=#343F44 bg2=#3D484D bg3=#475258 bg4=#4F585E \
              bg5=#56635F bg_visual=#543A48 bg_red=#514045 bg_yellow=#4D4C43 bg_green=#425047 \
              bg_blue=#3A515D bg_purple=#4A444E fg=#D3C6AA red=#E67E80 orange=#E69875 \
              yellow=#DBBC7F green=#A7C080 aqua=#83C092 blue=#7FBBB3 purple=#D699B6 \
              grey0=#7A8478 grey1=#859289 grey2=#9DA9A0; do
    name="${pair%%=*}"; want="${pair#*=}"
    [ "$(palette_value "$name")" = "$want" ] || { echo "$name: got '$(palette_value "$name")', want $want"; false; }
  done
}

@test "the palette's Grove additions are only the fill color" {
  run sed -n '/^# Grove additions/,$p' "$GROVE_ROOT/$PALETTE_REL"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -v '^[[:space:]]*#' | grep -v '^[[:space:]]*$')" = "fill = #596763" ]
}

@test "every config color comes from the palette" {
  local missing
  missing="$(comm -23 <(config_hexes "$GROVE_ROOT/config/ghostty/config" \
      "$GROVE_ROOT/config/starship.toml" "$GROVE_ROOT/config/starship-plain.toml" \
      "$GROVE_ROOT/config/macchina/themes/grove.toml" "$GROVE_ROOT/config/eza/theme.yml" \
      "$GROVE_ROOT"/config/zsh/conf.d/*.zsh) <(palette_hexes))"
  [ -z "$missing" ] || { echo "not in the palette: $missing"; false; }
}

# ghostty_value KEY: values of KEY in the Ghostty config, one per line.
ghostty_value() {
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$GROVE_ROOT/config/ghostty/config"
}

@test "ghostty config sets the spec's keys" {
  [ "$(ghostty_value font-family)" = "JetBrains Mono" ]
  [ "$(ghostty_value font-size)" = "14" ]
  [ "$(ghostty_value background)" = "#2D353B" ]
  [ "$(ghostty_value foreground)" = "#D3C6AA" ]
  [ "$(ghostty_value selection-background)" = "#543A48" ]
  [ "$(ghostty_value background-opacity)" = "1" ]
  [ "$(ghostty_value keybind)" = "global:ctrl+grave_accent=toggle_quick_terminal" ]
  [ "$(ghostty_value quick-terminal-position)" = "top" ]
  [ "$(ghostty_value macos-titlebar-style)" = "transparent" ]
  [ "$(ghostty_value window-padding-x)" = "24" ]
  [ "$(ghostty_value window-padding-y)" = "20" ]
  ghostty_value palette | grep -qx '0=#475258'
  ghostty_value palette | grep -qx '8=#859289'
  [ "$(ghostty_value palette | wc -l | tr -d ' ')" -eq 16 ]
  [ "$(ghostty_value palette | cut -d= -f1 | sort -n | tr '\n' ' ')" = "0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 " ]
}

@test "ghostty validates the config" {
  local g="${GROVE_GHOSTTY:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"
  [ -x "$g" ] || skip "Ghostty not installed"
  run "$g" +validate-config --config-file="$GROVE_ROOT/config/ghostty/config"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# prompt_styles FILE: "[table] key = value" for every style, toggle and time setting.
prompt_styles() {
  awk '/^\[/ { t = $0 } /^[[:space:]]*(style[a-z_]*|show_always|disabled|time_format)[[:space:]]*=/ { print t " " $0 }' "$1"
}

@test "the two prompts have the same blocks and colors" {
  [ -f "$GROVE_ROOT/config/starship-plain.toml" ]
  diff <(prompt_styles "$GROVE_ROOT/config/starship.toml") <(prompt_styles "$GROVE_ROOT/config/starship-plain.toml")
}

@test "the icon prompt uses the spec's glyphs" {
  local f="$GROVE_ROOT/config/starship.toml"
  grep -q $'\xee\x82\xb6' "$f"          # U+E0B6 rounded left end
  grep -q $'\xee\x82\xb4' "$f"          # U+E0B4 rounded right end
  grep -q $'\xee\x82\xa0' "$f"          # U+E0A0 git branch
  grep -q $'\xf3\xb0\x8c\xbe' "$f"      # U+F033E lock
  grep -q $'\xee\x82\xb0' "$f"          # U+E0B0 arrow between blocks
  grep -q $'\xef\x85\xb9' "$f"          # U+F179 before the user
  grep -q $'\xef\x80\x97' "$f"          # U+F017 clock before the time
}

@test "the plain prompt has no Nerd Font glyphs" {
  # grep: 1 = no match (wanted), 2 = file missing.
  LC_ALL=C run grep -q $'\xee\x82\|\xf3\xb0' "$GROVE_ROOT/config/starship-plain.toml"
  [ "$status" -eq 1 ]
}

@test "macchina shows the spec's readouts in order" {
  local got
  got="$(sed -n 's/^show[[:space:]]*=[[:space:]]*\[\(.*\)\]/\1/p' "$GROVE_ROOT/config/macchina/macchina.toml" | tr -d ' "')"
  [ "$got" = "Host,Machine,Kernel,OperatingSystem,DesktopEnvironment,WindowManager,Packages,Terminal,Shell,LocalIP,Backlight,Resolution,Uptime,Processor,ProcessorLoad,Memory,Battery" ]
  grep -qx 'theme = "grove"' "$GROVE_ROOT/config/macchina/macchina.toml"
}

@test "the logo art is 20 lines by at most 40 columns, next to the stats box" {
  local f="$GROVE_ROOT/config/macchina/grove.ascii" w=0 line n
  [ -f "$f" ]
  [ "$(wc -l < "$f" | tr -d ' ')" -eq 20 ]
  while IFS= read -r line; do
    n="$(printf '%s' "$line" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')"
    [ "$n" -gt "$w" ] && w="$n"
  done < "$f"
  [ "$w" -le 40 ]
}

@test "the macchina art is the rendered logo" {
  command -v python3 >/dev/null || [ -x /opt/homebrew/bin/python3 ] || skip "python3 not installed"
  diff <(PATH="/opt/homebrew/bin:$PATH" python3 -I "$GROVE_ROOT/theme/render-logo.py") "$GROVE_ROOT/config/macchina/grove.ascii"
}

@test "the logo uses only palette colors from its legend" {
  run grep -v '^#' "$GROVE_ROOT/theme/grove-logo.txt"
  [[ "$output" =~ ^[AGYTDE.[:space:]]*$ ]] || false
}

@test "macchina accepts its config" {
  command -v macchina >/dev/null || [ -x /opt/homebrew/bin/macchina ] || skip "macchina not installed"
  local h="$BATS_TEST_TMPDIR/mhome"
  mkdir -p "$h"
  ln -s "$GROVE_ROOT/config" "$h/.config"
  run env HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="/opt/homebrew/bin:/usr/bin:/bin" macchina
  [ "$status" -eq 0 ]
  [[ "$output" != *rror* ]] || false
  [[ "$output" == *Host* ]] || false
  run env HOME="$h" XDG_CONFIG_HOME="$h/.config" PATH="/opt/homebrew/bin:/usr/bin:/bin" macchina -l
  [[ "$output" == *grove* ]] || false
}

# render_prompt FILE: the prompt Starship draws in a temp git repo, colors stripped.
render_prompt() {
  local r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r" && git -C "$r" init -q -b main && touch "$r/new"
  (cd "$r" && env STARSHIP_CONFIG="$1" /opt/homebrew/bin/starship prompt --status 0) | sed $'s/\033\\[[0-9;]*m//g; s/%{//g; s/%}//g' | sed '/^$/d'
}

@test "the prompt bar reads user, folder, git, time, joined by arrows with rounded ends" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_ROOT/config/starship.toml"
  local me; me="$(id -un)" A=$'\xee\x82\xb0'
  [[ "$output" =~ ^$'\xee\x82\xb6'.*$me\ $A\ .*repo\ $A\ .*main\ .*\?.*$A.*[0-9]{2}:[0-9]{2}\ $'\xee\x82\xb4'\ \ ?❯ ]] || { echo "$output"; false; }
  [[ "$output" == *$'\xef\x85\xb9'* ]] || false   # U+F179 before the user
}

@test "the prompt has no duration or exit-code blocks" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  local r="$BATS_TEST_TMPDIR/repo3"; mkdir -p "$r"
  run bash -c "cd '$r' && STARSHIP_CONFIG='$GROVE_ROOT/config/starship.toml' /opt/homebrew/bin/starship prompt --status 1 --cmd-duration 9000"
  [[ "$output" != *"✗"* ]] || false
  [[ "$output" != *"9s"* ]] || false
}

@test "prompts are separated by an empty line" {
  grep -qx 'add_newline = true' "$GROVE_ROOT/config/starship.toml"
  grep -qx 'add_newline = true' "$GROVE_ROOT/config/starship-plain.toml"
}

@test "the plain prompt bar has the same blocks without rounded ends" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  run render_prompt "$GROVE_ROOT/config/starship-plain.toml"
  local me; me="$(id -un)"
  [[ "$output" =~ ^\ \ $me\ .*repo\ .*main\ .*\?.*\ [0-9]{2}:[0-9]{2}\ +❯ ]] || { echo "$output"; false; }
  [[ "$output" != *$'\xee\x82'* ]] || false
}

@test "a failed command turns the prompt character red" {
  [ -x /opt/homebrew/bin/starship ] || skip "starship not installed"
  local r="$BATS_TEST_TMPDIR/repo2"; mkdir -p "$r"
  run bash -c "cd '$r' && STARSHIP_CONFIG='$GROVE_ROOT/config/starship.toml' /opt/homebrew/bin/starship prompt --status 1"
  [[ "$output" == *"38;2;230;126;128m"*"❯"* ]] || false
}

@test "macchina draws the stats in a titled box with icons and the color dots" {
  local t="$GROVE_ROOT/config/macchina/themes/grove.toml"
  sed -n '/^\[box\]/,/^\[/p' "$t" | grep -qx 'visible = true'
  sed -n '/^\[box\]/,/^\[/p' "$t" | grep -qx 'title = " Grove "'
  sed -n '/^\[palette\]/,/^\[/p' "$t" | grep -qx 'visible = true'
  [ "$(sed -n '/^\[keys\]/,$p' "$t" | grep -c '= "')" -ge 17 ]
}
