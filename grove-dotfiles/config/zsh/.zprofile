# Login shells: Homebrew environment. Silent. The ssh key isn't loaded here:
# ssh/config (UseKeychain, AddKeysToAgent) loads it from the keychain on first use.
# GROVE_BREW (the path grove uses for brew) lets tests point this elsewhere.
_grove_brew="${GROVE_BREW:-/opt/homebrew/bin/brew}"
if [ -x "$_grove_brew" ]; then
  eval "$("$_grove_brew" shellenv zsh)"
fi
unset _grove_brew
# /etc/zprofile (path_helper) runs after .zshenv and demotes ~/.local/bin; put it back first, once.
typeset -U path
path=("$HOME/.local/bin" ${path:#$HOME/.local/bin})
true
