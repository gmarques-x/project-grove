# shellcheck shell=bash
# 30-fonts: the fonts in fonts.txt, plus any font files in local/, installed
# into ~/Library/Fonts (no sudo) and registered with macOS so apps see them now.
#
# Uses only tools that ship with macOS (curl, unzip, shasum, pkgutil, diskutil,
# osascript). Downloads are cached in ~/Library/Caches/grove/fonts and fetched
# again only when the server has a newer file.

about() { echo "JetBrains Mono, SF Pro and your own fonts"; }

check() { ( _fonts_sync check ); }
apply() { ( _fonts_sync apply ); }

_fonts_dir() { echo "${MODULE_DIR:-$GROVE_ROOT/modules/30-fonts}"; }

# _fonts_sync check|apply. check changes nothing in ~/Library/Fonts and returns
# 0 when every font is installed and active, 3 when not, 1 on errors.
# Runs in a subshell (see check/apply), so its EXIT trap and variables stay local.
_fonts_sync() {
  local mode="$1" dir list local_dir register dest cache tmp
  dir="$(_fonts_dir)"
  list="${GROVE_FONTS_LIST:-$dir/fonts.txt}"
  local_dir="${GROVE_FONTS_LOCAL:-$dir/local}"
  register="$dir/register-fonts.js"
  dest="$HOME/Library/Fonts"
  cache="${GROVE_FONTS_CACHE:-$HOME/Library/Caches/grove/fonts}"

  [ -f "$list" ] || { grove_fail "font list not found: $list"; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/grove-fonts.XXXXXX")" || return 1
  _F_MOUNTS="$tmp/mounts.txt"; : > "$_F_MOUNTS"
  _F_MANAGED="$tmp/managed.txt"; : > "$_F_MANAGED"
  # shellcheck disable=SC2064
  trap "_fonts_cleanup '$tmp'" EXIT
  _F_MODE="$mode"; _F_DEST="$dest"
  _F_CHANGED=0; _F_SAME=0; _F_ERRORS=0

  [ "$mode" = "apply" ] && mkdir -p "$dest"

  local i=0 line name url verify pattern work file actual pkg
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    IFS='|' read -r name url verify pattern <<EOF
$line
EOF
    i=$((i + 1))
    [ "$mode" = "apply" ] && grove_info "$name"
    work="$tmp/$i"; mkdir -p "$work"
    file="$cache/$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')-$(basename "${url%%\?*}")"

    if ! _fonts_fetch "$url" "$file"; then
      grove_fail "$name: download failed: $url"; _F_ERRORS=$((_F_ERRORS + 1)); continue
    fi
    case "$verify" in
      "") grove_info "  ! no verification set for $name; download not checked" ;;
      apple-signed) ;;  # checked on the package below
      *)
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
        if [ "$actual" != "$verify" ]; then
          rm -f "$file"   # drop the bad copy so the next run downloads it again
          grove_fail "$name: checksum mismatch, skipped. Expected $verify, got $actual"
          _F_ERRORS=$((_F_ERRORS + 1)); continue
        fi ;;
    esac

    case "$file" in
      *.zip|*.ZIP)
        if [ "$verify" = "apple-signed" ]; then
          grove_fail "$name: apple-signed only works for .dmg and .pkg"; _F_ERRORS=$((_F_ERRORS + 1)); continue
        fi
        unzip -q "$file" -d "$work/x" || { grove_fail "$name: could not unzip"; _F_ERRORS=$((_F_ERRORS + 1)); continue; }
        _fonts_install_matching "$work/x" "$pattern" "$name" ;;
      *.dmg|*.DMG|*.pkg|*.PKG)
        pkg="$file"
        case "$file" in
          *.dmg|*.DMG)
            if ! _fonts_mount "$file" "$work/mnt"; then
              grove_fail "$name: could not mount disk image"; _F_ERRORS=$((_F_ERRORS + 1)); continue
            fi
            pkg="$(find "$work/mnt" -maxdepth 1 -name '*.pkg' | head -1)"
            if [ -z "$pkg" ]; then
              grove_fail "$name: no installer package found in disk image"; _F_ERRORS=$((_F_ERRORS + 1)); continue
            fi ;;
        esac
        if [ "$verify" = "apple-signed" ] && ! pkgutil --check-signature "$pkg" 2>/dev/null | grep -q 'Status: signed Apple Software'; then
          grove_fail "$name: package is not signed by Apple, skipped"; _F_ERRORS=$((_F_ERRORS + 1)); continue
        fi
        # Unpack the package's files without running its installer (no admin rights needed).
        if ! pkgutil --expand-full "$pkg" "$work/x" >/dev/null 2>&1; then
          grove_fail "$name: could not unpack installer package"; _F_ERRORS=$((_F_ERRORS + 1)); continue
        fi
        _fonts_install_matching "$work/x" "$pattern" "$name" ;;
      *.ttf|*.otf|*.TTF|*.OTF)
        _fonts_install_file "$file" "$(basename "${url%%\?*}")" ;;
      *)
        grove_fail "$name: unsupported download type $(basename "$file") (use .zip, .dmg, .pkg, .ttf or .otf)"
        _F_ERRORS=$((_F_ERRORS + 1)) ;;
    esac
  done < "$list"

  if [ -d "$local_dir" ]; then
    local font
    while IFS= read -r font; do
      [ -n "$font" ] && _fonts_install_file "$font"
    done <<EOF
