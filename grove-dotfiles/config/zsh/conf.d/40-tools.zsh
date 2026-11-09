# zoxide replaces cd (`builtin cd` still reaches the original); fzf binds
# ⌃R (history), ⌃T (files) and ⌥C (folders), in Everforest colors.
if (( $+commands[zoxide] )); then
  eval "$(zoxide init zsh --cmd cd)"
fi
if (( $+commands[fzf] )); then
  if (( $+commands[rg] )); then
    export FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  fi
  export FZF_DEFAULT_OPTS="--color=bg:#2D353B,bg+:#543A48,fg:#D3C6AA,fg+:#D3C6AA,hl:#A7C080,hl+:#A7C080,prompt:#83C092,pointer:#E67E80,marker:#DBBC7F,info:#859289,spinner:#83C092,header:#7FBBB3,border:#475258"
  source <(fzf --zsh)
fi
