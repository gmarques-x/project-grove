# Syntax highlighting, loaded last so it wraps every other widget.
_grove_f="${HOMEBREW_PREFIX:-/nonexistent}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
if [[ -r "$_grove_f" ]]; then
  source "$_grove_f"
  ZSH_HIGHLIGHT_STYLES[command]='fg=#A7C080'
  ZSH_HIGHLIGHT_STYLES[builtin]='fg=#A7C080'
  ZSH_HIGHLIGHT_STYLES[alias]='fg=#A7C080'
  ZSH_HIGHLIGHT_STYLES[function]='fg=#A7C080'
  ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#E67E80'
  ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#DBBC7F'
  ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#DBBC7F'
  ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#DBBC7F'
  ZSH_HIGHLIGHT_STYLES[path]='underline'
  ZSH_HIGHLIGHT_STYLES[comment]='fg=#859289'
fi
unset _grove_f
