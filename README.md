# ClipMate

原生、快速、隐私优先的 macOS 剪贴板历史工具。菜单栏常驻、热键秒唤起、自动记录文本 / 图片 / 文件 / PDF / 富文本，支持全文与语义混合检索，内置 AI 侧边栏与自定义脚本动作。

**零第三方依赖** · 最低 macOS 13 · Swift 6.1 + SwiftUI · 数据全本地

> 产品方案与里程碑见《剪贴板历史工具-方案设计与开发计划.md》，本仓库为该计划的实现。

---

## 功能

### 采集

| 能力 | 说明 |
|---|---|
| 监听方式 | 0.5s 轮询 `NSPasteboard.changeCount`，后台队列读取，读取期间剪贴板再次变化则丢弃本次 |
| 内容类型 | 纯文本 / URL / 富文本（RTF·HTML）/ 图片 / 文件 URL / PDF |
| PDF | 首页缩略图 + PDFKit 全文提取入库可检索，粘贴保留 PDF 格式 |
| 图片 | 缩略图（≤512px，有透明通道存 PNG，无则 JPEG 0.85）内联入库，原图按内容哈希落盘 |
| 去重 | SHA256 内容哈希命中则复用同一条目，`use_count + 1` 并上浮 |
| 智能标题 | 本地规则识别色值 / Markdown 标题 / CLI 命令 / SQL / 代码签名 / JSON 摘要，生成可读标题（可关） |
| 自动标签 | 链接、邮箱、颜色、代码、JSON、长文本等，纯本地规则引擎，只扫描前 16KB |
| 号码识别 | 手机号 / 银行卡（Luhn 校验）/ 身份证（校验位）/ 快递单号 / IP / 金额 / 纯数字，自动打标签并可一键过滤 |
| 图片 OCR | Vision 文字识别（中英混合），结果入库可检索（可关） |
| 链接元数据 | 后台抓取网页 `<title>` 与 favicon（2.5s 超时，失败静默降级）（可关） |
| 容量上限 | 单条默认 20MB，可调 1–100MB；超限跳过 |

### 检索

- **全文检索**：SQLite FTS5（外部内容表 + 触发器同步）。拉丁文走前缀匹配；含 CJK 的查询自动降级为 `LIKE` 子串匹配，保证中文命中。FTS5 不可用时全局降级 LIKE。
- **语义检索**：系统 `NLEmbedding` 句向量，零网络零成本。查询向量与库内向量做余弦相似度（阈值 0.28），与关键词结果按 **RRF（k=60）** 融合排序，固定条目额外加权。存量向量启动时后台补算（每轮 2000 条、每批 50 条），采集后单条防抖补算。
- **关键词高亮**：标题、正文与预览页均高亮命中词。
- **分类过滤**：全部 / 文本 / 图片 / 文件 / 链接 / 片段 / 固定 / **号码**，8 个 chip，`Tab` 循环切换。
- **情境过滤**：按**来源应用**与**时间范围**（今天 / 昨天 / 最近 3 天 / 本周 / 本月）筛选——「我记得是昨天从微信复制的」可以直接点出来。
- **检索语法**：`#11`（恰好 11 位数字）、`#>8` / `#<12`（位数区间）、`len:>10`、`app:微信`、`before:昨天`、`after:2026-09-01`、`138*`（前缀），可叠加；悬停搜索框可查看提示。
- **号码友好**：号码按 3-4-4 / 4 位分组展示并放大等宽显示；同一号码的不同写法（`138 1234 5678` 与 `13812345678`）自动归并为一条。
- **片段短码**：输入 `/` 召回全部片段，`/email` 精确置顶。

### 粘贴与批量

- **粘贴回写**：先快照当前剪贴板 → 写入条目内容 → 合成 ⌘V → 0.45s 后恢复快照，不污染用户剪贴板。
- **无辅助功能权限时降级**为「仅复制到剪贴板」并播放提示音。
- **粘贴为纯文本**（`⌘⌥⏎`），富文本 / PDF / 链接均可去格式粘贴。
- **粘贴队列**：`⇧⏎` 逐条入队（最多 9 条）→ `⌘⇧⏎` 按序批量粘贴（每条间隔 0.55s）。
- **多选批量**：`⇧↑↓` 扩展选择，支持合并复制、批量固定、批量入队、批量删除。
- **编辑后复制**：`⌥⏎` 就地编辑文本再粘贴 / 复制。
- **菜单栏最近 5 条**一键复制。

### AI

