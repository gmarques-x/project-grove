# Runs for every zsh, scripts included: exports only, nothing printed.
# XDG base folders; values already set win.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
# Tools that would otherwise use ~/Library/Application Support on macOS.
export _ZO_DATA_DIR="$XDG_DATA_HOME/zoxide"
export EZA_CONFIG_DIR="$XDG_CONFIG_HOME/eza"
# Terminal.app: one shared history (conf.d/10-history.zsh), no per-window copies.
# Its session files go to $ZDOTDIR/.zsh_sessions, a link into $XDG_STATE_HOME (70-zsh).
export SHELL_SESSION_HISTORY=0
# Editor for git, zalias and zedit: VS Code when it's installed and this isn't an
# ssh session (its window would open on the far machine), else vim, else vi.
# Values already set win. Homebrew's folder joins the PATH after this file
# (/etc/zprofile, .zprofile), so `code` is looked for there too; GROVE_BREW as in
# .zprofile. Builtins only: this file runs for every zsh.
if [[ -z "$EDITOR" ]]; then
  _grove_code="${${GROVE_BREW:-/opt/homebrew/bin/brew}:h}/code"
  if [[ -n "$SSH_CONNECTION$SSH_TTY" ]]; then
    _grove_code=
  elif (( $+commands[code] )); then
    _grove_code=code
  elif [[ ! -x "$_grove_code" ]]; then
    _grove_code=
  fi
  if [[ -n "$_grove_code" ]]; then
    export EDITOR="$_grove_code --wait"
  elif (( $+commands[vim] )); then
    export EDITOR=vim
  else
    export EDITOR=vi
  fi
  unset _grove_code
fi
export VISUAL="${VISUAL:-$EDITOR}"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
