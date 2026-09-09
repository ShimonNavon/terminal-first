#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR=$(mktemp -d /tmp/terminal-first-build.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Terminal First.app"
mkdir -p "$APP/Contents/MacOS"
cp Source/Info.plist "$APP/Contents/Info.plist"
clang -fobjc-arc -Wall -Wextra -Wno-unused-parameter -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -framework Cocoa -framework Carbon -framework ServiceManagement Source/main.m -o "$APP/Contents/MacOS/TerminalFirst"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --keepParent "$APP" 'Terminal First App.zip'
