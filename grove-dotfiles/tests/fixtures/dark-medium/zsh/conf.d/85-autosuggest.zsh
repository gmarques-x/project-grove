# Suggestions from history in grey1; → accepts one.
_grove_f="${HOMEBREW_PREFIX:-/nonexistent}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
if [[ -r "$_grove_f" ]]; then
  ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#859289'
  source "$_grove_f"
fi
unset _grove_f
