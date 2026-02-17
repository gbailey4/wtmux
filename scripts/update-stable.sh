#!/bin/bash
set -euo pipefail

STABLE_WORKTREE="$HOME/Development/wt-easy-stable"
APP_DEST="$HOME/Applications"
SCHEME="WTMux-Stable"

echo "==> Updating stable worktree from main..."
cd "$STABLE_WORKTREE"
git merge main

echo "==> Generating Xcode project..."
xcodegen generate

echo "==> Building $SCHEME (Release)..."
xcodebuild -project WTMux.xcodeproj -scheme "$SCHEME" -destination "platform=macOS" -configuration Release build 2>&1 | tail -5

# Find the built app in DerivedData
APP_PATH=$(xcodebuild -project WTMux.xcodeproj -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
APP_PATH="$APP_PATH/Stable.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Built app not found at $APP_PATH"
    exit 1
fi

echo "==> Copying Stable.app to $APP_DEST..."
mkdir -p "$APP_DEST"

# Quit the running app if it's open
if pgrep -f "Stable.app" > /dev/null 2>&1; then
    echo "==> Quitting running Stable app..."
    osascript -e 'quit app "Stable"'
    sleep 1
fi

rm -rf "$APP_DEST/Stable.app"
cp -R "$APP_PATH" "$APP_DEST/"

echo "==> Relaunching Stable..."
open "$APP_DEST/Stable.app"

echo "==> Done!"
