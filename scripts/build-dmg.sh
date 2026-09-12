#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
bash "$root/scripts/build-native.sh" release
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
cp -R "$root/build/native/Spokn.app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Spokn -srcfolder "$staging" -ov -format UDZO "$root/build/native/Spokn.dmg"
