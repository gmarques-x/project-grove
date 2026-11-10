# shellcheck shell=bash
# grove-themes template renderer. Source it; it sets no shell options.
# Templates use {{name}}, name = [a-z0-9_]+. Bash 3.2 safe.

gt_schemes() {
  printf '%s\n' dark-hard dark-medium dark-soft light-hard light-medium light-soft
}

# gt_valid SCHEME: 0 when SCHEME is one of the six.
gt_valid() {
  local s
  for s in $(gt_schemes); do
    [ "$s" = "$1" ] && return 0
  done
  return 1
}

# gt_values SCHEME PALETTE_DIR: name<TAB>value lines, palette entries first,
# then name_rgb ("R, G, B" in decimal) and name_argb (0xffRRGGBB, upper case)
# for each #RRGGBB entry, then appearance,
# contrast, vscode_theme, fetch_image, chrome_version (1.0.N, N the scheme's
# position, so every switch changes Chrome's cached theme).
gt_values() {
  local scheme="$1" dir="$2" tab appearance contrast vscode image name hex s n
  tab="$(printf '\t')"
  sed -n "s/^[[:space:]]*\\([a-z0-9_][a-z0-9_]*\\)[[:space:]]*=[[:space:]]*\\([^[:space:]][^[:space:]]*\\)[[:space:]]*\$/\\1${tab}\\2/p" \
    "$dir/everforest-$scheme" || return 1
  sed -n "s/^[[:space:]]*\\([a-z0-9_][a-z0-9_]*\\)[[:space:]]*=[[:space:]]*#\\([0-9A-Fa-f]\\{6\\}\\)[[:space:]]*\$/\\1 \\2/p" \
    "$dir/everforest-$scheme" | while read -r name hex; do
    printf '%s_rgb\t%d, %d, %d\n' "$name" "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
    printf '%s_argb\t0xff%s\n' "$name" "$(printf '%s' "$hex" | tr '[:lower:]' '[:upper:]')"
  done
  n=0
  for s in $(gt_schemes); do
    n=$((n + 1))
    [ "$s" = "$scheme" ] && break
  done
  appearance="${scheme%%-*}"
  contrast="${scheme#*-}"
  if [ "$appearance" = light ]; then
    vscode="Everforest Light"
    image="grove-light-$contrast.png"
  else
    vscode="Everforest Dark"
    image="grove.png"
  fi
  printf 'appearance\t%s\ncontrast\t%s\nvscode_theme\t%s\nfetch_image\t%s\nchrome_version\t1.0.%s\n' \
    "$appearance" "$contrast" "$vscode" "$image" "$n"
}

# gt_render_file SCHEME PALETTE_DIR TEMPLATE OUT
gt_render_file() {
  local scheme="$1" dir="$2" tmpl="$3" out="$4"
  local script tmp name value bad
  tmp="$out.tmp"
  script="$(mktemp "${TMPDIR:-/tmp}/gt-sed.XXXXXX")" || return 1
  gt_valid "$scheme" && [ -r "$dir/everforest-$scheme" ] || { rm -f "$script"; return 1; }
  while IFS="$(printf '\t')" read -r name value; do
    value="$(printf '%s' "$value" | sed -e 's/[\\/&]/\\&/g')"
    printf 's/{{%s}}/%s/g\n' "$name" "$value" >> "$script"
  done <<EOT
$(gt_values "$scheme" "$dir")
EOT
  if ! sed -f "$script" "$tmpl" > "$tmp"; then
    rm -f "$script" "$tmp"
    return 1
  fi
  rm -f "$script"
  bad="$(grep -o '{{[a-z0-9_]*}}' "$tmp" || true)"
  bad="${bad%%$'\n'*}"
  if [ -n "$bad" ]; then
    name="${bad#\{\{}"
    name="${name%\}\}}"
    echo "unknown name: $name in $tmpl"
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$out"
}

# gt_templates CONFIG_DIR: every *.tmpl under it, relative, sorted.
gt_templates() {
  (cd "$1" && find . -type f -name '*.tmpl' | sed 's|^\./||' | LC_ALL=C sort)
}
