#!/bin/bash
# 开发期辅助：清除 ClipMate 的辅助功能授权残留并打开系统设置。
#
# 背景：make-app.sh 使用 ad-hoc（临时）签名，每次重新打包 cdhash 都会变化，
# macOS TCC 会视为"新应用"，旧授权作废并再次弹窗。重新授权前先清残留，
# 避免"开关已开但不生效"的状态。
#
# 正式分发后用 Developer ID 证书签名，授权按 Team ID 记录，重新构建不再失效。
set -e
tccutil reset Accessibility com.clipmate.app || true
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
echo "==> 已清除旧授权并打开系统设置"
echo "    步骤：辅助功能列表中删除旧的 ClipMate 条目（如有）→ 点 + 添加 dist/ClipMate.app → 打开开关"
echo "    然后重新唤起面板按 ⏎ 粘贴即可生效"