$(find "$local_dir" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | sort)
EOF
  fi

  # Copying into ~/Library/Fonts alone doesn't always make a font available
  # straight away, so register explicitly and confirm every PostScript name is
  # active. check only confirms.
  local files=() f result inactive=0
  while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(sort -u "$_F_MANAGED")
  if [ "${#files[@]}" -gt 0 ]; then
    if [ "$mode" = "apply" ]; then
      result="$(osascript -l JavaScript "$register" "${files[@]}" 2>&1)" || {
        grove_fail "font registration helper failed: $result"; return 1; }
    else
      result="$(osascript -l JavaScript "$register" --verify "${files[@]}" 2>&1)" || result="missing=?"
    fi
    case "$result" in
      *missing=0*) ;;
      *)
        if [ "$mode" = "apply" ]; then
          grove_fail "not active after registering: ${result#*missing=}"; _F_ERRORS=$((_F_ERRORS + 1))
        else
          inactive=1
        fi ;;
    esac
  fi

  [ "$_F_ERRORS" -eq 0 ] || return 1
  if [ "$mode" = "check" ]; then
    { [ "$_F_CHANGED" -gt 0 ] || [ "$inactive" -eq 1 ]; } && return 3
    return 0
  fi
  grove_info "fonts: installed $_F_CHANGED file(s), $_F_SAME already up to date"
  [ "$_F_CHANGED" -gt 0 ] && grove_info "restart open apps (terminal, editor) to pick up new fonts"
  return 0
}

_fonts_cleanup() {
  local m
  # Eject any disk image still mounted, then remove the work folder.
  while IFS= read -r m; do
    [ -n "$m" ] && { diskutil eject "$m" >/dev/null 2>&1 || hdiutil detach -force "$m" >/dev/null 2>&1 || true; }
  done < "$1/mounts.txt"
  rm -rf "$1"
}

# _fonts_fetch URL DEST: download into the cache; re-downloads only when the
# server has a newer file.
_fonts_fetch() {
  local url="$1" dest="$2" part="$2.part"
  mkdir -p "$(dirname "$dest")"
  rm -f "$part"
  if [ -s "$dest" ]; then
    curl -fsSL --retry 2 -R -z "$dest" -o "$part" "$url" || return 1
  else
    curl -fsSL --retry 2 -R -o "$part" "$url" || return 1
  fi
  if [ -s "$part" ]; then mv -f "$part" "$dest"; else rm -f "$part"; fi
  [ -s "$dest" ]
}

# _fonts_mount DMG DIR: mount a disk image read-only at DIR.
_fonts_mount() {
  mkdir -p "$2"
  if diskutil image attach --help >/dev/null 2>&1; then
    diskutil image attach --mountOptions nobrowse --readOnly --mountPoint "$2" "$1" >/dev/null 2>&1 || return 1
  else
    hdiutil attach -nobrowse -readonly -mountpoint "$2" "$1" >/dev/null 2>&1 || return 1
  fi
  echo "$2" >> "$_F_MOUNTS"
}

# _fonts_install_matching ROOT PATTERN NAME: every .ttf/.otf under ROOT whose
# path matches PATTERN.
_fonts_install_matching() {
  local root="$1" pattern="$2" name="$3" found=0 font
  while IFS= read -r font; do
    found=1
    _fonts_install_file "$font"
  done < <(find "$root" -type f -path "$root/$pattern" \( -iname '*.ttf' -o -iname '*.otf' \) | sort)
  if [ "$found" -eq 0 ]; then
    grove_fail "$name: no font files matched pattern '$pattern'"; _F_ERRORS=$((_F_ERRORS + 1))
  fi
}

# _fonts_install_file SRC [NAME]: copy into ~/Library/Fonts as NAME (default:
# SRC's own name) unless an identical copy is already there. check only counts
# what would change.
_fonts_install_file() {
  local src="$1" name="${2:-}" target
  [ -n "$name" ] || name="$(basename "$src")"
  target="$_F_DEST/$name"
  echo "$target" >> "$_F_MANAGED"
  if [ -f "$target" ] && cmp -s "$src" "$target"; then
    _F_SAME=$((_F_SAME + 1)); return 0
  fi
  _F_CHANGED=$((_F_CHANGED + 1))
  [ "$_F_MODE" = "apply" ] || return 0
  if cp "$src" "$target"; then
    grove_info "  + $name"
  else
    grove_fail "could not copy $name to $_F_DEST"; _F_ERRORS=$((_F_ERRORS + 1))
  fi
}
