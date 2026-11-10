# shellcheck shell=bash
# grove-themes: the steps of `set` after the configs. Source it after render.sh
# and state.sh; it sets no shell options. Bash 3.2 safe.
#
# Each gt_step_* prints result lines  name<TAB>result<TAB>message  and returns 0,
# or 1 when any line is failed or needs-you. result is one of: live,
# next-prompt, next-launch, needs-you, failed.
# Seams: GROVE_PS (default ps), GROVE_WALLPAPER_DIR (default
# $GROVE_ROOT/../grove-wallpapers), GROVE_WALLPAPER_STORE, GROVE_KILLALL (default killall), GROVE_CHROME_APP (default
# /Applications/Google Chrome.app), GROVE_KILL (default the kill builtin; a
# PATH stub cannot shadow a builtin). osascript and defaults come from PATH.

GT_AUTOMATION_HINT="allow Grove Themes or your terminal to control System Events (System Settings > Privacy & Security > Automation), then switch again"

_gt_line() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

# gt_step_ghostty: SIGUSR2 reloads Ghostty's config (Ghostty 1.4 macOS).
gt_step_ghostty() {
  local pid comm n=0 rc=0
  while read -r pid comm; do
    case "$comm" in
      */Ghostty.app/Contents/MacOS/ghostty)
        if "${GROVE_KILL:-kill}" -USR2 "$pid" 2>/dev/null; then
          n=$((n + 1))
        else
          rc=1
        fi
        ;;
    esac
  done < <("${GROVE_PS:-ps}" -axo pid=,comm= 2>/dev/null)
  if [ "$rc" -ne 0 ]; then
    _gt_line ghostty failed "could not signal Ghostty; press cmd-shift-, in Ghostty to reload"
    return 1
  fi
  if [ "$n" -eq 0 ]; then
    _gt_line ghostty live "not running"
  else
    _gt_line ghostty live "reloaded $n process(es)"
  fi
}

gt_step_zsh() {
  _gt_line zsh next-prompt "the precmd hook re-sources the colours"
}

gt_step_static() {
  _gt_line starship live "read on every prompt"
  _gt_line eza live "read on every run"
  _gt_line bat live "read on every run"
  _gt_line fastfetch live "read on every run"
  _gt_line vscode live "watches its settings"
}

# gt_step_chrome: Chrome's profile can't be read without Full Disk Access, so
# this only checks that the theme was rendered. Chrome compiles the theme into
# "Cached Theme.pak" in the theme folder and reuses it at every start, whatever
# the manifest says; removing it makes Chrome rebuild from the new colours.
gt_step_chrome() {
  rm -f "${GROVE_ROOT:?}/config/chrome-theme/Cached Theme.pak"
  if [ ! -d "${GROVE_CHROME_APP:-/Applications/Google Chrome.app}" ]; then
    _gt_line chrome live "Chrome not installed"
  elif [ -f "${GROVE_ROOT:?}/config/chrome-theme/manifest.json" ]; then
    _gt_line chrome next-launch "Chrome takes the new colours the next time it starts (load ~/.config/chrome-theme once in chrome://extensions if you haven't)"
  else
    _gt_line chrome failed "the Chrome theme wasn't rendered"
    return 1
  fi
}

gt_step_yazi() {
  _gt_line yazi next-launch "read at launch"
}

# gt_step_appearance SCHEME
gt_step_appearance() {
  local want=true
  case "$1" in light-*) want=false ;; esac
  if osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $want" >/dev/null 2>&1; then
    _gt_line appearance live "dark mode $want"
  else
    _gt_line appearance needs-you "$GT_AUTOMATION_HINT"
    return 1
  fi
}

