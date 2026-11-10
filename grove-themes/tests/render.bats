load helpers
setup() { gt_test_setup; gt_toy_palettes; source "$GT_ROOT/lib/render.sh"; }

@test "render fills names with the scheme's values" {
  printf 'fg={{fg}} bg={{bg0}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A1 bg=#27E31" ]
  gt_render_file light-soft "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A6 bg=#27E36" ]
}

@test "render fills the computed names" {
  printf '{{appearance}}|{{contrast}}|{{vscode_theme}}|{{fetch_image}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file light-soft "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "light|soft|Everforest Light|grove-light-soft.png" ]
  gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "dark|hard|Everforest Dark|grove.png" ]
}

@test "fetch_image: grove.png for every dark scheme, grove-light-<contrast>.png for each light one" {
  local s want
  for s in $(gt_schemes); do
    case "$s" in
      dark-*) want=grove.png ;;
      *) want="grove-light-${s#light-}.png" ;;
    esac
    [ "$(gt_values "$s" "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = "$want" ] || { echo "$s"; false; }
  done
  [ "$(gt_values light-hard "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = grove-light-hard.png ]
  [ "$(gt_values light-medium "$PALETTES" | awk -F"\t" '$1 == "fetch_image" { print $2 }')" = grove-light-medium.png ]
}

@test "values with & / and backslash render literally" {
  printf '{{amp}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-medium "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = '#A&B/C\2' ]
}

@test "an unknown name fails and writes nothing" {
  printf 'x={{nope}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown name: nope in $BATS_TEST_TMPDIR/t.tmpl"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out" ]
  [ ! -e "$BATS_TEST_TMPDIR/out.tmp" ]
}

@test "text without names passes through byte for byte" {
  printf '# c / path & amp \\ back {single} $x `y`\n\tindent\nno newline' > "$BATS_TEST_TMPDIR/t.tmpl"
  gt_render_file dark-hard "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  cmp "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
}

@test "gt_valid rejects other names" {
  gt_valid dark-hard
  gt_valid light-soft
  run gt_valid dark;        [ "$status" -eq 1 ]
  run gt_valid Dark-Medium; [ "$status" -eq 1 ]
  run gt_valid "";          [ "$status" -eq 1 ]
}

@test "gt_schemes lists the six in order" {
  [ "$(gt_schemes | tr '\n' ' ')" = "dark-hard dark-medium dark-soft light-hard light-medium light-soft " ]
}

@test "gt_values lists palette entries then computed names" {
  run gt_values dark-hard "$PALETTES"
  [ "${lines[0]}" = "$(printf 'fg\t#D3C6A1')" ]
  [ "${#lines[@]}" -eq 7 ]
  [ "${lines[6]}" = "$(printf 'fetch_image\tgrove.png')" ]
}

@test "gt_templates lists *.tmpl relative and sorted" {
  mkdir -p "$BATS_TEST_TMPDIR/cfg/b" "$BATS_TEST_TMPDIR/cfg/a"
  touch "$BATS_TEST_TMPDIR/cfg/b/z.tmpl" "$BATS_TEST_TMPDIR/cfg/a/y.tmpl" "$BATS_TEST_TMPDIR/cfg/a/n.txt"
  run gt_templates "$BATS_TEST_TMPDIR/cfg"
  [ "$output" = "$(printf 'a/y.tmpl\nb/z.tmpl')" ]
}

@test "render works under set -euo pipefail" {
  printf 'fg={{fg}}\n' > "$BATS_TEST_TMPDIR/t.tmpl"
  run /bin/bash -c 'set -euo pipefail; source "$1/lib/render.sh"; gt_render_file dark-hard "$2" "$3" "$4"; echo done' _ "$GT_ROOT" "$PALETTES" "$BATS_TEST_TMPDIR/t.tmpl" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [ "$output" = done ]
  [ "$(cat "$BATS_TEST_TMPDIR/out")" = "fg=#D3C6A1" ]
  [ ! -e "$BATS_TEST_TMPDIR/out.tmp" ]
  printf 'x={{nope}}\n' > "$BATS_TEST_TMPDIR/u.tmpl"
  run /bin/bash -c 'set -euo pipefail; source "$1/lib/render.sh"; gt_render_file dark-hard "$2" "$3" "$4" || echo "rc=$?"' _ "$GT_ROOT" "$PALETTES" "$BATS_TEST_TMPDIR/u.tmpl" "$BATS_TEST_TMPDIR/out2"
  [[ "$output" == *"unknown name: nope"*"rc=1"* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/out2" ]
}
