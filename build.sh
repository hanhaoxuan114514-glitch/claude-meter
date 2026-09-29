#!/bin/bash
# 编译并打包 ClaudeMeter.app
# 用法：./build.sh            仅编译打包到当前目录
#       ./build.sh --install  编译后安装到 /Applications

set -euo pipefail
cd "$(dirname "$0")"

APP="ClaudeMeter.app"
BIN="ClaudeMeter"

echo "==> 编译"
rm -rf "$APP" "$BIN"
swiftc -O -parse-as-library -o "$BIN" main.swift \
    -framework SwiftUI -framework AppKit -framework Security

echo "==> 打包 $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$BIN" "$APP/Contents/MacOS/$BIN"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>       <string>ClaudeMeter</string>
    <key>CFBundleIdentifier</key>       <string>local.claudemeter</string>
    <key>CFBundleName</key>             <string>ClaudeMeter</string>
    <key>CFBundleDisplayName</key>      <string>ClaudeMeter</string>
    <key>CFBundlePackageType</key>      <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>          <string>1</string>
    <key>LSMinimumSystemVersion</key>   <string>13.0</string>
    <key>LSUIElement</key>              <true/>
    <key>NSHighResolutionCapable</key>  <true/>
</dict>
</plist>
PLIST

# 本地自签名（ad-hoc），避免每次重编后钥匙串重复询问
codesign --force --sign - "$APP" 2>/dev/null || true

echo "==> 完成：$PWD/$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> 安装到 /Applications"
    osascript -e 'quit app "ClaudeMeter"' 2>/dev/null || pkill -f "ClaudeMeter.app" 2>/dev/null || true
    sleep 1
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open -a ClaudeMeter
    echo "==> 已安装并启动"
fi
