# shellcheck shell=bash
# 05-config: ~/.config is a link to the tracked config folder.

about() { echo "the .config folder is a link to the tracked config"; }

check() {
  local link="$HOME/.config"
  grove_link_check "$GROVE_CONFIG" "$link"
}

# _config_merge SRC DST: move what is in folder SRC into folder DST. A name that
# DST doesn't have moves across; two real folders merge; anything else that
# collides goes to the backup (the tracked copy stays as it is).
_config_merge() {
  local src="$1" dst="$2" e name moved
  for e in "$src"/* "$src"/.[!.]* "$src"/..?*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    name="$(basename "$e")"
    if [ ! -e "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      mv "$e" "$dst/$name" || { grove_fail "could not move $e"; return 1; }
    elif [ -d "$e" ] && [ ! -L "$e" ] && [ -d "$dst/$name" ] && [ ! -L "$dst/$name" ]; then
      _config_merge "$e" "$dst/$name" || return 1
      rmdir "$e" 2>/dev/null || true
    else
      moved="$(grove_backup "$e")" || return 1
      grove_info "$e collides with the tracked config, backed up to $moved"
    fi
  done
}

apply() {
  local link="$HOME/.config"
  if [ -L "$link" ]; then
    if grove_link_check "$GROVE_CONFIG" "$link"; then return 0; fi
    grove_fail "$link is a symlink to $(readlink "$link"), not replacing it"
    return 1
  fi
  mkdir -p "$GROVE_CONFIG" || { grove_fail "could not create $GROVE_CONFIG"; return 1; }
  if [ -e "$link" ]; then
    if [ ! -d "$link" ]; then
      grove_fail "$link is not a folder, not touching it"
      return 1
    fi
    _config_merge "$link" "$GROVE_CONFIG" || return 1
    if ! rmdir "$link" 2>/dev/null; then
      grove_fail "$link still has content after moving it; leaving it in place"
      return 1
    fi
  fi
  grove_link "$GROVE_CONFIG" "$link"
}
