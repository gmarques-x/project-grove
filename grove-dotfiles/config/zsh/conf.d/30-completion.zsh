# Completion: zsh's own system plus zsh-completions. The dump and cache live in
# $XDG_CACHE_HOME/zsh. Insecure folders are fixed by grove (70-zsh), never ignored.
# HOMEBREW_PREFIX comes from `brew shellenv` in .zprofile (inherited by child shells).
# A Homebrew folder is used only when this user owns it and its parent, and
# neither is writable by others, so compinit never stops to ask about insecure
# folders (70-zsh fixes the permissions; another account's Homebrew is skipped).
_grove_safe_dir() {
  local d m
  for d in "$1" "${1:h}"; do
    [[ -d "$d" && -O "$d" ]] || return 1
    m="$(command stat -f %Lp "$d" 2>/dev/null)" || return 1
    [[ "${m[-2]}" == [0145] && "${m[-1]}" == [0145] ]] || return 1
  done
}
if [[ -n "$HOMEBREW_PREFIX" ]]; then
  local_dir=
  for local_dir in "$HOMEBREW_PREFIX/share/zsh/site-functions" "$HOMEBREW_PREFIX/share/zsh-completions"; do
    fpath=(${fpath:#$local_dir})
    _grove_safe_dir "$local_dir" && fpath=("$local_dir" $fpath)
  done
  unset local_dir
  typeset -U fpath
fi
unfunction _grove_safe_dir
[[ -d "$XDG_CACHE_HOME/zsh" ]] || mkdir -p "$XDG_CACHE_HOME/zsh"
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
