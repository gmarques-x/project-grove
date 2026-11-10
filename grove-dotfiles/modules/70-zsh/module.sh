# shellcheck shell=bash
# 70-zsh: zsh files from the tracked config, the grove command on PATH.

about() { echo "zsh config, Starship prompt and the grove and grove-themes commands"; }

_zsh_starship() {
  command -v starship >/dev/null 2>&1 || [ -x /opt/homebrew/bin/starship ]
}

# History moved to ~/.local/state/zsh/history; carry the old file across once.
_zsh_hist_old() { echo "$HOME/.zsh_history"; }
_zsh_hist_new() { echo "$HOME/.local/state/zsh/history"; }
_zsh_hist_pending() {
  [ -f "$(_zsh_hist_old)" ] && [ ! -e "$(_zsh_hist_new)" ] && [ ! -L "$(_zsh_hist_new)" ]
}

# Terminal.app writes session files to $ZDOTDIR/.zsh_sessions (fixed in
# /etc/zshrc_Apple_Terminal), so that path is a link into the state folder.
_zsh_sessions_link() { echo "$GROVE_CONFIG/zsh/.zsh_sessions"; }
_zsh_sessions_dir() { echo "$HOME/.local/state/zsh/sessions"; }

# Files zsh and Terminal kept in $HOME before ZDOTDIR moved to ~/.config/zsh.
# ~/.zsh_history only goes once its copy exists in the state folder.
_zsh_home_leftovers() {
  [ -e "$HOME/.zsh_sessions" ] || [ -L "$HOME/.zsh_sessions" ] && echo "$HOME/.zsh_sessions"
  { [ -e "$HOME/.zsh_history" ] || [ -L "$HOME/.zsh_history" ]; } && ! _zsh_hist_pending && echo "$HOME/.zsh_history"
  return 0
}

# compinit refuses folders that others can write to. _zsh_insecure_dirs lists
# the ones compaudit reports inside the Homebrew prefix (anything else is never
# touched). GROVE_COMPAUDIT replaces the compaudit run in tests.
_zsh_brew_prefix() { dirname "$(dirname "${GROVE_BREW:-/opt/homebrew/bin/brew}")"; }
_zsh_insecure_dirs() {
  local prefix d
  prefix="$(_zsh_brew_prefix)"
  if [ -n "${GROVE_COMPAUDIT:-}" ]; then
    "$GROVE_COMPAUDIT" 2>/dev/null
  else
    # shellcheck disable=SC2016
    /bin/zsh -fc 'fpath=("$1/share/zsh-completions" "$1/share/zsh/site-functions" $fpath)
      autoload -Uz compaudit; compaudit 2>/dev/null' _ "$prefix"
  fi | while IFS= read -r d; do
    # Folders owned by someone else (another account's Homebrew) can't be fixed
    # here; 30-completion.zsh leaves them out of fpath instead.
    case "$d" in "$prefix"/*) [ -d "$d" ] && [ -O "$d" ] && printf '%s\n' "$d" ;; esac
  done
  return 0
}

check() {
  grove_link_check "$GROVE_CONFIG/zsh/.zshenv" "$HOME/.zshenv" || return 3
  grove_link_check "$GROVE_ROOT/bin/grove" "$HOME/.local/bin/grove" || return 3
  grove_link_check "$GROVE_ROOT/../grove-themes/bin/grove-themes" "$HOME/.local/bin/grove-themes" || return 3
  [ ! -e "$HOME/.zprofile" ] && [ ! -L "$HOME/.zprofile" ] || return 3
  [ ! -e "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ] || return 3
  _zsh_starship || return 3
  ! _zsh_hist_pending || return 3
  grove_link_check "$(_zsh_sessions_dir)" "$(_zsh_sessions_link)" || return 3
  [ -d "$(_zsh_sessions_dir)" ] || return 3
  [ -z "$(_zsh_home_leftovers)" ] || return 3
  [ -z "$(_zsh_insecure_dirs)" ] || return 3
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
  grove_link "$GROVE_ROOT/../grove-themes/bin/grove-themes" "$HOME/.local/bin/grove-themes" || return 1
  if _zsh_hist_pending; then
    mkdir -p "$(dirname "$(_zsh_hist_new)")" || { grove_fail "could not create $(dirname "$(_zsh_hist_new)")"; return 1; }
    cp -n "$(_zsh_hist_old)" "$(_zsh_hist_new)" || { grove_fail "could not copy shell history"; return 1; }
    grove_info "copied $(_zsh_hist_old) to $(_zsh_hist_new)"
  fi
  _zsh_apply_sessions || return 1
  local old
  for old in $(_zsh_home_leftovers); do
    moved="$(grove_backup "$old")" || return 1
    grove_note "backed up $old to $moved"
  done
  local d
  while IFS= read -r d; do
    chmod go-w "$d" || { grove_fail "could not fix permissions on $d"; return 1; }
    grove_note "removed group/other write access on $d (zsh completion refuses it)"
  done < <(_zsh_insecure_dirs)
}

_zsh_apply_sessions() {
  local link dir
  link="$(_zsh_sessions_link)"; dir="$(_zsh_sessions_dir)"
  # A real sessions folder in the config moves over whole when the state one is new.
  if [ -d "$link" ] && [ ! -L "$link" ] && [ ! -e "$dir" ]; then
    mkdir -p "$(dirname "$dir")" || { grove_fail "could not create $(dirname "$dir")"; return 1; }
    mv -n "$link" "$dir" || { grove_fail "could not move $link to $dir"; return 1; }
    grove_info "moved $link to $dir"
  fi
  mkdir -p "$dir" || { grove_fail "could not create $dir"; return 1; }
  chmod 700 "$dir"
  grove_link "$dir" "$link"
}
