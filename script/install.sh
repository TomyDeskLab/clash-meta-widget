#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_kind="${1:-lite}"
if [[ "$build_kind" == "--xcode" ]]; then
  bash "$project_dir/build.sh"
  source_app="$project_dir/build/native/Build/Products/Release/Clash Meta Switch.app"
elif [[ "$build_kind" == "--skip-build" ]]; then
  source_app="$project_dir/build/lite/Clash Meta Switch.app"
elif [[ "$build_kind" == "--skip-xcode-build" ]]; then
  source_app="$project_dir/build/native/Build/Products/Release/Clash Meta Switch.app"
else
  bash "$project_dir/build-lite.sh"
  source_app="$project_dir/build/lite/Clash Meta Switch.app"
fi
target_app="/Applications/Clash Meta Switch.app"
if [[ ! -d "$source_app" ]]; then
  echo "Build product not found: $source_app" >&2
  exit 1
fi

pkill -x "Clash Meta Switch" 2>/dev/null || true
pkill -x "MetaSwitch" 2>/dev/null || true

if [[ -d "$target_app" ]]; then
  backup_app="$HOME/.Trash/Clash Meta Switch.backup-$(date +%Y%m%d-%H%M%S).app"
  mv "$target_app" "$backup_app"
  echo "Previous version saved at: $backup_app"
fi

ditto "$source_app" "$target_app"
codesign --verify --deep --strict "$target_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$target_app"
pluginkit -a "$target_app/Contents/PlugIns/MetaSwitch.appex"
open "$target_app"
echo "Installed: $target_app"
