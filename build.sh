#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
output_dir="${1:-.build}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
stage="$(mktemp -d "$output_dir/.disk-space.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
app="$stage/Disk Space.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -swift-version 6 -target arm64-apple-macosx14.0 -O -parse-as-library \
    Core/*.swift App/*.swift -o "$app/Contents/MacOS/DiskSpace"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/*.lproj "$app/Contents/Resources/"
cp Resources/DiskSpace.icns "$app/Contents/Resources/"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
destination="$output_dir/Disk Space.app"
previous="$stage/Previous Disk Space.app"
if [[ -e "$destination" || -L "$destination" ]]; then
    mv "$destination" "$previous"
fi
if ! mv "$app" "$destination"; then
    if [[ -e "$previous" || -L "$previous" ]]; then mv "$previous" "$destination"; fi
    exit 1
fi
codesign --verify --strict "$destination"
echo "$destination"