# gt_step_accent SCHEME: green accent, highlight from bg_visual.
gt_step_accent() {
  local hex rgb
  hex="$(gt_values "$1" "${GROVE_ROOT:?}/theme" | sed -n 's/^bg_visual	#\(......\)$/\1/p')"
  if [ -z "$hex" ]; then
    _gt_line accent failed "no bg_visual in the $1 palette"
    return 1
  fi
  rgb="$(awk -v r=$((16#${hex:0:2})) -v g=$((16#${hex:2:2})) -v b=$((16#${hex:4:2})) \
    'BEGIN { printf "%.6f %.6f %.6f Other", r / 255, g / 255, b / 255 }')"
  if defaults write -g AppleAccentColor -int 3 >/dev/null 2>&1 \
    && defaults write -g AppleHighlightColor -string "$rgb" >/dev/null 2>&1; then
    _gt_line accent live "green accent, highlight $rgb; open apps pick it up when they redraw or relaunch"
  else
    _gt_line accent failed "defaults write failed"
    return 1
  fi
}

# _gt_copy_backup FILE: cp -p FILE to $GROVE_STATE/backup/$GROVE_RUN_ID/<path
# relative to $HOME, or absolute minus the "/">, with a ".N" suffix when that
# exists (as grove_backup does). Prints the backup path; FILE stays in place.
_gt_copy_backup() {
  local src="$1" rel dest n=0
  case "$src" in
    "${HOME%/}"/*) rel="${src#"${HOME%/}"/}" ;;
    *) rel="${src#/}" ;;
  esac
  dest="${GROVE_STATE:?}/backup/${GROVE_RUN_ID:-$(date +%Y%m%d-%H%M%S)}/$rel"
  while [ -e "$dest" ] || [ -L "$dest" ]; do
    n=$((n + 1))
    dest="${GROVE_STATE}/backup/${GROVE_RUN_ID:-$(date +%Y%m%d-%H%M%S)}/$rel.$n"
  done
  mkdir -p "$(dirname "$dest")" && cp -p "$src" "$dest" && printf '%s\n' "$dest"
}

# gt_step_wallpaper SCHEME: the scheme's picture on every screen and Space.
# osascript changes the visible Spaces at once; the rest live in macOS's
# wallpaper store, which wallpaper_store.py rewrites (backed up first) before
# WallpaperAgent is force-stopped (-KILL: a normal quit saves its in-memory
# copy over ours) and launchd restarts it. Seams: GROVE_WALLPAPER_STORE,
# GROVE_KILLALL.
gt_step_wallpaper() {
  local dir file store lib msg backup
  dir="${GROVE_WALLPAPER_DIR:-${GROVE_ROOT:?}/../grove-wallpapers}"
  file="$dir/wallpaper-project-grove-$1.png"
  store="${GROVE_WALLPAPER_STORE:-$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist}"
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ ! -r "$file" ]; then
    _gt_line wallpaper failed "wallpaper not found: $file"
    return 1
  fi
  if ! osascript - "$file" >/dev/null 2>&1 <<'OSA'
on run argv
  tell application "System Events" to set picture of every desktop to POSIX file (item 1 of argv)
end run
OSA
  then
    _gt_line wallpaper needs-you "$GT_AUTOMATION_HINT"
    return 1
  fi
  if [ ! -f "$store" ]; then
    _gt_line wallpaper live "$1 on the visible Spaces; other Spaces couldn't be updated: no wallpaper store at $store"
    return 0
  fi
  # Copy (never move) the store into the backup folder, where grove_backup
  # would put it, so the helper's atomic replace is the only change to it.
  if ! backup="$(_gt_copy_backup "$store")"; then
    _gt_line wallpaper live "$1 on the visible Spaces; other Spaces couldn't be updated: could not back up the wallpaper store"
    return 0
  fi
  if msg="$(/usr/bin/python3 -I "$lib/wallpaper_store.py" "$store" "$file" 2>&1)"; then
    "${GROVE_KILLALL:-killall}" -KILL WallpaperAgent >/dev/null 2>&1 || true
    _gt_line wallpaper live "$1 on every Space"
  else
    _gt_line wallpaper live "$1 on the visible Spaces; other Spaces couldn't be updated: $(printf '%s' "$msg" | tr '\n\t' '  ') (backup: $backup)"
  fi
}
