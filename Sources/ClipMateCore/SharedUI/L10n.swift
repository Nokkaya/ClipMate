import Foundation
import SwiftUI

/// 轻量级原生多语言本地化模块（无需编译 .strings 文件，纯 Swift 零开销）。
public enum L10n {

    /// 获取当前生效的语言环境（跟随系统或用户在设置中显式指定）。
    public static var currentLanguage: AppLanguage {
        let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if let mode = AppLanguage(rawValue: raw), mode != .system {
            return mode
        }
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.starts(with: "en") ? .en : .zhHans
    }

    /// 翻译指定键，支持参数替换
    public static func tr(_ key: String, _ args: CVarArg..., lang: AppLanguage? = nil) -> String {
        let targetLang = lang ?? currentLanguage
        let template: String
        switch targetLang {
        case .en:
            template = enStrings[key] ?? zhStrings[key] ?? key
        case .zhHans, .system:
            template = zhStrings[key] ?? enStrings[key] ?? key
        }
        if args.isEmpty {
            return template
        }
        return String(format: template, arguments: args)
    }

    // MARK: - 分类与模式枚举多语言映射

    public static func filterTitle(_ kind: FilterKind, lang: AppLanguage? = nil) -> String {
        switch kind {
        case .all: return tr("filter.all", lang: lang)
        case .text: return tr("filter.text", lang: lang)
        case .image: return tr("filter.image", lang: lang)
        case .file: return tr("filter.file", lang: lang)
        case .link: return tr("filter.link", lang: lang)
        case .snippet: return tr("filter.snippet", lang: lang)
        case .pinned: return tr("filter.pinned", lang: lang)
        }
    }

    public static func positionModeTitle(_ mode: PanelPositionMode, lang: AppLanguage? = nil) -> String {
        switch mode {
        case .center: return tr("position.center", lang: lang)
        case .followCursor: return tr("position.followCursor", lang: lang)
        case .remember: return tr("position.remember", lang: lang)
        }
    }

    public static func languageTitle(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return tr("language.system")
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    // MARK: - 中英文字典

    private static let zhStrings: [String: String] = [
        // 主面板
        "search.placeholder": "搜索剪贴板历史…",
        "empty.title": "暂无剪贴板历史",
        "empty.subtitle": "按下 ⌘C 复制任意内容，将自动保存在这里",
        "empty.no_match": "未找到匹配项",
        "empty.no_match_sub": "换个关键词或切换分类试试",
        "footer.paste": "⏎ 粘贴",
        "footer.copy": "⌘⏎ 仅复制",
        "footer.edit": "⌥⏎ 编辑",
        "footer.ai": "⌘K AI工作台",
        "footer.preview": "⌘I 详情",
        "footer.delete": "⌫ 删除",
        "batch.selected": "已选 %d 项",
        "batch.paste_queue": "⏎ 粘贴队列",
        "batch.copy_all": "⌘⏎ 合并复制",
        "batch.pin_all": "⌘P 批量固定",
        "batch.delete_all": "⌫ 批量删除",
        "batch.cancel": "Esc 取消",

        // 分类
        "filter.all": "全部",
        "filter.text": "文本",
        "filter.image": "图片",
        "filter.file": "文件",
        "filter.link": "链接",
        "filter.snippet": "片段",
        "filter.pinned": "已固定",

        // 面板位置
        "position.center": "屏幕居中（跟随当前活动显示器）",
        "position.followCursor": "跟随鼠标光标（大屏贴手呼出）",
        "position.remember": "记忆上次拖拽位置",

        // 语言
        "language.system": "跟随系统",

        // 设置 Tab
        "tab.general": "通用",
        "tab.snippets": "片段",
        "tab.capture": "采集",
        "tab.privacy": "隐私",
        "tab.ai": "AI",
        "tab.scripts": "脚本",
        "tab.about": "关于",

        // 设置项
        "settings.hotkey": "全局热键",
        "settings.hotkey_sub": "随时随地呼出或隐藏 ClipMate 主搜索面板",
        "settings.position": "面板出现位置",
        "settings.position_sub": "选择主面板在多显示器或光标附近出现的定位策略",
        "settings.language": "界面显示语言",
        "settings.language_sub": "自定义应用程序的界面语言或自动跟随系统",
        "settings.launch_at_login": "开机自动启动",
        "settings.launch_at_login_sub": "登录 macOS 系统时在后台自动启动常驻",
        "settings.sound": "剪贴板提示音",
        "settings.sound_sub": "捕获到新的剪贴板内容时播放提示音",
        "settings.haptic": "触控板触觉反馈",
        "settings.haptic_sub": "复制、粘贴、清空等操作时触发触控板轻微震动",
        "settings.smart_title": "智能标题生成 (Smart Title)",
        "settings.smart_title_sub": "自动识别代码签名、SQL、CLI命令、Markdown标题并展示清晰标题",
    ]

    private static let enStrings: [String: String] = [
        // Main Panel
        "search.placeholder": "Search clipboard history…",
        "empty.title": "No clipboard history",
        "empty.subtitle": "Press ⌘C to copy anything, it will automatically appear here",
        "empty.no_match": "No matching items",
        "empty.no_match_sub": "Try a different keyword or category filter",
        "footer.paste": "⏎ Paste",
        "footer.copy": "⌘⏎ Copy",
        "footer.edit": "⌥⏎ Edit",
        "footer.ai": "⌘K AI",
        "footer.preview": "⌘I Detail",
        "footer.delete": "⌫ Delete",
        "batch.selected": "%d selected",
        "batch.paste_queue": "⏎ Paste Queue",
        "batch.copy_all": "⌘⏎ Copy Combined",
        "batch.pin_all": "⌘P Pin",
        "batch.delete_all": "⌫ Delete",
        "batch.cancel": "Esc Cancel",

        // Filter chips
        "filter.all": "All",
        "filter.text": "Text",
        "filter.image": "Image",
        "filter.file": "File",
        "filter.link": "Link",
        "filter.snippet": "Snippets",
        "filter.pinned": "Pinned",

        // Panel position
        "position.center": "Center Screen (Active Display)",
        "position.followCursor": "Follow Mouse Cursor",
        "position.remember": "Remember Last Position",

        // Language
        "language.system": "System Default",

        // Settings Tabs
        "tab.general": "General",
        "tab.snippets": "Snippets",
        "tab.capture": "Capture",
        "tab.privacy": "Privacy",
        "tab.ai": "AI",
        "tab.scripts": "Scripts",
        "tab.about": "About",

        // Settings items
        "settings.hotkey": "Global Hotkey",
        "settings.hotkey_sub": "Quickly summon or hide the ClipMate main search panel",
        "settings.position": "Panel Position",
        "settings.position_sub": "Choose where the main panel pops up across monitors and cursor",
        "settings.language": "App Language",
        "settings.language_sub": "Choose display language or follow macOS system language",
        "settings.launch_at_login": "Launch at Login",
        "settings.launch_at_login_sub": "Automatically start ClipMate in the background when logging in",
        "settings.sound": "Sound on Capture",
        "settings.sound_sub": "Play sound when new clipboard content is captured",
        "settings.haptic": "Haptic Feedback",
        "settings.haptic_sub": "Trigger subtle trackpad feedback on copy, paste and batch actions",
        "settings.smart_title": "Smart Title Generation",
        "settings.smart_title_sub": "Extract recognizable titles for code functions, SQL, CLI commands, and Markdown",
    ]
}
