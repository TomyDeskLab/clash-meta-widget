#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
bash "$project_dir/build-lite.sh"

app="$project_dir/build/lite/Clash Meta Switch.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
release_dir="$project_dir/build/release"
archive="$release_dir/Clash-Meta-Widget-$version-build$build_number-macos-universal.zip"

case "$release_dir" in
  "$project_dir"/build/release) ;;
  *) echo "Unexpected release path" >&2; exit 1 ;;
esac
rm -rf "$release_dir"
mkdir -p "$release_dir"

ditto -c -k --keepParent --sequesterRsrc "$app" "$archive"
cd "$release_dir"
shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt
cat SHA256SUMS.txt
