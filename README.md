# ClipMate

原生、快速、隐私优先的 macOS 剪贴板历史工具。菜单栏常驻、热键秒唤起、自动记录文本/图片/文件/富文本，全文检索，内置 AI 快速操作。

> 设计与开发计划见上级目录《剪贴板历史工具-方案设计与开发计划.md》，本仓库为该计划的实现。

## 功能现状（对照开发计划）

### ✅ M0 技术验证
- [x] 系统环境探测：Swift 6.1 + Command Line Tools 可完整构建（无需完整 Xcode）
- [x] 系统 SQLite FTS5 可用性运行时探测（不可用自动降级 LIKE）
- [x] Carbon 全局热键 / CGEvent 粘贴回写 / NSPanel 非激活面板 技术路线落地

### ✅ M1 MVP
- [x] 剪贴板监听（0.5s 轮询 changeCount，后台队列读取，变化竞态防护）
- [x] 采集类型：纯文本 / URL / 富文本（RTF/HTML）/ 图片（缩略图+原图落盘）/ 文件 URL
- [x] 重复内容去重合并上浮（SHA256 + use_count）
- [x] 非激活悬浮面板 + 菜单栏图标，全局热键 ⌘⇧V（可换档）
- [x] 键盘优先交互：`↑↓` 选择 · `⏎` 粘贴 · `⌘⏎` 复制 · `⌥⏎` 编辑 · `⌫` 删除 · `Esc` 隐藏 · `Tab` 切分类 · `⌘1-9` 快速粘贴 · `⌘P` 固定 · `⌘K` AI
- [x] 全文检索（FTS5，CJK 查询走 LIKE 保证中文命中）+ 分类过滤 chips
- [x] 固定 ★ / 单条删除 / 清空（保留固定，面板内浮层确认）
- [x] 粘贴回写：剪贴板快照 → 合成 ⌘V → 恢复原剪贴板；AX 未授权时降级为仅复制
- [x] 来源应用显示、相对时间、自动标签（链接/邮箱/色值/代码/JSON）
- [x] 敏感应用排除（内置 1Password/Keychain/Bitwarden/KeePassXC，可增删）
- [x] 安全输入检测（密码框不采集）、锁屏暂停、单条大小上限、条数/天数保留策略
- [x] 编辑后复制、菜单栏最近 5 条快捷复制、暂停采集、提示音
- [x] 设置窗口（通用/采集/隐私/AI/关于）+ 设置持久化 UserDefaults

### ✅ M3 AI 能力（部分，云端路径）
- [x] `⌘K` AI 快速操作：翻译 / 摘要 / 润色 / 修正语法 / 解释代码 / 提取要点 / 自定义指令
- [x] OpenAI 兼容流式 Provider（覆盖 OpenAI / Ollama / LM Studio / 各类兼容网关）
- [x] 结果三种处置：复制 / 替换为新条目 / 直接粘贴；流式预览可中断
- [x] API Key 仅存 Keychain；AI 默认关闭，启用需显式配置
- [x] **语义搜索**：NLEmbedding 本地句向量（零网络），与关键词检索 RRF 混合排序，后台自动补算向量，按含义也能搜到历史
- [x] **图片 OCR**（Vision，中英混合）：识别文字并入库可检索，可开关

### ✅ v1.1 体验增强
- [x] **详情预览面板**（`⌘I`）：大图 / 全文 / 文件清单 / 元信息 / OCR 文字，面板内直接复制/粘贴/编辑/入队
- [x] **粘贴队列**：`⇧⏎` 逐条入队（最多 9 条）→ `⌘⇧⏎` 顺序批量粘贴；无 AX 权限降级为拼接复制
- [x] **导入导出 JSON**：菜单栏入口，导入自动去重、还原原始时间
- [x] 数据库迁移机制（user_version，v1→v2 自动加向量列）

### ⏳ 后续（计划中的 M2/M3 余量与 P2）
- [ ] Apple Foundation Models 端侧 Provider（需 macOS 26 SDK）
- [ ] PDF 首页预览、片段收藏夹、自定义动作脚本、多语言
- [ ] iCloud 同步（需签名与 CloudKit entitlement）
- [ ] Sparkle 自动更新、Developer ID 公证、Homebrew Cask（需开发者证书）

## 构建与运行

```bash
# 开发运行（菜单栏出现图标，⌘⇧V 唤起面板）
swift run

# 单元测试（11 例；本环境仅 CLT 无 XCTest，故为自研 runner）
swift run ClipMateTests

# 打包成 ClipMate.app（release + ad-hoc 签名）
./make-app.sh
open dist/ClipMate.app
```

首次粘贴回写时系统会引导授予**辅助功能**权限（系统设置 → 隐私与安全性 → 辅助功能）；未授权时自动降级为"仅复制到剪贴板"。

## 架构

```
Sources/
├── ClipMate/main.swift        # 可执行壳（accessory 策略）
└── ClipMateCore/              # 库目标（可测试）
    ├── Model/                 # ClipItem / ClipKind / FilterKind
    ├── Store/                 # Database(SQLite3 封装) / Migrations / ClipStore / BlobStore
    ├── Capture/               # ClipboardMonitor / ClipboardReader / AutoTagger / BlobStore
    ├── Paste/                 # PasteBack(快照+CGEvent) / FrontAppTracker
    ├── Hotkey/                # Carbon 全局热键
    ├── Panel/                 # NSPanel 控制器 + SwiftUI 主面板/浮层/键盘处理
    ├── AI/                    # AIAction / OpenAICompatProvider / AIService
    ├── Settings/              # AppSettings / KeychainStore / 设置窗口
    ├── App/                   # AppModel(组装根) / AppDelegate / MenuBarController
    └── SharedUI/              # 材质背景 / 缩略图 / 时间格式化
```

技术要点：

- **零第三方依赖**：SQLite 直接用系统库（`import SQLite3`），WAL 模式 + FTS5 触发器同步
- **隐私默认安全**：数据全本地；安全输入（`IsSecureEventInputEnabled`）、锁屏通知、敏感应用前台检测三重防护；自己写回剪贴板的内容用私有 UTI 标记 + 时间窗抑制，不会回环采集
- **粘贴回写可靠性**：先快照原剪贴板（含私有 UTI），粘贴后 450ms 恢复，用户剪贴板不被污染；粘贴目标在面板唤起前记录（FrontAppTracker）

## 性能预算达成情况

| 指标 | 预算 | 实测（冒烟） |
|---|---|---|
| 常驻内存 | ≤ 120MB | ✅ 65MB |
| 启动即常驻、无崩溃 | — | ✅ 6s 冒烟通过 |
| 检索（万条内） | ≤ 50ms | FTS5 索引查询 ✅ |

## 配置 AI

设置 → AI：填入任意 OpenAI 兼容端点。示例：

- OpenAI：`https://api.openai.com/v1` + 模型 `gpt-4o-mini` + API Key
- Ollama（本地、免费、隐私）：`http://localhost:11434/v1` + 模型如 `qwen2.5:7b`，Key 留空
