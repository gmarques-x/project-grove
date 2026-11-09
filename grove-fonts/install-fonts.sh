#!/bin/bash
#
# Project Grove · font installer
#
# Installs every font listed in FONTS below, plus any font files you drop into
# grove-fonts/local/, into ~/Library/Fonts (current user, no sudo needed), then
# registers them with macOS so apps can use them right away.
#
# Uses only tools that ship with macOS (curl, unzip, shasum, pkgutil, diskutil,
# osascript), so it runs on a fresh Mac before Command Line Tools or Homebrew.
#
# Usage:
#   install-fonts.sh            install anything missing or changed
#   install-fonts.sh --dry-run  show what would happen, change nothing
#   install-fonts.sh --check    report whether everything is installed; change nothing
#   install-fonts.sh --force    reinstall every file, even if identical
#   install-fonts.sh --quiet    print only errors and the final summary line
#   install-fonts.sh --list     list the configured fonts and exit
#   install-fonts.sh --help
#
# Exit codes (for callers such as the grove-dotfiles installer):
#   0  everything is installed and active
#   1  one or more errors (download, verification, copy or registration)
#   2  bad arguments, or not running on macOS
#   3  --check only: some fonts are missing or out of date
#
# Can be called from any directory, by path: bash /path/to/install-fonts.sh

set -euo pipefail

# ---------------------------------------------------------------------------
# FONTS: one entry per line, four fields separated by "|":
#
#   name     a label for the output
#   url      a .zip archive, a .dmg or .pkg installer, or a single .ttf / .otf
#   verify   how to check the download:
#              <sha256>      exact checksum (curl -sL <url> | shasum -a 256)
#              apple-signed  .dmg / .pkg only: the package must be signed by Apple.
#                            Use this for Apple fonts, which Apple updates in place.
#              (empty)       no check; a warning is printed
#   pattern  which files to install (shell glob, "*" also matches "/"):
#              .zip          relative to the archive root
#              .dmg / .pkg   relative to the expanded package
#              .ttf / .otf   ignored
#            Only .ttf and .otf files are ever installed.
#
# To add a font, add a line. Example:
#   "Inter|https://example.com/Inter.zip|<sha256>|Inter/*.ttf"
# ---------------------------------------------------------------------------
FONTS=(
  # Principal font: monospace for terminal, editor and code.
  "JetBrains Mono 2.304|https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip|6f6376c6ed2960ea8a963cd7387ec9d76e3f629125bc33d1fdcd7eb7012f7bbf|fonts/ttf/*.ttf"
  # Companion font: SF Pro, SF Pro Text, SF Pro Display, SF Pro Rounded (Apple license).
  "SF Pro|https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg|apple-signed|*.pkg/Payload/Library/Fonts/*"
)

DEST="$HOME/Library/Fonts"
CACHE_DIR="${GROVE_FONTS_CACHE:-$HOME/Library/Caches/grove-fonts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$SCRIPT_DIR/local"
REGISTER_JS="$SCRIPT_DIR/lib/register-fonts.js"

DRY_RUN=0; CHECK=0; FORCE=0; QUIET=0

usage() { sed -n '3,27p' "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --check)   CHECK=1; DRY_RUN=1 ;;
    --force)   FORCE=1 ;;
    --quiet)   QUIET=1 ;;
    --list)
      for entry in "${FONTS[@]}"; do echo "${entry%%|*}"; done
      [ -d "$LOCAL_DIR" ] && find "$LOCAL_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' \) -exec basename {} \; | sed 's/^/local: /'
      exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "install-fonts: unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "install-fonts: this script only runs on macOS" >&2; exit 2
fi

