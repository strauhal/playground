#!/bin/zsh
set -e

cd "$(dirname "$0")"
swift build -c release

APP_DIR="$PWD/dist/Audio Reactive.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp .build/arm64-apple-macosx/release/AudioReactive "$APP_DIR/Contents/MacOS/AudioReactive"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/AudioReactive"

echo "Built: $APP_DIR"
