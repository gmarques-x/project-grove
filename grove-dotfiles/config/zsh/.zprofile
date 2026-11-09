# Login shells: Homebrew environment and the ssh keychain. Silent.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv zsh)"
fi
if command -v ssh-add >/dev/null 2>&1; then
  ssh-add --apple-load-keychain -q 2>/dev/null
fi
# /etc/zprofile (path_helper) runs after .zshenv and demotes ~/.local/bin; put it back first, once.
typeset -U path
path=("$HOME/.local/bin" ${path:#$HOME/.local/bin})
true
