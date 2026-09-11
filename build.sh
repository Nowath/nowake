#!/bin/bash
# Builds nowake.app and installs it into ~/Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/nowake.app"
INSTALL_DIR="$HOME/Applications"

cd "$ROOT"

echo "==> Compiling"
swift build -c release

echo "==> Assembling the .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/nowake" "$APP/Contents/MacOS/nowake"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>nowake</string>
	<key>CFBundleDisplayName</key>
	<string>nowake</string>
	<key>CFBundleIdentifier</key>
	<string>com.nowath.nowake</string>
	<key>CFBundleExecutable</key>
	<string>nowake</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing"
codesign --force --sign - --timestamp=none "$APP"

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
pkill -x nowake 2>/dev/null || true
rm -rf "$INSTALL_DIR/nowake.app"
cp -R "$APP" "$INSTALL_DIR/nowake.app"

echo "Done: $INSTALL_DIR/nowake.app"
