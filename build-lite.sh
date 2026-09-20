#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
developer_dir="${CLT_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
swiftc="$developer_dir/usr/bin/swiftc"
sdk="$developer_dir/SDKs/MacOSX.sdk"

if [[ ! -x "$swiftc" || ! -d "$sdk" ]]; then
  echo "Apple Command Line Tools not found." >&2
  echo "Install them with: xcode-select --install" >&2
  exit 1
fi

# Keep compiler subprocesses and Apple's /usr/bin shims on the same toolchain.
# This does not change the user's global xcode-select setting.
export DEVELOPER_DIR="$developer_dir"

build_root="$project_dir/build/lite"
case "$build_root" in
  "$project_dir"/build/lite) ;;
  *) echo "Unexpected build path" >&2; exit 1 ;;
esac
rm -rf "$build_root"

app="$build_root/Clash Meta Switch.app"
appex="$app/Contents/PlugIns/MetaSwitch.appex"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$appex/Contents/MacOS" "$appex/Contents/Resources"

cd "$project_dir/native"
python3 generate_project.py

for arch in arm64 x86_64; do
  "$swiftc" -sdk "$sdk" -target "$arch-apple-macos14.0" -swift-version 5 -O -parse-as-library \
    Host.swift Intent.swift ProxyState.swift Bridge.swift Core.swift \
    -o "$build_root/host-$arch" \
    -framework SwiftUI -framework WidgetKit -framework AppKit -framework SystemConfiguration -framework Security

  "$swiftc" -sdk "$sdk" -target "$arch-apple-macos14.0" -swift-version 5 -O -parse-as-library -DWIDGET_EXTENSION \
    Widget.swift Bridge.swift \
    -o "$build_root/widget-$arch" \
    -framework SwiftUI -framework WidgetKit -framework Security
done

lipo -create "$build_root/host-arm64" "$build_root/host-x86_64" -output "$app/Contents/MacOS/Clash Meta Switch"
lipo -create "$build_root/widget-arm64" "$build_root/widget-x86_64" -output "$appex/Contents/MacOS/MetaSwitch"

cp Host-Info.plist "$app/Contents/Info.plist"
cp Widget-Info.plist "$appex/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "Clash Meta Switch" "$app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "local.clash.metaswitch" "$app/Contents/Info.plist"
plutil -replace CFBundleName -string "Clash Meta Switch" "$app/Contents/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "MetaSwitch" "$appex/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "local.clash.metaswitch.widget" "$appex/Contents/Info.plist"
plutil -replace CFBundleName -string "MetaSwitch" "$appex/Contents/Info.plist"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$appex/Contents/Info.plist"

codesign --force --sign - --options runtime --entitlements Widget.entitlements "$appex"
codesign --force --sign - --options runtime --entitlements Host.entitlements "$app"
codesign --verify --deep --strict "$app"
lipo "$app/Contents/MacOS/Clash Meta Switch" -verify_arch arm64 x86_64
lipo "$appex/Contents/MacOS/MetaSwitch" -verify_arch arm64 x86_64

cd "$project_dir"
"$swiftc" -sdk "$sdk" -swift-version 5 native/Bridge.swift native/ProxyState.swift native/Core.swift tests/main.swift \
  -o "$build_root/security-checks" -framework SystemConfiguration -framework Security
"$build_root/security-checks"

echo "$app"
