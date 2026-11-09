# shellcheck shell=bash
# grove link helpers: symlinks with backup. Meant to be sourced; sets no shell
# options. Needs lib/ui.sh (grove_info, grove_fail). Nothing here deletes.

# grove_backup PATH: move PATH (file, directory, or the symlink itself) into
# $GROVE_STATE/backup/$GROVE_RUN_ID/. Under $HOME the backup path is relative to
# $HOME; elsewhere it is the absolute path minus the leading "/". An existing
# backup is never overwritten: a ".N" suffix is added. Prints the new location.
# No-op (0) when PATH doesn't exist; 1 for a relative path, $HOME itself, or a
# failed move.
grove_backup() {
  local src="$1" rel dest n
  case "$src" in
    /*) ;;
    *) grove_fail "backup needs an absolute path: $src"; return 1 ;;
  esac
  [ -e "$src" ] || [ -L "$src" ] || return 0
  # Normalize trailing slashes ("/x/dir/" would make mv follow a symlink).
  while [ "${#src}" -gt 1 ] && [ "${src%/}" != "$src" ]; do src="${src%/}"; done
  if [ "$src" = "${HOME%/}" ] || [ "$src" = "/" ]; then
    grove_fail "refusing to back up $src"
    return 1
  fi
  case "$src" in
    "${HOME%/}"/*) rel="${src#"${HOME%/}"/}" ;;
    *) rel="${src#/}" ;;
  esac
  dest="$GROVE_STATE/backup/$GROVE_RUN_ID/$rel"
  n=0
  while [ -e "$dest" ] || [ -L "$dest" ]; do
    n=$((n + 1))
    dest="$GROVE_STATE/backup/$GROVE_RUN_ID/$rel.$n"
  done
  mkdir -p "$(dirname "$dest")" || return 1
  if ! mv -n "$src" "$dest"; then
    grove_fail "could not back up $src"
    return 1
  fi
  # mv -n skips silently when dest appeared meanwhile; make sure src moved.
  if [ -e "$src" ] || [ -L "$src" ]; then
    grove_fail "could not back up $src"
    return 1
  fi
  printf '%s\n' "$dest"
}

# grove_link_check TARGET LINK: 0 when LINK is a symlink to TARGET, else 3.
# Changes nothing.
grove_link_check() {
  [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ] && return 0
  return 3
}

# grove_link TARGET LINK: make LINK a symlink to TARGET. A correct link is left
# alone; a real file or directory is backed up first; a symlink to something
# else is never touched (returns 1).
grove_link() {
  local target="$1" link="$2" moved
  if [ -L "$link" ]; then
    grove_link_check "$target" "$link" && return 0
    grove_fail "$link is a symlink to $(readlink "$link"), not touching it"
    return 1
  fi
  if [ -e "$link" ]; then
    moved="$(grove_backup "$link")" || return 1
    grove_note "backed up $link to $moved"
  fi
  mkdir -p "$(dirname "$link")" || { grove_fail "could not create folder for $link"; return 1; }
  if ! ln -s "$target" "$link"; then
    grove_fail "could not link $link"
    return 1
  fi
}
