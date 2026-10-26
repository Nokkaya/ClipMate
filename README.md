<div align="center">

<img src="Resources/AppIcon.png" alt="ClipMate Icon" width="128" height="128" />

# ClipMate

**原生 · 极速 · 隐私优先的 macOS 现代剪贴板管理器**  
*Native, Blazing-Fast, Privacy-First Clipboard Manager for macOS with Hybrid Search & Local AI*

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue.svg?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%20%7C%206.0-F05138.svg?style=flat-square&logo=swift)](https://swift.org)
[![Release](https://img.shields.io/badge/release-v0.1.1-brightgreen.svg?style=flat-square)](https://github.com/Nokkaya/ClipMate/releases)
[![Tests](https://img.shields.io/badge/tests-162%20passed-success.svg?style=flat-square)](https://github.com/Nokkaya/ClipMate)
[![Dependencies](https://img.shields.io/badge/dependencies-0%20external-orange.svg?style=flat-square)](#-技术特性与架构)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)

</div>

---

## 📖 简介

**ClipMate** 是一款面向 macOS 的轻量级剪贴板历史工具，专为注重效率与数据隐私的用户打造。无需笨重的 Electron 容器，无任何外部第三方依赖，纯 Swift + AppKit / SwiftUI 原生编写，实现开箱即用的毫秒级唤起与极低资源常驻。

ClipMate 不仅具备高保真的剪贴板采集与全文/语义混合检索能力，还内置了**活粘贴意图控件（Interactive Clips）**、**LLM 汇聚工作草稿（Working Draft）** 以及 **AI 侧边栏助手**，让剪贴板成为您的随身多功能创作台。

---

## ✨ 核心特性

### ⚡️ 极速无感采集
- **全格式支持**：自动记录纯文本、URL、富文本（RTF / HTML）、图片、PDF 以及文件路径。
- **PDF & 图片 OCR**：PDF 首页缩略图实时生成并提取全文入库；图片自动进行系统级 Vision OCR 文字识别。
- **智能元数据**：纯本地规则引擎识别色值、Markdown 结构、SQL、JSON 摘要，后台静默解析链接标题与 Favicon。
- **号码识别归一**：精准识别手机号、银行卡号（Luhn 校验）、快递单号、IP、身份证等，归一化展示并支持类型过滤。
- **天然去重**：SHA-256 内容哈希命中去重，自动增加使用计数并置顶上浮。

### 🔍 全文与语义混合检索
- **SQLite FTS5 全文检索**：毫秒级多关键词前缀匹配；针对中文（CJK）智能自动降级至子串检索，保证零遗漏。
- **系统原生语义检索**：基于 macOS 原生 `NaturalLanguage` 句向量模型，**零网络流量、零推理成本**。
- **RRF 混合排序**：关键词匹配与语义相似度结果经由 **RRF（Reciprocal Rank Fusion, k=60）** 算法精准加权融合。
- **情境过滤语法**：支持按来源应用（`app:微信`）、时间范围（`before:昨天`）、位数区间（`#11`、`#>8`）、片段短码（`/email`）多维组合过滤。

### 🧩 意图控件与「活粘贴」(Interactive Clips)
- **数值与物料缩放**：自动识别文本中的原料清单、BOM 耗材与数值比例，就地按倍率或目标总量实时换算。
- **日程动态顺延**：识别多行会议或活动日程，一键顺延整体开始时间或微调单项时长，自动校验重叠与超时冲突。
- **粘贴变焦 (Paste Zoom)**：针对冗长资料提供「原长 / 要点摘要 / 关键单行 / 待办清单」4 级变焦，满足不同场景粘贴需求。

### 📝 LLM 智能工作草稿 (Working Draft)
- **多材料智能归属**：复制多段零散文本时自动聚合至工作草稿，智能推断内容用途与修改意向。
- **原子化修改建议**：AI 针对草稿生成的修改建议支持单条/批量原子化采纳或驳回，内置完整撤销恢复栈（Undo Stack）。
- **人工编辑优先保护**：人工就地修改的内容受系统级保护，模型提议绝不意外覆盖用户的直接编辑。

### 🤖 兼容通用协议的 AI 助手
- **OpenAI 兼容协议**：无缝对接 OpenAI、DeepSeek、Ollama（本地模型）、LM Studio 等任意服务端点。
- **实时联动侧边栏**（`⌘K` / `⌘⇧A`）：主列表条目一键作为上下文直接提问；内置中英互译、代码解释、提炼要点等实用模板。
- **零隐私泄露**：API Key 仅安全存放在 macOS **Keychain（钥匙串）**，内存无日志记录。

### 🛡️ 隐私优先，安全透明
- **100% 数据全本地**：仅存储于本地 SQLite 数据库，无任何遥测、无第三方 SDK、零外部数据回传。
- **敏感场景自动抑制**：自动识别并跳过 1Password、Bitwarden、KeePassXC、钥匙串访问等敏感应用；密码框输入（SecureEventInput）与锁屏状态下自动暂停采集。
- **无痕回写保护**：粘贴条目时先快照剪贴板，合成粘贴动作后立即恢复快照，带私有 UTI 标记防止回环自录。

---

## 📥 安装指南

### 方式一：下载 DMG 安装镜像（推荐）

1. 从 [GitHub Releases](https://github.com/Nokkaya/ClipMate/releases/latest) 下载最新版本的 `ClipMate-0.1.1.dmg`。
2. 双击打开镜像，将 `ClipMate.app` 拖入 `Applications` 应用程序文件夹。
3. 首次启动时，按下全局快捷键 `⌘⇧V` 唤起主面板。

### 方式二：Homebrew Cask

本仓库内置 Homebrew Cask 配置文件，可直接通过本地 Formula 安装：

```bash
brew install --cask ./Casks/clipmate.rb
```

### 方式三：源码构建

**环境要求**：macOS 13.0+，已安装 Xcode Command Line Tools（或 Swift 5.9+ 工具链）。

```bash
# 1. 克隆仓库
git clone https://github.com/Nokkaya/ClipMate.git
cd ClipMate

# 2. 编译并直接运行
swift run

# 3. 压制打包正式版 DMG
./make-dmg.sh
# 产物将生成在 dist/ClipMate-0.1.1.dmg
```

> [!TIP]
> 运行 `./scripts/make-dev-cert.sh` 可创建本机开发签名证书「ClipMate Dev」，之后执行 `./make-app.sh` 将自动使用该证书进行稳定签名，避免重新构建后辅助功能权限失效。

---

## ⌨️ 快捷键速查

### 全局呼出
| 快捷键 | 行为 |
|---|---|
| `⌘⇧V` | 快速呼出 / 隐藏 ClipMate 面板（支持在设置中自定义） |

### 主面板导航与操作
| 按键 | 说明 |
|---|---|
| `↑` / `↓` | 上下移动当前选中项 |
| `⏎` | 将选中项粘贴至前台应用并隐藏面板 |
| `⌘⏎` | 仅复制到剪贴板（多选时自动合并复制） |
| `⌘⌥⏎` | 粘贴为去除格式的纯文本 |
| `⌥⏎` | 就地编辑文本内容后复制或粘贴 |
| `⇧⏎` | 将当前条目加入/移出粘贴队列 |
| `⌘⇧⏎` | 按队列先后顺序依次批量粘贴 |
| `⌘1` ～ `⌘9` | 极速直贴列表第 1 到第 9 项 |
| `⌘K` / `⌘⇧A` | 展开 / 收起 AI 智能侧边栏 |
| `⌘I` | 打开 / 关闭条目大图或文本详细预览 |
| `⌘P` | 置顶固定（Pinned）条目，免除自动过期清理 |
| `⌘R` | 自定义重命名当前条目标题 |
| `⇧↑` / `⇧↓` | 扩展多选条目（支持合并复制、批量删除、批量固定） |
| `Tab` | 循环切换类别过滤栏（全部 / 文本 / 图片 / 文件 / 链接 / 片段 / 固定 / 号码） |
| `Esc` | 依序收起浮层：清除多选 → 关闭预览 → 收起侧边栏 → 清空搜索 → 隐藏面板 |

---

## ⚙️ 配置指南

### 1. 辅助功能权限（Accessibility）
- 剪贴板采集**完全无需任何特殊系统权限**（基于系统标准 `changeCount` 轮询）。
- 仅当需要自动执行「回写粘贴」动作时，需要 macOS 的 **辅助功能（Accessibility）** 授权。若未授权，系统会自动安全降级为「仅复制到剪贴板」并播放提示音。
- 授权路径：**系统设置 → 隐私与安全性 → 辅助功能**，勾选 `ClipMate`。

### 2. AI 供应商配置
在 ClipMate 偏好设置中切换至 **AI** 标签页：
- **API 端点**：填入兼容 OpenAI 规范的完整端点（例如 `https://api.openai.com/v1`、`https://api.deepseek.com/v1` 或本地 `http://localhost:11434/v1`）。
- **模型名称**：指定使用的模型标识（例如 `gpt-4o-mini`、`deepseek-chat` 或 `qwen2.5:7b`）。
- **API 密钥**：密钥存储于系统 Keychain，本地服务（如 Ollama）可留空。

---

## 🏗 技术特性与架构

```
Sources/
├── ClipMate/main.swift              # 应用程序入口（LSUIElement 常驻菜单栏）
└── ClipMateCore/                    # 核心逻辑库
    ├── Model/                       # 核心数据模型 (ClipItem, ClipKind, FilterKind)
    ├── Store/                       # 数据存储引擎 (SQLite3 WAL, FTS5 索引, SearchQuery)
    ├── Capture/                     # 剪贴板采集与分析 (AutoTagger, NumberRecognizer, OCR)
    ├── Paste/                       # 快照回写装配与前台应用追踪 (PasteBack, FrontAppTracker)
    ├── Hotkey/                      # Carbon 全局热键监听
    ├── Panel/                       # 主面板交互、列表与意图控件视图 (PanelView, PanelViewModel)
    ├── Draft/                       # LLM 工作草稿引擎与修改建议模型 (WorkingDraftEngine)
    ├── AI/                          # AI 客户端通信与线程安全语义向量服务 (EmbeddingService)
    ├── Settings/                    # 用户偏好设置与 Keychain 安全存储
    ├── App/                         # 应用装配根 (AppModel, MenuBarController, UpdateManager)
    └── SharedUI/                    # 7 套主题引擎、毛玻璃视效与高亮控件
```

### 核心工程原则
1. **零第三方依赖 (Zero External Dependencies)**：直接调用 macOS 系统级 C API（`libsqlite3`、`Carbon`、`NaturalLanguage`、`Vision`、`PDFKit`），不引入任何臃肿的三方 SPM 包，构建迅速、分发干净。
2. **多线程并发安全保障**：UI 严格运行在 MainActor；采集在串行队列；SQLite 采用 WAL 模式加 `SQLITE_OPEN_FULLMUTEX`；CoreNLP 向量推理通过互斥锁严格串行化，彻底消除内存争抢。
3. **极低资源占用**：空闲时常驻内存仅约 35MB 左右，无定时后台无谓唤醒，电池与续航友好。

---

## 🧪 自动化测试

项目内置全功能无依赖测试运行器，覆盖采集去重、FTS5 检索、语义排序、活粘贴控件、工作草稿与并发安全等全量用例：

```bash
swift run ClipMateTests
```

当前测试状态：**157 / 157 用例全部通过 ✅**。

---

## 📄 开源协议

本项目采用 [MIT 许可证](LICENSE) 开源。欢迎提交 Issue、发起讨论或贡献 Pull Request！
