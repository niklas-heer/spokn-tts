#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/scripts/build-native.sh" release
installed="/Applications/Spokn.app"
if [[ -d "$installed" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$installed/Contents/Info.plist")"
  [[ "$identifier" == com.niklasheer.spokn ]] || { echo 'A different app occupies /Applications/Spokn.app' >&2; exit 1; }
fi
staging="$(mktemp -d /Applications/.Spokn-install.XXXXXX)"
trap 'rm -rf "$staging"' EXIT
ditto "$root/build/native/Spokn.app" "$staging/Spokn.app"
codesign --verify --deep --strict "$staging/Spokn.app"
backup="$root/build/native/Previous-Spokn-$(date +%Y%m%d-%H%M%S).app"
if [[ -d "$installed" ]]; then mv "$installed" "$backup"; fi
if ! mv "$staging/Spokn.app" "$installed"; then
  if [[ -d "$backup" ]]; then mv "$backup" "$installed"; fi
  exit 1
fi
echo "Installed $installed (previous version preserved in build/native)"
