#!/usr/bin/env bats
# Colour-carrying configs are templates (config/<path>.tmpl), rendered by
# grove-themes for any of the six schemes. Spec §5.
# shellcheck disable=SC1090,SC1091

load helpers

setup() {
  grove_test_setup
  . "$GROVE_ROOT/../grove-themes/lib/render.sh"
  PALETTES="$GROVE_ROOT/theme"
}

# The twelve generated files, one per line.
GENERATED="eza/theme.yml
fastfetch/config.jsonc
ghostty/config
starship-plain.toml
starship.toml
vscode/settings.json
yazi/init.lua
yazi/theme.toml
zsh/conf.d/40-tools.zsh
zsh/conf.d/85-autosuggest.zsh
zsh/conf.d/95-fetch.zsh
zsh/conf.d/98-highlight.zsh"

@test "the templates are the twelve colour-carrying configs" {
  local want
  want="$(printf '%s\n' "$GENERATED" | sed 's/$/.tmpl/' | LC_ALL=C sort)"
  [ "$(gt_templates "$GROVE_ROOT/config")" = "$want" ] || { diff <(echo "$want") <(gt_templates "$GROVE_ROOT/config"); false; }
}

@test "templates use only palette and computed names" {
  local names t n
  names="$(gt_values dark-medium "$PALETTES" | cut -f1)"
  [ -n "$(gt_templates "$GROVE_ROOT/config")" ]
  for t in $(gt_templates "$GROVE_ROOT/config"); do
    for n in $(grep -o '{{[a-z0-9_]*}}' "$GROVE_ROOT/config/$t" | sed 's/[{}]//g' | sort -u); do
      printf '%s\n' "$names" | grep -qx "$n" || { echo "$t: unknown name $n"; false; }
    done
  done
}

@test "every template renders for all six schemes" {
  local s f out n=0
  for s in $(gt_schemes); do
    for f in $GENERATED; do
      out="$BATS_TEST_TMPDIR/$s/$f"
      mkdir -p "$(dirname "$out")"
      gt_render_file "$s" "$PALETTES" "$GROVE_ROOT/config/$f.tmpl" "$out" || { echo "$s: $f failed"; false; }
      [ -s "$out" ] || { echo "$s: $f empty"; false; }
      n=$((n + 1))
    done
  done
  [ "$n" -eq 72 ]
}

@test "the Dark Medium render is today's config" {
  local f out
  for f in $GENERATED; do
    [ -f "$GROVE_ROOT/tests/fixtures/dark-medium/$f" ] || { echo "no fixture: $f"; false; }
    out="$BATS_TEST_TMPDIR/out/$f"
    mkdir -p "$(dirname "$out")"
    gt_render_file dark-medium "$PALETTES" "$GROVE_ROOT/config/$f.tmpl" "$out" || { echo "render failed: $f"; false; }
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$out" || { diff "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$out"; false; }
  done
}

@test "GROVE_RENDERED is a Dark Medium render of the tracked config" {
  local f
  [ -n "$GROVE_RENDERED" ] && [ -d "$GROVE_RENDERED" ] || false
  for f in $GENERATED; do
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$GROVE_RENDERED/$f" || false
  done
  [ -f "$GROVE_RENDERED/zsh/.zshrc" ] || false
}

@test "grove_copy_tracked_config renders Dark Medium into the copy" {
  local f d="$BATS_TEST_TMPDIR/copy"
  grove_copy_tracked_config "$d"
  for f in $GENERATED; do
    cmp "$GROVE_ROOT/tests/fixtures/dark-medium/$f" "$d/$f" || false
  done
}
