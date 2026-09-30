#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/prepare-defaults.sh
bundle="dist/Aemeath Startup.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/web/assets" .build/module-cache
swiftc -O -module-cache-path .build/module-cache Native/App.swift -o "$bundle/Contents/MacOS/AemeathStartup" -framework AppKit -framework WebKit
cp index.html style.css animation.js image-settings.js "$bundle/Contents/Resources/web/"
cp assets/artwork.jpg assets/avatar.jpg assets/contours.js "$bundle/Contents/Resources/web/assets/"
rm -f "$bundle/Contents/Resources/web/assets/aemeath.png" "$bundle/Contents/Resources/web/assets/avatar.png"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AemeathStartup</string>
<key>CFBundleIdentifier</key><string>local.aemeath.startup</string>
<key>CFBundleName</key><string>爱弥斯启动动画</string>
<key>CFBundleDisplayName</key><string>爱弥斯启动动画</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$bundle"
printf 'Built: %s\n' "$PWD/$bundle"
