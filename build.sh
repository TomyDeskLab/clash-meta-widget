#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
cd native
python3 generate_project.py
xcodebuild -project ClashMetaSwitch.xcodeproj -scheme ClashMetaSwitch -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath ../build/native build > ../build/native-build.log 2>&1
cd ..
codesign --verify --deep --strict 'build/native/Build/Products/Release/Clash Meta Switch.app'
xcrun swiftc native/Bridge.swift native/ProxyState.swift native/Core.swift tests/main.swift -o build/security-checks -framework SystemConfiguration -framework Security
build/security-checks
echo "$PWD/build/native/Build/Products/Release/Clash Meta Switch.app"
