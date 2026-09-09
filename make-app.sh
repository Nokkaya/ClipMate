#!/bin/bash
# 构建 ClipMate.app（release）并 ad-hoc 签名。
# 正式分发请替换为 Developer ID 签名 + notarytool 公证（见方案文档 §8）。
set -euo pipefail
cd "$(dirname "$0")"

echo "==> swift build -c release"
swift build -c release
BIN_PATH=$(swift build -c release --show-bin-path)

APP="dist/ClipMate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>ClipMate</string>
    <key>CFBundleDisplayName</key>        <string>ClipMate</string>
    <key>CFBundleIdentifier</key>         <string>com.clipmate.app</string>
    <key>CFBundleExecutable</key>         <string>ClipMate</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundleShortVersionString</key> <string>0.2.0</string>
    <key>CFBundleVersion</key>            <string>2</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>SUFeedURL</key>                  <string>https://raw.githubusercontent.com/zhangdi/ClipMate/main/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key>    <true/>
</dict>
</plist>
PLIST

# 应用图标（Resources/AppIcon.icns 由 scripts/make-icon.swift 生成，已入库）
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cp "$BIN_PATH/ClipMate" "$APP/Contents/MacOS/ClipMate"
# 签名：优先使用本机自签/正式代码签名证书（授权跨构建稳定），
# 没有则退回 ad-hoc（每次重新打包辅助功能授权会失效，需重新添加）。
SIGN_IDENTITY="ClipMate Dev"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "ClipMate Dev"; then
    codesign --force --sign "${SIGN_IDENTITY}" "$APP"
    echo "==> 已使用证书签名：${SIGN_IDENTITY}"
    echo "    辅助功能授权按证书记录，重新打包不再失效"
else
    codesign --force --sign - "$APP"
    echo "==> ad-hoc 签名：每次重新打包辅助功能授权会失效"
    echo "    运行 scripts/make-dev-cert.sh 创建证书可永久解决"
fi

echo "==> 完成：$APP"
echo "    启动：open $APP"
echo "    提示：首次粘贴回写需在 系统设置 → 隐私与安全性 → 辅助功能 中授权 ClipMate"
