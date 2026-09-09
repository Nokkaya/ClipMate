#!/bin/bash
# 生成 Sparkle 2 标准 appcast.xml 文件
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/ClipMate.app"
if [ ! -d "$APP" ]; then
    echo "错误：请先运行 ./make-app.sh 构建应用"
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo "0.2.0")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo "2")
DMG_NAME="ClipMate-${VERSION}.dmg"
DMG_PATH="dist/${DMG_NAME}"

if [ ! -f "$DMG_PATH" ]; then
    echo "提示：DMG 尚未生成，正在压制..."
    ./make-dmg.sh
fi

LENGTH=$(stat -f%z "$DMG_PATH" 2>/dev/null || wc -c < "$DMG_PATH")
PUB_DATE=$(date -R 2>/dev/null || date +"%a, %d %b %Y %H:%M:%S %z")
DOWNLOAD_URL="https://github.com/zhangdi/ClipMate/releases/download/v${VERSION}/${DMG_NAME}"
OUTPUT_XML="appcast.xml"

cat > "$OUTPUT_XML" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ClipMate Changelog</title>
    <link>https://raw.githubusercontent.com/zhangdi/ClipMate/main/appcast.xml</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:releaseNotesLink>https://github.com/zhangdi/ClipMate/releases/tag/v${VERSION}</sparkle:releaseNotesLink>
      <description><![CDATA[
        <h2>ClipMate v${VERSION}</h2>
        <ul>
          <li>内置 AI 智能问答侧边栏，支持与主历史无缝联动。</li>
          <li>Liquid Glass 液态毛玻璃按钮与现代微光设计。</li>
          <li>中英文双语全界面即时无缝切换。</li>
          <li>正式发布 DMG 安装镜像与自动更新支持。</li>
        </ul>
      ]]></description>
      <enclosure url="${DOWNLOAD_URL}"
                 sparkle:version="${BUILD}"
                 sparkle:shortVersionString="${VERSION}"
                 length="${LENGTH}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML

echo "==> 已生成 Sparkle 2 标准 Appcast: $OUTPUT_XML"
echo "    版本: v${VERSION} (Build ${BUILD})"
echo "    大小: ${LENGTH} 字节"
echo "    链接: ${DOWNLOAD_URL}"
