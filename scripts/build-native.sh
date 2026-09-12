#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
if [[ "$configuration" != debug && "$configuration" != release ]]; then
  echo 'Usage: scripts/build-native.sh [debug|release]' >&2
  exit 1
fi
swift build --package-path "$root" --configuration "$configuration"
bin_dir="$(swift build --package-path "$root" --configuration "$configuration" --show-bin-path)"
output_dir="$root/build/native"
mkdir -p "$output_dir"
staging="$(mktemp -d "$output_dir/.Spokn.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_dir="$staging/Spokn.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/Spokn" "$app_dir/Contents/MacOS/Spokn"
cp "$root/native/Info.plist" "$app_dir/Contents/Info.plist"
cp "$root/native/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
# SwiftPM resource bundles must travel with the executable.
for resource in "$bin_dir"/*.bundle; do
  [[ -d "$resource" ]] || continue
  cp -R "$resource" "$app_dir/Contents/Resources/"
done
cp "$root/native/Resources/ThirdPartyNotices.txt" "$app_dir/Contents/Resources/"
chmod +x "$app_dir/Contents/MacOS/Spokn"
codesign --force --sign - "$app_dir"
if [[ -d "$output_dir/Spokn.app" ]]; then
  mv "$output_dir/Spokn.app" "$staging/Previous.app"
fi
mv "$app_dir" "$output_dir/Spokn.app"
echo "Built $output_dir/Spokn.app"
