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
