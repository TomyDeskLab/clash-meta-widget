#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
case "${1:---xcode}" in
  --xcode)
    bash "$project_dir/build.sh"
    app="$project_dir/build/native/Build/Products/Release/Clash Meta Switch.app"
    ;;
  --app) app="${2:?Provide the verified app bundle path}" ;;
  *) echo "Usage: $0 [--xcode | --app /path/to/verified.app]" >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == "local.clash.metaswitch" ]]
lipo "$app/Contents/MacOS/Clash Meta Switch" -verify_arch arm64 x86_64
lipo "$app/Contents/PlugIns/MetaSwitch.appex/Contents/MacOS/MetaSwitch" -verify_arch arm64 x86_64
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
release_dir="$project_dir/build/release/build$build_number"
archive="$release_dir/Clash-Meta-Widget-$version-build$build_number-macos-universal.zip"

case "$release_dir" in
  "$project_dir"/build/release/build[0-9]*) ;;
  *) echo "Unexpected release path" >&2; exit 1 ;;
esac
mkdir -p "$release_dir"
if [[ -e "$archive" ]]; then
  echo "Archive already exists; preserve or move it before packaging again: $archive" >&2
  exit 1
fi

ditto -c -k --keepParent --sequesterRsrc "$app" "$archive"
cd "$release_dir"
shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt
cat SHA256SUMS.txt
