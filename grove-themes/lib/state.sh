# shellcheck shell=bash
# grove-themes state and whole-config rendering. Source it after render.sh; it
# sets no shell options. Bash 3.2 safe. Needs GROVE_STATE (the state file is
# $GROVE_STATE/theme, one line) and, for gt_render_all, GROVE_ROOT.

GT_DEFAULT_SCHEME="dark-medium"

# gt_current: the state file's scheme. A missing file means dark-medium; an
# empty or unknown value means dark-medium plus a warning on stderr.
gt_current() {
  local file="$GROVE_STATE/theme" s=""
  if [ ! -e "$file" ]; then
    printf '%s\n' "$GT_DEFAULT_SCHEME"
    return 0
  fi
  IFS= read -r s < "$file" || true
  if gt_valid "$s"; then
    printf '%s\n' "$s"
  else
    echo "grove-themes: unknown scheme in $file, using $GT_DEFAULT_SCHEME" >&2
    printf '%s\n' "$GT_DEFAULT_SCHEME"
  fi
}

# gt_write_state SCHEME: write the state file (via a temp file and mv).
gt_write_state() {
  local file="$GROVE_STATE/theme"
  mkdir -p "$GROVE_STATE" || return 1
  printf '%s\n' "$1" > "$file.tmp" || { rm -f "$file.tmp"; return 1; }
  mv "$file.tmp" "$file" || { rm -f "$file.tmp"; return 1; }
}

# _gt_backup PATH: grove's grove_backup (needs $GROVE_ROOT/lib); prints where
# PATH went. Backups of one run land in $GROVE_STATE/backup/$GROVE_RUN_ID.
_gt_backup() {
  local f
  for f in ui link; do
    # shellcheck source=/dev/null
    . "${GROVE_ROOT:?}/lib/$f.sh" || return 1
  done
  grove_backup "$1"
}

# _gt_is_live_config DIR: 0 when DIR is $GROVE_ROOT/config (both resolved).
_gt_is_live_config() {
  local a b
  a="$(cd -P "$1" 2>/dev/null && pwd)" || return 1
  b="$(cd -P "${GROVE_ROOT:?}/config" 2>/dev/null && pwd)" || return 1
  [ "$a" = "$b" ]
}

# gt_render_all SCHEME CONFIG_DIR: render every template under CONFIG_DIR into a
# temp folder beside it, then mv each result into place. A render failure moves
# nothing; a failed mv returns 1 (a later render repairs what is left). The
# last-written records ($GROVE_STATE/theme-rendered, for the edited-file
# backup) are read and written only when CONFIG_DIR is $GROVE_ROOT/config, so
# a render into another folder (a preview) can't make them stale.
gt_render_all() {
  local scheme="$1" cfg="$2" palettes tmp t rc=0 out last dest live=0
  local rendered="$GROVE_STATE/theme-rendered"
  palettes="${GROVE_ROOT:?}/theme"
  [ -d "$cfg" ] || { echo "grove-themes: no config folder $cfg" >&2; return 1; }
  _gt_is_live_config "$cfg" && live=1
  : "${GROVE_RUN_ID:=$(date +%Y%m%d-%H%M%S)}"
  export GROVE_RUN_ID
  tmp="$(mktemp -d "$cfg/.grove-themes.XXXXXX")" || return 1
  for t in $(gt_templates "$cfg"); do
    mkdir -p "$tmp/$(dirname "$t")" || { rm -rf "$tmp"; return 1; }
    if ! out="$(gt_render_file "$scheme" "$palettes" "$cfg/$t" "$tmp/${t%.tmpl}")"; then
      [ -n "$out" ] && echo "grove-themes: $out" >&2
      rm -rf "$tmp"
      return 1
    fi
  done
  for t in $(gt_templates "$cfg"); do
    last="$rendered/${t%.tmpl}"
    if [ "$live" = 1 ] && [ -f "$last" ] && [ -f "$cfg/${t%.tmpl}" ] && ! cmp -s "$last" "$cfg/${t%.tmpl}"; then
      if dest="$(_gt_backup "$cfg/${t%.tmpl}")" && [ -n "$dest" ]; then
        echo "backed up edited ${t%.tmpl} to $dest"
      else
        echo "grove-themes: could not back up $cfg/${t%.tmpl}" >&2
        rc=1
        continue
      fi
    fi
    if ! mv -f "$tmp/${t%.tmpl}" "$cfg/${t%.tmpl}"; then
      echo "grove-themes: could not write $cfg/${t%.tmpl}" >&2
      rc=1
    elif [ "$live" = 1 ]; then
      mkdir -p "$rendered/$(dirname "${t%.tmpl}")" && cp -f "$cfg/${t%.tmpl}" "$last" \
        || echo "grove-themes: could not record $last" >&2
    fi
  done
  rm -rf "$tmp"
  return $rc
}
