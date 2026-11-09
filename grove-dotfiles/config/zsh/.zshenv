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
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