- **Provider**：任意 OpenAI 兼容 Chat Completions 端点（OpenAI / DeepSeek / Ollama / LM Studio / 兼容网关），流式 SSE 输出、可中断。
- **默认关闭**，需在设置中显式启用；API Key 仅存 **Keychain**，不落盘、不入日志。
- **AI 侧边栏**（`⌘K` / `⌘⇧A`）：与主列表实时联动，选中条目即作为上下文，内置 8 个提示词模板（中英互译、精简摘要、提取要点、解释代码、修正语法、专业润色、生成单测、JSON 转 TS）并支持自定义模板，模板内 `{content}` 自动替换为剪贴板正文（截断 8000 字符）。
- **问剪贴板**：多轮追问，对话历史仅存内存。
- **结果三种处置**：复制到剪贴板 / 以 `AI` 标签另存为新条目 / 直接粘贴到唤起前的应用。
- **提示词模板**与**脚本动作**均可在设置中增删、恢复默认。

### 自动化脚本

- 设置 → 脚本：`shell`（`/bin/sh -c`）或 macOS 快捷指令（`shortcuts run`）。
- 剪贴板文本经 **stdin** 传入，**stdout** 作为结果（超时 10s，输出截断 20000 字符），结果可直接复制 / 另存 / 直贴。
- 内置 **14 个预置动作**（时间戳转日期、Base64 编解码、JSON 美化压缩、URL 编解码、SHA-256、MD5、字数统计、提取网址/邮箱、去空行、转下划线命名），首次启动默认启用 4 个。

### 片段收藏

- 任意条目右键「存为片段」，可设标题、分组与快捷短码。
- 主面板切到「片段」分类时，顶部出现分组栏（全部 / 各分组 / 新建片段）。
- 设置 → 片段页支持搜索（标题 / 正文 / 短码）与分组筛选，独立于历史条目管理。

### 隐私与安全

| 机制 | 说明 |
|---|---|
| 数据全本地 | 仅存 `~/Library/Application Support/ClipMate/`，无任何遥测上报 |
| 敏感应用排除 | 内置 1Password / 钥匙串访问 / Bitwarden / KeePassXC，可增删，支持「一键添加当前前台应用」 |
| 安全输入检测 | `IsSecureEventInputEnabled()` 为真（密码框）时跳过采集 |
| 锁屏暂停 | 监听 `screenIsLocked` / `screenIsUnlocked` 通知 |
| 自写抑制 | 自己写回剪贴板的内容带私有 UTI 标记 + 时间窗抑制，不会回环采集 |
| 保留策略 | 默认 1000 条 / 30 天，固定条目豁免；启动时 + 每小时清理，同时回收孤儿 blob |
| 一键清空 | 面板与菜单栏均可清空（保留固定），删除条目时同步清理落盘文件 |

### 外观与本地化

- **7 套主题**：默认毛玻璃 / One Dark Pro / Dracula / Tokyo Night / Nord / Monokai / GitHub Light，设置页色卡预览，即时生效。
- **中英双语**：跟随系统或手动指定，切换即时生效（无需重启）。
- **毛玻璃面板**：`NSVisualEffectView`（`.popover` / `.behindWindow`），窗口内绘制阴影避免重算卡顿。
- **面板定位**：屏幕居中 / 跟随鼠标 / 记忆位置三选一。
- **细节**：自定义药丸滚动条、类型色标、触感反馈、采集提示音。

---

## 快捷键

### 全局

| 按键 | 行为 |
|---|---|
| `⌘⇧V`（可改：`⌘⌥V` / `⌃⌥V` / `F9`） | 唤起 / 隐藏主面板 |

### 主面板

| 按键 | 行为 |
|---|---|
| `↑` `↓` | 上下移动选中 |
| `⇧↑` `⇧↓` | 扩展多选 |
| `⏎` | 粘贴选中条目并隐藏面板 |
| `⌘⏎` | 仅复制（多选时合并复制） |
| `⌘⌥⏎` | 粘贴为纯文本 |
| `⌥⏎` | 编辑后复制 |
| `⇧⏎` | 加入 / 移出粘贴队列（多选时批量入队） |
| `⌘⇧⏎` | 按序粘贴整个队列 |
| `⌘1` … `⌘9` | 直接粘贴列表第 N 条 |
| `⌘K` / `⌘⇧A` | 展开 / 收起 AI 侧边栏 |
| `⌘I` | 详情预览 |
| `⌘P` | 固定 / 取消固定（多选时批量固定） |
| `⌘R` | 重命名条目（自定义标题，之后可按名字搜到） |
| `⌘A` | 全选可见条目（搜索框为空时） |
| `⌘C` | 复制选中条目（搜索框为空时） |
| `⌫` | 删除选中（多选时批量删除；搜索框为空时生效） |
| `Tab` | 循环切换分类 |
| `Esc` | 依次：清多选 → 关预览 → 收起 AI 侧边栏 → 清空搜索词 → 隐藏面板 |

### 菜单栏

最近 5 条快捷复制 · 打开主面板 · 暂停 / 恢复采集 · 清空历史（保留固定） · 导出历史 · 导入历史 · 检查更新 · 设置（`⌘,`）· 退出（`⌘Q`）。

