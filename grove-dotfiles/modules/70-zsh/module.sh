# shellcheck shell=bash
# 70-zsh: zsh files from the tracked config, the grove command on PATH.

about() { echo "zsh config, Starship prompt and the grove command"; }

_zsh_starship() {
  command -v starship >/dev/null 2>&1 || [ -x /opt/homebrew/bin/starship ]
}

# History moved to ~/.local/state/zsh/history; carry the old file across once.
_zsh_hist_old() { echo "$HOME/.zsh_history"; }
_zsh_hist_new() { echo "$HOME/.local/state/zsh/history"; }
_zsh_hist_pending() {
  [ -f "$(_zsh_hist_old)" ] && [ ! -e "$(_zsh_hist_new)" ] && [ ! -L "$(_zsh_hist_new)" ]
}

check() {
  grove_link_check "$GROVE_CONFIG/zsh/.zshenv" "$HOME/.zshenv" || return 3
  grove_link_check "$GROVE_ROOT/bin/grove" "$HOME/.local/bin/grove" || return 3
  [ ! -e "$HOME/.zprofile" ] && [ ! -L "$HOME/.zprofile" ] || return 3
  [ ! -e "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ] || return 3
  _zsh_starship || return 3
  ! _zsh_hist_pending || return 3
  return 0
}

apply() {
  local f moved
  for f in .zprofile .zshrc; do
    if [ -e "$HOME/$f" ] || [ -L "$HOME/$f" ]; then
      moved="$(grove_backup "$HOME/$f")" || return 1
      grove_note "backed up $HOME/$f to $moved"
    fi
  done
  grove_link "$GROVE_CONFIG/zsh/.zshenv" "$HOME/.zshenv" || return 1
  mkdir -p "$HOME/.local/bin" || { grove_fail "could not create $HOME/.local/bin"; return 1; }
  grove_link "$GROVE_ROOT/bin/grove" "$HOME/.local/bin/grove" || return 1
  if _zsh_hist_pending; then
    mkdir -p "$(dirname "$(_zsh_hist_new)")" || { grove_fail "could not create $(dirname "$(_zsh_hist_new)")"; return 1; }
    cp -n "$(_zsh_hist_old)" "$(_zsh_hist_new)" || { grove_fail "could not copy shell history"; return 1; }
    grove_info "copied $(_zsh_hist_old) to $(_zsh_hist_new)"
  fi
}