if [ -t 1 ]; then
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
ok()   { [ "$QUIET" -eq 1 ] || printf '  %s+%s %s\n' "$GREEN" "$RESET" "$*"; }
skip() { [ "$QUIET" -eq 1 ] || printf '  %s= %s%s\n' "$DIM" "$*" "$RESET"; }
warn() { [ "$QUIET" -eq 1 ] || printf '  %s! %s%s\n' "$YELLOW" "$*" "$RESET"; }
fail() { printf '  %sx %s%s\n' "$RED" "$*" "$RESET" >&2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/grove-fonts.XXXXXX")"
MOUNTS="$TMP/mounts.txt"; : > "$MOUNTS"
cleanup() {
  # Eject any disk image still mounted, then remove the work folder.
  while IFS= read -r m; do
    [ -n "$m" ] && { diskutil eject "$m" >/dev/null 2>&1 || hdiutil detach -force "$m" >/dev/null 2>&1 || true; }
  done < "$MOUNTS"
  rm -rf "$TMP"
}
trap cleanup EXIT
MANAGED="$TMP/managed.txt"   # every font file this run is responsible for
: > "$MANAGED"

installed=0; unchanged=0; errors=0

# Download url into the cache. Re-downloads only when the server has a newer file.
fetch() {
  local url="$1" dest="$2" part="$2.part"
  mkdir -p "$CACHE_DIR"
  rm -f "$part"
  if [ -s "$dest" ]; then
    curl -fsSL --retry 2 -R -z "$dest" -o "$part" "$url" || return 1
  else
    curl -fsSL --retry 2 -R -o "$part" "$url" || return 1
  fi
  if [ -s "$part" ]; then mv -f "$part" "$dest"; else rm -f "$part"; fi
  [ -s "$dest" ]
}

# Mount a .dmg read-only and print the mount point.
mount_dmg() {
  local dmg="$1" mnt="$2"
  mkdir -p "$mnt"
  if diskutil image attach --help >/dev/null 2>&1; then
    diskutil image attach --mountOptions nobrowse --readOnly --mountPoint "$mnt" "$dmg" >/dev/null 2>&1 || return 1
  else
    hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$dmg" >/dev/null 2>&1 || return 1
  fi
  echo "$mnt" >> "$MOUNTS"
}

# Check that a .pkg is signed by Apple.
apple_signed() {
  pkgutil --check-signature "$1" 2>/dev/null | grep -q 'Status: signed Apple Software'
}

# Copy one font file into DEST unless an identical copy is already there.
install_file() {
  local src="$1" name target
  name="$(basename "$src")"
  target="$DEST/$name"
  echo "$target" >> "$MANAGED"
  if [ "$FORCE" -eq 0 ] && [ -f "$target" ] && cmp -s "$src" "$target"; then
    skip "$name (already installed)"
    unchanged=$((unchanged + 1))
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    ok "$name (would install)"
  elif cp "$src" "$target"; then
    ok "$name"
  else
    fail "Could not copy $name to $DEST"
    errors=$((errors + 1)); return
  fi
  installed=$((installed + 1))
}

# Install every .ttf/.otf under root whose path matches the entry's pattern.
install_matching() {
  local root="$1" pattern="$2" name="$3" found=0 font
  while IFS= read -r font; do
    found=1
    install_file "$font"
  done < <(find "$root" -type f -path "$root/$pattern" \( -iname '*.ttf' -o -iname '*.otf' \) | sort)
  if [ "$found" -eq 0 ]; then
    fail "$name: no font files matched pattern '$pattern'"
    errors=$((errors + 1))
  fi
}

[ "$DRY_RUN" -eq 1 ] && [ "$CHECK" -eq 0 ] && say "Dry run: nothing will be changed."
[ "$DRY_RUN" -eq 1 ] || mkdir -p "$DEST"

i=0
for entry in "${FONTS[@]}"; do
  i=$((i + 1))
  IFS='|' read -r name url verify pattern <<EOF
$entry
EOF
  say ""
  say "$name"

  work="$TMP/$i"
  mkdir -p "$work"
  file="$CACHE_DIR/$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')-$(basename "${url%%\?*}")"

  if ! fetch "$url" "$file"; then
    fail "$name: download failed: $url"
    errors=$((errors + 1)); continue
  fi

  case "$verify" in
    "") warn "No verification set for this entry, download not checked" ;;
    apple-signed) ;;  # checked on the package below
    *)
      actual="$(shasum -a 256 "$file" | awk '{print $1}')"
      if [ "$actual" != "$verify" ]; then
        rm -f "$file"   # drop the bad copy so the next run downloads it again
        fail "$name: checksum mismatch, skipped. Expected $verify, got $actual"
        errors=$((errors + 1)); continue
      fi ;;
  esac

  case "$file" in
    *.zip|*.ZIP)
      [ "$verify" = "apple-signed" ] && { fail "$name: apple-signed only works for .dmg and .pkg"; errors=$((errors + 1)); continue; }
      unzip -q "$file" -d "$work/x"
      install_matching "$work/x" "$pattern" "$name"
      ;;
    *.dmg|*.DMG|*.pkg|*.PKG)
      pkg="$file"
      case "$file" in
        *.dmg|*.DMG)
          if ! mount_dmg "$file" "$work/mnt"; then
            fail "$name: could not mount disk image"; errors=$((errors + 1)); continue
          fi
          pkg="$(find "$work/mnt" -maxdepth 1 -name '*.pkg' | head -1)"
          if [ -z "$pkg" ]; then
            fail "$name: no installer package found in disk image"; errors=$((errors + 1)); continue
          fi ;;
      esac
      if [ "$verify" = "apple-signed" ] && ! apple_signed "$pkg"; then
        fail "$name: package is not signed by Apple, skipped"
        errors=$((errors + 1)); continue
      fi
      # Unpack the package's files without running its installer (no admin rights needed).
      if ! pkgutil --expand-full "$pkg" "$work/x" >/dev/null 2>&1; then
        fail "$name: could not unpack installer package"; errors=$((errors + 1)); continue
      fi
      install_matching "$work/x" "$pattern" "$name"
      ;;
    *.ttf|*.otf|*.TTF|*.OTF)
      install_file "$file" ;;
    *)
      fail "$name: unsupported download type $(basename "$file") (use .zip, .dmg, .pkg, .ttf or .otf)"
      errors=$((errors + 1)) ;;
  esac
