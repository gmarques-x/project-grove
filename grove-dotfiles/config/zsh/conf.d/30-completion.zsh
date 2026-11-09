# Completion: zsh's own system plus zsh-completions. The dump and cache live in
# $XDG_CACHE_HOME/zsh. Insecure folders are fixed by grove (70-zsh), never ignored.
# HOMEBREW_PREFIX comes from `brew shellenv` in .zprofile (inherited by child shells).
if [[ -n "$HOMEBREW_PREFIX" ]]; then
  [[ -d "$HOMEBREW_PREFIX/share/zsh-completions" ]] && fpath=("$HOMEBREW_PREFIX/share/zsh-completions" $fpath)
  [[ -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]] && fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
  typeset -U fpath
fi
[[ -d "$XDG_CACHE_HOME/zsh" ]] || mkdir -p "$XDG_CACHE_HOME/zsh"
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump-$ZSH_VERSION"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