---

## 安装

### 源码构建（推荐用于开发）

```bash
swift run                     # 直接运行（菜单栏出现图标，⌘⇧V 唤起）
./make-app.sh                 # 打包 dist/ClipMate.app（release + 签名）
open dist/ClipMate.app
```

### DMG 安装包

```bash
./make-dmg.sh                 # 构建 app 并压制只读 UDZO 镜像 + 生成 SHA-256
open dist/ClipMate-0.2.0.dmg  # 挂载后拖入 Applications
```

### Homebrew Cask

仓库内提供 Cask 定义 `Casks/clipmate.rb`（尚未提交至 Homebrew 官方仓库，可本地安装）：

```bash
brew install --cask ./Casks/clipmate.rb
```

---

## 构建与发布脚本

| 脚本 | 作用 |
|---|---|
| `./make-app.sh` | `swift build -c release` → 组装 `dist/ClipMate.app` → 签名（优先本机「ClipMate Dev」证书，否则 ad-hoc） |
| `./make-dmg.sh` | 调用 `make-app.sh` → 压制 UDZO 格式 DMG + Applications 软链接 → 生成 `.sha256` |
| `./scripts/generate-appcast.sh` | 依据 DMG 生成 Sparkle 2 格式的 `appcast.xml`（版本、大小、下载地址） |
| `./scripts/make-dev-cert.sh` | 创建自签名代码签名证书「ClipMate Dev」（10 年有效，仅需一次） |
| `./scripts/make-icon.swift` | 生成 `Resources/AppIcon.icns`（已入库） |
| `./reset-permission.sh` | 清除辅助功能授权残留并打开系统设置 |

---

## 架构

```
Sources/
├── ClipMate/main.swift          # 可执行壳（accessory 策略，无 Dock 图标）
└── ClipMateCore/                # 库目标（可被测试链接）
    ├── Model/       ClipItem / ClipKind / FilterKind
    ├── Store/       Database(SQLite3 封装) / Migrations / ClipStore / SearchQuery
    ├── Capture/     ClipboardMonitor / ClipboardReader / BlobStore
    │                AutoTagger / NumberRecognizer / SmartTitleGenerator / URLMetadataFetcher
    ├── Paste/       PasteBack(快照 + CGEvent) / FrontAppTracker
    ├── Hotkey/      HotkeyManager（Carbon 全局热键）
    ├── Panel/       PanelController / PanelView / ClipRowView / PanelViewModel
    │                Overlays / PreviewOverlay / AISidebarView
    ├── AI/          AIService / AIWorkspaceModel / EmbeddingService / ScriptRunner
    ├── Settings/    AppSettings / SettingsView / SettingsWindowController / KeychainStore
    ├── App/         AppModel(组装根) / AppDelegate / MenuBarController
    │                OnboardingController / UpdateManager
    └── SharedUI/    Theme / Palette / ButtonStyles / L10n / FlowLayout
                     ModernScroller / SyntaxHighlighter / TextHighlighter
                     HapticHelper / Helpers / VisualEffectBackground
```

### 技术要点

- **零第三方依赖**：存储直接用系统 SQLite3（`import SQLite3`），WAL 模式 + `SQLITE_OPEN_FULLMUTEX`；无 SPM 外部依赖，无 `Package.resolved`。
- **线程模型**：主线程只做 UI；采集在 `clipmate.capture` 串行队列，OCR 在 `clipmate.ocr`，向量补算在 `clipmate.embedding`（独立数据库连接，利用 WAL 多连接避免与主线程查询争锁）。
- **粘贴目标记录**：面板唤起会激活自身，因此 `FrontAppTracker` 在唤起**之前**记录前台应用 PID，作为回写目标。
- **窗口行为**：`NSPanel`（`.borderless` + `.nonactivatingPanel`），不抢焦点；窗口本身透明无阴影，阴影由 SwiftUI 在窗口内绘制，避免内容变化触发系统阴影重算。
- **迁移机制**：`PRAGMA user_version`，当前为 **v4**（v1 建表 + FTS5；v2 增 `embedding` 列；v3 以 `plain_text, title` 两列重建 FTS 索引并全量回填；v4 增 `num_key` 号码归一化键，存量数据启动后后台回填）。

### 数据存储

| 项目 | 位置 |
|---|---|
| 数据库 | `~/Library/Application Support/ClipMate/clipmate.sqlite`（WAL） |
| 原图 / PDF | `~/Library/Application Support/ClipMate/blobs/`，文件名为内容 SHA256，天然去重 |
| 缩略图 / favicon / RTF | 数据库 `inline_data` 列（列表查询不读取，按需加载） |
| API Key | Keychain（`service: ClipMate`，`account: aiAPIKey`） |
| 其余设置 | `UserDefaults` |

---

## 配置 AI