done

if [ -d "$LOCAL_DIR" ]; then
  locals="$(find "$LOCAL_DIR" -type f \( -iname '*.ttf' -o -iname '*.otf' \) | sort)"
  if [ -n "$locals" ]; then
    say ""
    say "Local fonts (grove-fonts/local)"
    while IFS= read -r font; do install_file "$font"; done <<EOF
$locals
EOF
  fi
fi

# Register the fonts with macOS. Copying into ~/Library/Fonts alone does not
# always make a font available straight away, so register explicitly and then
# confirm every PostScript name is active. In --check mode, only confirm.
files=()
while IFS= read -r f; do [ -f "$f" ] && files+=("$f"); done < <(sort -u "$MANAGED")

inactive=0
if [ "$DRY_RUN" -eq 0 ] && [ "${#files[@]}" -gt 0 ]; then
  say ""
  say "Registering with macOS"
  if result="$(osascript -l JavaScript "$REGISTER_JS" "${files[@]}" 2>&1)"; then
    missing="$(echo "$result" | sed -n 's/.*missing=\([0-9]*\).*/\1/p')"
    checked="$(echo "$result" | sed -n 's/.*checked=\([0-9]*\).*/\1/p')"
    if [ "${missing:-1}" -eq 0 ]; then
      ok "$checked font face(s) active"
    else
      fail "Not active after registering: ${result#*missing=* }"
      errors=$((errors + 1))
    fi
  else
    fail "Registration helper failed: $result"
    errors=$((errors + 1))
  fi
elif [ "$CHECK" -eq 1 ] && [ "${#files[@]}" -gt 0 ]; then
  result="$(osascript -l JavaScript "$REGISTER_JS" --verify "${files[@]}" 2>&1 || true)"
  case "$result" in *missing=0*) ;; *) inactive=1 ;; esac
fi

say ""
if [ "$CHECK" -eq 1 ]; then
  if [ "$errors" -gt 0 ]; then
    echo "install-fonts: check failed with $errors error(s)."; exit 1
  elif [ "$installed" -gt 0 ]; then
    echo "install-fonts: $installed font file(s) missing or out of date. Run install-fonts.sh to fix."; exit 3
  elif [ "$inactive" -eq 1 ]; then
    echo "install-fonts: fonts are installed but not active. Run install-fonts.sh to register them."; exit 3
  fi
  echo "install-fonts: all $unchanged font file(s) installed and active."; exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "install-fonts: would install $installed file(s); $unchanged already up to date; $errors error(s)."
else
  echo "install-fonts: installed $installed file(s) to $DEST; $unchanged already up to date; $errors error(s)."
  [ "$installed" -gt 0 ] && say "Restart open apps (terminal, editor) to pick up new fonts."
fi
[ "$errors" -eq 0 ]
