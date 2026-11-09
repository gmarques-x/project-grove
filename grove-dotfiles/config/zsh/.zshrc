# Interactive shells: load every conf.d/*.zsh in name order.
for _grove_conf in "$ZDOTDIR"/conf.d/*.zsh(N); do
  source "$_grove_conf"
done
unset _grove_conf