设置 → AI：

| 项目 | 说明 |
|---|---|
| 启用 AI 智能操作 | 默认关闭，开启后侧边栏与脚本外的 AI 能力可用 |
| API 端点 | 需填到 `/v1` 这一层，如 `https://api.openai.com/v1`（不会自动补全） |
| 模型名称 | 如 `gpt-4o-mini` |
| API 密钥 | 仅存 Keychain；本地服务（Ollama / LM Studio）可留空 |
| 测试连接 | 发送「请只回复：OK」验证连通性 |

示例：

- OpenAI：`https://api.openai.com/v1` + `gpt-4o-mini` + API Key
- Ollama（本地、免费、隐私）：`http://localhost:11434/v1` + 如 `qwen2.5:7b`，Key 留空

---

## 自动更新

`UpdateManager` 为**自研实现**（不依赖 Sparkle 库，仅复用其 appcast 格式）：

- Feed 取自 Info.plist 的 `SUFeedURL`，默认 `https://raw.githubusercontent.com/zhangdi/ClipMate/main/appcast.xml`。
- 解析 feed 中全部 `<item>` 并取版本号最高的一条（`sparkle:shortVersionString` 的元素与属性两种写法都支持）。
- 启动后静默检查，且距上次检查超过 24 小时才触发；设置页可手动检查。
- 发现新版本后**仅提示并跳转浏览器下载页**，不内置下载 / 安装，也不做签名或哈希校验——请以 Releases 页面的 SHA-256 自行核对。

发版流程：`./make-dmg.sh` → 上传 DMG 至 GitHub Releases → `./scripts/generate-appcast.sh` 更新 `appcast.xml`。

---

## 权限说明

剪贴板采集**不需要任何授权**（轮询 `changeCount`）。只有**粘贴回写**（合成 ⌘V）需要**辅助功能**权限：

- 首次启动引导页点击「开始使用」时请求；未授权时所有粘贴操作自动降级为「仅复制到剪贴板」并播放提示音。
- `make-app.sh` 优先使用本机「ClipMate Dev」证书签名：TCC 按「证书 + Bundle ID」记录授权，**重新打包不再失效**；退回 ad-hoc 签名时每次重新打包都需重新授权。

```bash
./scripts/make-dev-cert.sh   # 一次性：创建自签名证书
./make-app.sh                # 自动探测并使用该证书签名
./reset-permission.sh        # 授权异常时：清除残留并打开系统设置
```

正式分发应替换为 Developer ID 签名 + `notarytool` 公证。

---

## 测试

```bash
swift run ClipMateTests
```

本环境仅安装 Command Line Tools（无 XCTest），测试以自研 runner 形式实现，当前 **55 个用例全部通过**，覆盖：

- 采集与去重、分类过滤、固定与保留策略、编辑后检索、清空保留固定
- 图片 / PDF 落盘与清理、缩略图自适应压缩、异步 OCR 补全
- FTS5 可用性降级、中文 LIKE 检索、向量编解码与语义检索、RRF 联动
- 导入导出 roundtrip、片段 CRUD 与短码检索、链接元数据持久化
- 智能标题、自动标签与色值识别、语法高亮、关键词高亮
- 脚本执行（含 64KB 以上输出的管道防死锁）、提示词模板插值
- 面板多选 / 合并复制 / AI 侧边栏联动、主题引擎、本地化字典、版本比较

另有性能基准模式：`CLIPMATE_BENCH_DB=/path/to/clipmate.sqlite swift run ClipMateTests`，对真实库跑筛选 / 搜索 / 格式化基准。

### 性能预算

| 指标 | 预算 | 实测 |
|---|---|---|
| 常驻内存 | ≤ 120MB | 32–45MB（149 条历史，空闲实测，随检索活动波动） |
| 启动即常驻、无崩溃 | — | ✅ 冒烟通过 |
| 检索（万条内） | ≤ 50ms | FTS5 索引查询 ✅ |

---

## 已知限制

- **AI 对话不持久化**：消息仅存内存，切换选中条目或清空对话即丢失。
- **自动更新不内置下载安装**，也不校验签名，需手动从 Releases 下载。
- **全局热键冲突静默失败**：注册被系统拒绝时无提示，需改选其它预设。
- **脚本动作无沙箱**：以当前用户权限直接执行，请只添加可信命令；取消不会终止已启动的子进程（最长等到 10s 超时）。
- 少量文案尚未本地化（设置窗口标题、导入导出面板等）。

## 路线图

- [ ] Apple Foundation Models 端侧 Provider（需 macOS 26 SDK）
- [ ] iCloud 同步（需签名与 CloudKit entitlement）
- [ ] Developer ID 签名 + 公证，Homebrew Cask 正式提交
- [ ] AI 对话持久化与会话管理
- [ ] 批量多选删除的键盘导航完善
