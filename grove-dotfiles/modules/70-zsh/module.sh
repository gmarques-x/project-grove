# shellcheck shell=bash
# 70-zsh: zsh files from the tracked config, the grove command on PATH.

about() { echo "zsh config, Starship prompt and the grove command"; }

_zsh_starship() {
  command -v starship >/dev/null 2>&1 || [ -x /opt/homebrew/bin/starship ]
}

check() {
  grove_link_check "$GROVE_CONFIG/zsh/.zshenv" "$HOME/.zshenv" || return 3
  grove_link_check "$GROVE_ROOT/bin/grove" "$HOME/.local/bin/grove" || return 3
  [ ! -e "$HOME/.zprofile" ] && [ ! -L "$HOME/.zprofile" ] || return 3
  [ ! -e "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ] || return 3
  _zsh_starship || return 3
  return 0
}

apply() {
  local f moved
  for f in .zprofile .zshrc; do
    if [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ]; then
      moved="$(grove_backup "$HOME/$f")" || return 1
      grove_info "backed up $HOME/$f to $moved"
    fi
  done
  grove_link "$GROVE_CONFIG/zsh/.zshenv" "$HOME/.zshenv" || return 1
  mkdir -p "$HOME/.local/bin" || { grove_fail "could not create $HOME/.local/bin"; return 1; }
  grove_link "$GROVE_ROOT/bin/grove" "$HOME/.local/bin/grove" || return 1
}
