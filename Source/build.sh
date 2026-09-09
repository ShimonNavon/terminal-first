#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d /tmp/terminal-first-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Terminal First.app"
mkdir -p "$APP/Contents/MacOS"
cp Source/Info.plist "$APP/Contents/Info.plist"
SDK=$(xcrun --sdk macosx --show-sdk-path)
for ARCH in arm64 x86_64; do
    xcrun swiftc -swift-version 6 -warnings-as-errors -O -sdk "$SDK" \
        -target "$ARCH-apple-macosx13.0" -module-cache-path "$BUILD_DIR/ModuleCache" \
        Source/main.swift -o "$BUILD_DIR/TerminalFirst-$ARCH"
done
lipo -create "$BUILD_DIR/TerminalFirst-arm64" "$BUILD_DIR/TerminalFirst-x86_64" \
    -output "$APP/Contents/MacOS/TerminalFirst"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --keepParent "$APP" 'Terminal First App.zip'
