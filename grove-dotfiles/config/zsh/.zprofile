# Login shells: Homebrew environment and the ssh keychain. Silent.
# GROVE_BREW (the path grove uses for brew) lets tests point this elsewhere.
_grove_brew="${GROVE_BREW:-/opt/homebrew/bin/brew}"
if [ -x "$_grove_brew" ]; then
  eval "$("$_grove_brew" shellenv zsh)"
fi
unset _grove_brew
if command -v ssh-add >/dev/null 2>&1; then
  ssh-add --apple-load-keychain -q 2>/dev/null
fi
# /etc/zprofile (path_helper) runs after .zshenv and demotes ~/.local/bin; put it back first, once.
typeset -U path
path=("$HOME/.local/bin" ${path:#$HOME/.local/bin})
true
