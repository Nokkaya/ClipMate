#!/bin/bash
# 构建 ClipMate.app 并压制为正式发布的只读 DMG 安装镜像，同时生成 SHA-256 校验和。
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 步骤 1/4: 构建并签名应用 bundle"
./make-app.sh

APP="dist/ClipMate.app"
if [ ! -d "$APP" ]; then
    echo "错误：未找到构建产物 $APP"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.2.0")
DMG_NAME="ClipMate-${VERSION}.dmg"
DMG_PATH="dist/${DMG_NAME}"
STAGING="dist/dmg-staging"

echo "==> 步骤 2/4: 准备 DMG 装配目录 (v${VERSION})"
rm -rf "$STAGING"
mkdir -p "$STAGING"

# 拷贝应用
cp -R "$APP" "$STAGING/"

# 创建 Applications 软链接（用户可直接拖拽安装）
ln -s /Applications "$STAGING/Applications"

echo "==> 步骤 3/4: 压制 UDZO 格式压缩镜像"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "ClipMate" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING"

echo "==> 步骤 4/4: 生成 SHA-256 校验和"
cd dist
shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256"
cd ..

DMG_SIZE=$(ls -lh "$DMG_PATH" | awk '{print $5}')
SHA256=$(cat "${DMG_PATH}.sha256" | awk '{print $1}')

echo ""
echo "=========================================="
echo "✅ ClipMate 正式分发 DMG 打包成功！"
echo "产物路径: $DMG_PATH"
echo "文件大小: $DMG_SIZE"
echo "SHA-256:  $SHA256"
echo "校验文件: ${DMG_PATH}.sha256"
echo "=========================================="
echo ""
echo "挂载测试: open $DMG_PATH"
