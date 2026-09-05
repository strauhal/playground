#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="release"
app_dir="$project_dir/dist/Pix2Pix Studio.app"
contents="$app_dir/Contents"

cd "$project_dir"
swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"

mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$binary_dir/Pix2PixStudio" "$contents/MacOS/Pix2PixStudio"
cp "$project_dir/Resources/Info.plist" "$contents/Info.plist"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
