#!/usr/bin/env bash
# Builds "QuadCast Control.app". Pass --install to copy it into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="QuadCast Control"
EXECUTABLE="QuadCastControl"
APP="build/${APP_NAME}.app"

echo "Compiling…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "Bundling…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>        <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>         <string>local.quadcast-control</string>
    <key>CFBundleExecutable</key>         <string>${EXECUTABLE}</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will run it locally.
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/${APP_NAME}.app"
    open "/Applications/${APP_NAME}.app"
else
    echo "Built: $APP"
    echo "Run it with:  open \"$APP\""
fi
