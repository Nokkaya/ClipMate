import Foundation
import SwiftUI

/// 轻量级原生多语言本地化模块（无需编译 .strings 文件，纯 Swift 零开销）。
public enum L10n {

    /// 语言覆盖（当 AppSettings 变更语言时实时更新，避免与 UserDefaults 异步不同步）
    public static var overrideLanguage: AppLanguage? = nil

    /// 获取当前生效的语言环境（跟随系统或用户在设置中显式指定）。
    public static var currentLanguage: AppLanguage {
        let lang = overrideLanguage ?? {
            let raw = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
            return AppLanguage(rawValue: raw) ?? .system
        }()
        if lang != .system {
            return lang
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

    public static func tagTitle(_ tag: String, lang: AppLanguage? = nil) -> String {
        switch tag {
        case "代码": return tr("tag.code", lang: lang)
        case "长文本": return tr("tag.long_text", lang: lang)
        case "链接": return tr("tag.link", lang: lang)
        case "图片": return tr("tag.image", lang: lang)
        case "文件": return tr("tag.file", lang: lang)
        case "富文本": return tr("tag.rich_text", lang: lang)
        case "邮箱": return tr("tag.email", lang: lang)
        case "含链接": return tr("tag.has_link", lang: lang)
        case "颜色": return tr("tag.color", lang: lang)
        case "片段": return tr("tag.snippet", lang: lang)
        case "PDF": return tr("tag.pdf", lang: lang)
        case "JSON": return tr("tag.json", lang: lang)
        case "手机号": return tr("tag.phone", lang: lang)
        case "座机": return tr("tag.telephone", lang: lang)
        case "银行卡": return tr("tag.bank_card", lang: lang)
        case "身份证": return tr("tag.id_card", lang: lang)
        case "快递单号": return tr("tag.tracking", lang: lang)
        case "IP": return tr("tag.ip", lang: lang)
        case "金额": return tr("tag.amount", lang: lang)
        case "数字": return tr("tag.number", lang: lang)
        default: return tag
        }
    }

    public static func filterTitle(_ kind: FilterKind, lang: AppLanguage? = nil) -> String {
        switch kind {
        case .all: return tr("filter.all", lang: lang)
        case .text: return tr("filter.text", lang: lang)
        case .image: return tr("filter.image", lang: lang)
        case .file: return tr("filter.file", lang: lang)
        case .link: return tr("filter.link", lang: lang)
        case .snippet: return tr("filter.snippet", lang: lang)
        case .pinned: return tr("filter.pinned", lang: lang)
        case .number: return tr("filter.number", lang: lang)
        }
    }

    public static func timeTitle(_ time: TimeFilter, lang: AppLanguage? = nil) -> String {
        tr("time.\(time.rawValue)", lang: lang)
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

    public static func kindTitle(_ kind: ClipKind, lang: AppLanguage? = nil) -> String {
        tr("kind.\(kind.rawValue)", lang: lang)
    }

    public static func themeTitle(_ theme: AppTheme, lang: AppLanguage? = nil) -> String {
        tr("theme.\(theme.rawValue)", lang: lang)
    }

    public static func themeDesc(_ theme: AppTheme, lang: AppLanguage? = nil) -> String {
        tr("theme.desc.\(theme.rawValue)", lang: lang)
    }

    public static func templateName(_ id: String, defaultName: String, lang: AppLanguage? = nil) -> String {
        let key = "ai.tpl.\(id)"
        let localized = tr(key, lang: lang)
        return localized == key ? defaultName : localized
    }

    public static func scriptName(_ script: ScriptAction, lang: AppLanguage? = nil) -> String {
        let key = "script.preset.\(script.id)"
        let localized = tr(key, lang: lang)
        return localized == key ? script.name : localized
    }

    public static func scriptPresetDesc(_ id: String, lang: AppLanguage? = nil) -> String {
        let key = "script.preset_desc.\(id)"
        let localized = tr(key, lang: lang)
        return localized == key ? "" : localized
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    public static func relativeTime(_ date: Date, lang: AppLanguage? = nil) -> String {
        let interval = Date().timeIntervalSince(date)
        switch interval {
        case ..<0, ..<60:
            return tr("time.now", lang: lang)
        case ..<3600:
            let mins = max(1, Int(interval / 60))
            return tr("time.mins_ago", mins, lang: lang)
        case ..<86400:
            let hours = max(1, Int(interval / 3600))
            return tr("time.hours_ago", hours, lang: lang)
        case ..<(86400 * 30):
            let days = max(1, Int(interval / 86400))
            return tr("time.days_ago", days, lang: lang)
        default:
            return shortDateFormatter.string(from: date)
        }
    }

    // MARK: - 中英文字典

    private static let zhStrings: [String: String] = [
        "app.launch_failed": "ClipMate 启动失败",
        // 主面板
        "search.placeholder": "搜索剪贴板历史…",
        "search.help": "展开/收起 AI 问答侧边栏 (⌘K / ⌘⇧A)",
        "empty.title": "暂无剪贴板历史",
        "empty.subtitle": "按下 ⌘C 复制任意内容，将自动保存在这里",
        "empty.no_match": "未找到匹配项",
        "empty.no_match_sub": "换个关键词或切换分类试试",
        "footer.paste": "粘贴",
        "footer.copy": "仅复制",
        "footer.edit": "编辑",
        "footer.ai": "AI",
        "footer.preview": "详情",
        "footer.delete": "删除",
        "footer.cancel": "取消",
        "batch.selected": "已选 %d 项",
        "batch.paste_queue": "粘贴队列",
        "batch.copy_all": "合并复制",
        "batch.pin_all": "批量固定",
        "batch.delete_all": "批量删除",
        "batch.cancel": "取消",

        // 分类与状态
        "filter.all": "全部",
        "filter.text": "文本",
        "filter.image": "图片",
        "filter.file": "文件",
        "filter.link": "链接",
        "filter.snippet": "片段",
        "filter.pinned": "已固定",
        "filter.queue": "队列 %d",
        "filter.queue_tip": "按 ⌘⇧⏎ 顺序粘贴队列内容",
        "filter.paused": "已暂停采集",
        "filter.all_snippets": "全部片段",
        "filter.new_snippet": "新建片段",

        // 条目类型
        "kind.text": "文本",
        "kind.url": "链接",
        "kind.richText": "富文本",
        "kind.image": "图片",
        "kind.file": "文件",
        "kind.pdf": "PDF",

        // 自动标签
        "tag.code": "代码",
        "tag.long_text": "长文本",
        "tag.link": "链接",
        "tag.image": "图片",
        "tag.file": "文件",
        "tag.rich_text": "富文本",
        "tag.email": "邮箱",
        "tag.has_link": "含链接",
        "tag.color": "颜色",
        "tag.snippet": "片段",
        "tag.pdf": "PDF",
        "tag.json": "JSON",

        // 相对时间
        "time.now": "刚刚",
        "time.mins_ago": "%d分钟前",
        "time.hours_ago": "%d小时前",
        "time.days_ago": "%d天前",

        // 元数据与计量
        "meta.source": "来源",
        "meta.time": "时间",
        "meta.size": "大小",
        "meta.used": "使用",
        "meta.uses_count": "%d 次",
        "meta.chars": "%d 字符",
        "meta.chars_unit": "%d 字",
        "meta.lines": "%d 行",
        "meta.items": "%d 个项目",

        // 通用操作
        "action.copy": "复制",
        "action.copied": "已复制",
        "action.paste": "粘贴",
        "action.direct_paste": "直接粘贴 ⏎",
        "action.edit": "编辑",
        "action.delete": "删除",
        "action.cancel": "取消",
        "action.save": "保存",
        "action.confirm": "确认",
        "action.open": "打开",
        "action.add": "添加",
        "action.reset": "重置",
        "action.close": "关闭",
        "action.paste_plain": "粘贴为纯文本",
        "action.copy_plain": "复制为纯文本",
        "action.pin": "固定 ★",
        "action.unpin": "取消固定",
        "action.edit_snippet": "编辑片段…",
        "action.remove_snippet": "移出片段",
        "action.save_snippet": "存为片段…",
        "action.edit_item": "编辑…",
        "toast.paste_fallback.title": "无法自动粘贴至目标应用",
        "toast.paste_fallback.manual_hint": "内容已保留在剪贴板，请按 ⌘V 手动粘贴",
        "toast.paste_fallback.permission": "缺少辅助功能权限",
        "toast.paste_fallback.permission_hint": "内容已写入剪贴板，请按 ⌘V 粘贴（可在系统设置中授权）",
        "toast.paste_fallback.target_lost": "目标应用不可用或已退出",
        "toast.paste_queue_aborted": "检测到外部新复制，已终止队列粘贴",
        "toast.paste_queue_aborted_hint": "已保留您的最新剪贴板内容",
        "action.mute_action": "减少推荐此动作",
        "action.copy_only": "仅复制",
        "action.more_fields": "+%d 更多",
        "action.collapse_fields": "收起",
        "action.copy_ocr": "复制文字",
        "action.fix_line_breaks": "修复断行",
        "action.deduplicate_list": "名单去重",
        "action.format_json": "格式化 JSON",
        "action.translate": "快捷翻译",
        "action.translate_to_zh": "翻译为中文",
        "action.translate_to_en": "翻译为英文",
        "action.view_original": "查看原文",
        "action.view_result": "查看结果",
        "action.retry": "重试",
        "action.cancelling": "取消中…",
        "action.processing": "处理中…",
        "action.diff_deduped": "已删除 %d 条重复项",
        "action.diff_breaks_fixed": "已修复断行",
        "action.diff_json_formatted": "已格式化 JSON",
        "action.target_language": "目标语言",
        "action.need_ai_config": "需在设置中配置 AI 端点与模型",
        "action.open_settings": "前往设置",
        "action.compare": "原文比对",
        "action.result_card_title": "一键处理结果",
        "rec.title": "智能推荐",
        "rec.app_frequent": "此应用常用",
        "rec.same_material": "同份资料",
        "rec.sequence": "连续使用",
        "rec.dismiss": "隐藏此条推荐",
        "settings.recommendations_title": "智能内容推荐",
        "settings.recommendations_desc": "基于当前前台应用与使用习惯，在面板顶部提供最多 3 条快捷候选",
        "settings.clear_rec_learning": "清除推荐学习记录",
        "settings.clear_rec_learning_done": "已清除学习记录",
        "preview.extracted_fields": "可取用局部字段",
        "preview.highlight_in_source": "在原文中定位",
        "search.syntax_hint": "检索语法：\n#11 = 恰好 11 位数字 · #>8 / #<12 = 数字位数范围\nlen:>8 = 内容长度大于 8 · app:微信 = 来源应用\nbefore:昨天 / after:2026-09-01 = 时间范围 · 138* = 前缀匹配",
        "filter.number": "号码",
        "tag.phone": "手机号",
        "tag.telephone": "座机",
        "tag.bank_card": "银行卡",
        "tag.id_card": "身份证",
        "tag.tracking": "快递单号",
        "tag.ip": "IP",
        "tag.amount": "金额",
        "tag.number": "数字",
        "filter.all_sources": "所有来源",
        "filter.clear_context": "清除来源与时间筛选",
        "time.all": "全部时间",
        "time.today": "今天",
        "time.yesterday": "昨天",
        "time.last3Days": "最近 3 天",
        "time.thisWeek": "本周",
        "time.thisMonth": "本月",
        "action.rename": "重命名…",
        "action.clear_title": "清除自定义标题",
        "action.preview": "详情预览",
        "overlay.rename.title": "重命名条目",
        "overlay.rename.subtitle": "给这条内容起个好记的名字，之后按名字就能搜到",
        "overlay.rename.placeholder": "例如：招行卡号 / 公司座机 / 订单 2026-09",
        "overlay.rename.clear": "清除标题",
        "action.queue_add": "加入粘贴队列",
        "action.queue_remove": "移出粘贴队列",
        "action.ai_actions": "AI 操作…",
        "batch.copy_count": "合并复制选中的 %d 条",
        "batch.toggle_pin": "批量固定 / 取消固定",
        "batch.add_queue": "批量加入粘贴队列",
        "batch.delete_count": "删除选中的 %d 条",

        // 交互浮层
        "overlay.edit.title": "编辑内容",
        "overlay.edit.subtitle": "修改后将更新历史记录并复制到剪贴板",
        "overlay.edit.save_copy": "保存并复制",
        "overlay.clear.title": "清空全部历史？",
        "overlay.clear.subtitle": "已固定（Pinned）的条目会完整保留，未固定的全部历史将无法恢复。",
        "overlay.clear.confirm": "确认清空",
        "overlay.snippet.title_new": "新建常用片段",
        "overlay.snippet.title_edit": "编辑片段",
        "overlay.snippet.subtitle": "保存高频文本模板，支持快捷短码快速检索",
        "overlay.snippet.title_label": "片段标题（可选）",
        "overlay.snippet.title_placeholder": "如：开票抬头、Git rebase 常用流、邮箱签名…",
        "overlay.snippet.group_label": "分组",
        "overlay.snippet.group_placeholder": "开发 / 常用 / 邮件…",
        "overlay.snippet.shortcode_label": "快捷短码（可选）",
        "overlay.snippet.shortcode_placeholder": ";tax / ;git / ;sig…",
        "overlay.snippet.content_label": "片段正文内容",
        "overlay.snippet.content_placeholder": "在此粘贴或输入片段文本…",
        "overlay.snippet.save": "保存片段",

        // 详情预览（⌘I）
        "preview.pinned": "已固定",
        "preview.image_unavailable": "图片数据不可用",
        "preview.ocr_title": "识别到的文本 (Vision OCR)",
        "preview.ocr_copy": "复制文字",
        "preview.pdf_unavailable": "PDF 预览暂不可用",
        "preview.pdf_extracted": "提取的正文",
        "preview.url_default": "网页链接",
        "preview.url_open_tip": "在默认浏览器中打开链接",
        "preview.url_full": "完整链接",
        "preview.url_copy": "复制链接",
        "preview.json_title": "JSON 数据",
        "preview.json_format": "格式化显示",
        "preview.json_raw": "原始显示",
        "preview.json_copy": "复制格式化",
        "preview.code_title": "代码高亮",
        "preview.code_copy": "复制代码",
        "preview.file_title": "文件清单",
        "preview.file_locate_tip": "在访达中定位文件",
        "preview.text_title": "文本正文",
        "preview.tip_delete": "删除此条目 (⌫)",
        "preview.tip_edit": "编辑条目 (⌘E)",
        "preview.tip_snippet_edit": "片段设置",
        "preview.tip_snippet_save": "存为常用片段",
        "preview.tip_queue_remove": "移出多重粘贴队列",
        "preview.tip_queue_add": "加入多重粘贴队列",
        "preview.shortcut_bar": "⏎ 粘贴 · ⌘⏎ 复制 · Esc 关闭",

        // AI 侧边栏与工作台
        "ai.sidebar_title": "AI 问答",
        "ai.workspace_title": "AI 工作台 · 问剪贴板",
        "ai.status_configured": "OpenAI 兼容端点",
        "ai.status_unconfigured": "未配置（设置 → AI）",
        "ai.tip_clear_chat": "重置会话并清空历史",
        "ai.clear_chat": "清空会话",
        "ai.tip_collapse_sidebar": "收起 AI 侧边栏 (⌘K / ⌘⇧A)",
        "ai.tip_close_esc": "关闭（Esc）",
        "ai.select_item_hint": "在左侧列表选择条目以分析与问答",
        "ai.image_ocr_hint": "（图片条目：可提问图中的识别文字）",
        "ai.empty_chat_title": "向 AI 提问 / 连续追问",
        "ai.empty_chat_subtitle": "点击上方快捷模板，或在下方输入框自由提问。\n支持多轮连续追问与代码/文本分析。",
        "ai.workspace_empty_subtitle": "在主面板中按 ⌘K 打开此工作台，可针对任意选中的剪贴板内容进行多轮追问。",
        "ai.response_title": "AI 回复",
        "ai.role_user": "你",
        "ai.drag_hint": "拖动空白可移动",
        "ai.thinking": "正在思考分析中…",
        "ai.prompt_placeholder_new": "向 AI 自由提问当前剪贴板（⏎ 发送）…",
        "ai.prompt_placeholder_followup": "连续追问…",
        "ai.tip_send": "发送提问（Return）",
        "ai.copy_latest": "复制最新",
        "ai.save_as_new": "存为新条目",
        "ai.direct_paste": "直接粘贴 ⏎",
        "ai.tpl.translate": "中英互译",
        "ai.tpl.summary": "精简摘要",
        "ai.tpl.summarize": "提取要点",
        "ai.tpl.explainCode": "解释代码",
        "ai.tpl.grammar": "修正语法",
        "ai.tpl.rewrite": "专业润色",
        "ai.tpl.unitTest": "生成单测",
        "ai.tpl.jsonToTS": "JSON转TS",

        // 面板位置与语言
        "position.center": "屏幕居中（跟随当前活动显示器）",
        "position.followCursor": "跟随鼠标光标（大屏贴手呼出）",
        "position.remember": "记忆上次拖拽位置",
        "language.system": "跟随系统",

        // 设置 Tab
        "tab.general": "通用",
        "tab.snippets": "片段",
        "tab.capture": "采集",
        "tab.privacy": "隐私",
        "tab.ai": "AI",
        "tab.scripts": "脚本",
        "tab.about": "关于",

        // 设置项 - 主题外观
        "settings.theme.card_title": "界面外观与主题风格",
        "settings.theme.desc": "精选热门主题与配色方案，点击立即生效，兼顾 macOS 毛玻璃质感与经典编辑器格调。",
        "theme.default": "默认毛玻璃",
        "theme.desc.default": "原生 macOS 动态毛玻璃，通透纯粹，自适应明暗",
        "theme.oneDarkPro": "One Dark Pro",
        "theme.desc.oneDarkPro": "Atom / VS Code 经典暗色，深灰石板底色配标志性青蓝",
        "theme.dracula": "Dracula",
        "theme.desc.dracula": "官方经典吸血鬼德古拉暗色，深靛灰底色搭配标志性吸血鬼紫、霓虹粉与青绿",
        "theme.darcula": "Dracula",
        "theme.desc.darcula": "官方经典吸血鬼德古拉暗色，深靛灰底色搭配标志性吸血鬼紫、霓虹粉与青绿",
        "theme.tokyoNight": "Tokyo Night",
        "theme.desc.tokyoNight": "赛博朋克深靛蓝夜色，搭配霓虹粉青对比高亮",
        "theme.nord": "Nord",
        "theme.desc.nord": "北极极光与冰雪极简冷灰，克制内敛护眼配色",
        "theme.monokai": "Monokai",
        "theme.desc.monokai": "经典极客黑底高反差，明亮黄绿粉鲜明亮眼",
        "theme.githubLight": "GitHub Light",
        "theme.desc.githubLight": "清晰素雅纸白底色，搭配 GitHub 经典科技蓝",

        // 设置项 - 通用
        "settings.general.card_interaction": "交互与常规设置",
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
        "settings.backup.card_title": "数据备份与迁移",
        "settings.backup.stats": "历史 %d 条 · 片段 %d 条",
        "settings.backup.desc": "支持将本地存储的全部剪贴板历史与自定义片段完整导出为 JSON 备份文件，换机或重装时可无损导入合并。",
        "settings.backup.export": "导出完整备份 (JSON)",
        "settings.backup.import": "从备份恢复 (JSON)",
        "settings.backup.export_title": "导出剪贴板历史与片段备份",
        "settings.backup.export_success": "导出成功",
        "settings.backup.export_success_msg": "已成功将 %d 条记录备份至：\n%@",
        "settings.backup.export_failed": "导出失败",
        "settings.backup.import_title": "从备份文件恢复",
        "settings.backup.import_success": "恢复成功",
        "settings.backup.import_success_msg": "新入库 %d 条记录（已有相同内容已自动跳过合并）。",
        "settings.backup.import_failed": "恢复失败",
        "settings.shortcuts.card_title": "主面板常用快捷键",
        "settings.shortcuts.paste": "粘贴至当前光标处",
        "settings.shortcuts.copy": "复制到剪贴板并置顶",
        "settings.shortcuts.edit": "原地快速编辑正文",
        "settings.shortcuts.ai": "唤起 AI 智能助手",
        "settings.shortcuts.preview": "开关详情抽屉预览",
        "settings.shortcuts.quick_paste": "一键快速贴出指定序号项",
        "settings.shortcuts.multiselect": "多选选中多条记录",
        "settings.shortcuts.switch_tab": "快速在分类栏间轮换",

        // 设置项 - 片段
        "snippets.search_placeholder": "搜索片段标题、正文或短码…",
        "snippets.all_groups": "所有分组",
        "snippets.new": "添加片段",
        "snippets.empty": "暂无片段记录",
        "snippets.empty_sub": "点击右上角添加片段，或在主面板中将任意历史条目保存为常用片段",
        "snippets.no_match": "未找到匹配片段",
        "snippets.editor_title_new": "新建常用片段",
        "snippets.editor_title_edit": "编辑片段",
        "snippets.editor_subtitle": "输入片段信息，保存后支持在主面板和设置中快速调用",
        "snippets.title_optional": "片段标题（可选）",
        "snippets.title_placeholder": "如：日常开票信息、Git 常用流、邮箱签名…",
        "snippets.group": "分组",
        "snippets.group_placeholder": "如：开发 / 常用 / 邮件",
        "snippets.shortcode_optional": "快捷短码（可选）",
        "snippets.shortcode_placeholder": "如：;tax、;sig",
        "snippets.existing_groups": "已有分组:",
        "snippets.content": "片段正文",
        "snippets.save": "保存片段",
        "snippets.copy_tip": "复制片段内容",
        "snippets.edit_tip": "编辑片段",
        "snippets.delete_tip": "删除片段",

        // 设置项 - 采集
        "capture.card_retention": "历史容量与留存策略",
        "capture.max_items": "最多保留条数",
        "capture.max_items_sub": "超出上限时自动淘汰最旧的历史记录（已固定的条目永不清除）",
        "capture.items_unit": "%d 条",
        "capture.max_days": "保留天数周期",
        "capture.max_days_sub": "历史记录默认保留的最大时间窗口",
        "capture.days_unit": "%d 天",
        "capture.max_size": "单条内容容量上限",
        "capture.max_size_sub": "单次复制体积超出该阈值的内容将自动丢弃，防止内存过载",
        "capture.card_smart": "智能识别与元数据增强",
        "capture.smart_title": "智能标题生成 (Smart Title)",
        "capture.smart_title_sub": "自动识别代码签名、SQL、CLI命令、Markdown标题及OCR文本，展示更具辨识度的标题",
        "capture.ocr": "图片文字识别 (Vision OCR)",
        "capture.ocr_sub": "复制或截取图片入库时，自动提取图中文本建立索引，图片亦可搜",
        "capture.link_metadata": "网页链接元数据解析",
        "capture.link_metadata_sub": "后台轻量解析复制的 URL 页面标题与图标，列表显示更直观",
        "capture.card_db": "数据库与检索引擎",
        "capture.fts_ready": "SQLite FTS5 全文检索引擎已就绪",
        "capture.fts_fallback": "系统 SQLite 不支持 FTS5，已降级为 LIKE 检索",
        "capture.fts_ready_sub": "支持中文精准分词、倒排索引与毫秒级高亮检索。",
        "capture.fts_fallback_sub": "基础模糊查询可用，但海量数据下检索耗时略有增加。",

        // 设置项 - 隐私
        "privacy.card_blacklist": "忽略应用名单（黑名单）",
        "privacy.blacklist_desc": "当以下应用处于前台运行激活状态时，所有复制的内容均不会被记录：",
        "privacy.empty_blacklist": "当前未添加任何忽略应用",
        "privacy.input_placeholder": "输入应用 Bundle ID（如：com.1password.mac）",
        "privacy.add_frontmost": "一键添加前台应用",
        "privacy.card_security": "采集安全与临时暂停",
        "privacy.pause": "临时暂停采集",
        "privacy.pause_sub": "使用密码管理器或处理高密敏感内容时可临时关闭采集",
        "privacy.security_note": "系统安全自适应：当检测到密码输入框（NSSecureTextField / Concealed）或屏幕锁定状态时，ClipMate 会全自动静默停止采集，无需手动干预。",

        // 设置项 - AI
        "ai.card_core": "AI 核心特性",
        "ai.enable": "启用 AI 智能操作",
        "ai.enable_sub": "在主面板中选中条目后按 ⌘K 唤起工作台，进行快速润色、总结与问答",
        "ai.semantic": "本地语义向量检索",
        "ai.semantic_sub": "利用 macOS 本地句向量按语义理解检索历史，无网络请求与隐私泄露",
        "ai.semantic_unavailable": "当前系统未提供句向量资源，语义搜索不可用（不影响关键词检索）",
        "ai.card_model": "模型服务与 API 配置",
        "ai.endpoint": "API 端点（兼容 OpenAI / Ollama / DeepSeek / 本地服务）",
        "ai.endpoint_placeholder": "https://api.openai.com/v1 或 http://localhost:11434/v1",
        "ai.model_name": "模型名称",
        "ai.model_placeholder": "如：gpt-4o-mini / deepseek-chat / qwen2.5:7b",
        "ai.api_key": "API 密钥（安全存储于本地系统钥匙串 Keychain；本地服务可留空）",
        "ai.save_key": "保存密钥",
        "ai.key_saved": "密钥已保存至本地钥匙串",
        "ai.test_connection": "测试连接",
        "ai.card_prompts": "自定义提示词模板",
        "ai.reset_prompts": "恢复精选模板",
        "ai.prompt_var_note": "支持在提示词中包含 {content} 变量，执行时将自动替换为剪贴板选中的正文。",
        "ai.prompt_name_placeholder": "模板名（如：代码转TS）",
        "ai.prompt_content_placeholder": "提示词内容（包含 {content} 占位变量）",

        // 设置项 - 脚本与快捷动作
        "scripts.card_spec": "脚本与快捷指令规范",
        "scripts.spec_desc": "支持配置 Shell 终端脚本与 macOS 原生快捷指令（Shortcuts）。自定义动作将在主面板快捷动作区与 AI 工作台中展示。选中的剪贴板文本经标准输入（stdin）传入命令，输出结果（stdout）可直接更新回剪贴板或用于二次编辑。所有命令以当前用户权限运行，请勿添加来源不明的危险脚本。",
        "scripts.card_presets": "快捷动作预置库 (Power Tools)",
        "scripts.preset_desc": "一键启用高频极客与办公文本处理工具，无外部依赖，本地极速运行。",
        "scripts.add_preset": "添加",
        "scripts.preset_added": "已添加",
        "scripts.add_all_presets": "一键添加全部预置",
        "scripts.reset_presets": "恢复默认动作",
        "scripts.card_list": "已启用的快捷动作",
        "scripts.empty": "尚未添加任何快捷动作",
        "scripts.card_add": "添加自定义动作",
        "scripts.type_label": "动作类型",
        "scripts.type_shell": "Shell 终端命令",
        "scripts.type_shortcut": "macOS 快捷指令 (Shortcuts)",
        "scripts.name_label": "动作名称",
        "scripts.name_placeholder": "如：提取网址 / 邮箱清洗 / 格式化JSON",
        "scripts.command_label": "命令或快捷指令",
        "scripts.command_placeholder": "如：grep -oE 'https?://[^[:space:]]+' | sort -u",
        "scripts.shortcut_placeholder": "输入快捷指令 App 中的完整名称，如：剪贴板润色",
        "scripts.add_button": "添加动作",

        // 预置动作名称与描述
        "script.preset.preset_timestamp_date": "时间戳转日期",
        "script.preset_desc.preset_timestamp_date": "将当前毫秒/秒级时间戳转换为标准可读日期格式",
        "script.preset.preset_base64_decode": "Base64 解码",
        "script.preset_desc.preset_base64_decode": "标准 Base64 文本解码",
        "script.preset.preset_base64_encode": "Base64 编码",
        "script.preset_desc.preset_base64_encode": "标准 Base64 文本编码",
        "script.preset.preset_json_format": "JSON 美化排版",
        "script.preset_desc.preset_json_format": "美化格式化 JSON，增加 4 空格缩进排版",
        "script.preset.preset_json_minify": "JSON 紧凑压缩",
        "script.preset_desc.preset_json_minify": "压缩 JSON，去除所有冗余空白与换行",
        "script.preset.preset_url_decode": "URL 解码",
        "script.preset_desc.preset_url_decode": "URL 编码转义字符还原解码",
        "script.preset.preset_url_encode": "URL 编码",
        "script.preset_desc.preset_url_encode": "URL 参数安全转义编码",
        "script.preset.preset_sha256": "SHA-256 哈希",
        "script.preset_desc.preset_sha256": "计算输入文本的 256 位安全散列值",
        "script.preset.preset_md5": "MD5 哈希",
        "script.preset_desc.preset_md5": "计算输入文本的 MD5 校验散列值",
        "script.preset.preset_word_count": "字数与行数统计",
        "script.preset_desc.preset_word_count": "快速统计文本行数、词数与总字符数",
        "script.preset.preset_extract_urls": "提取所有网址",
        "script.preset_desc.preset_extract_urls": "正则匹配提取所有 http/https 链接并去重",
        "script.preset.preset_extract_emails": "提取所有邮箱",
        "script.preset_desc.preset_extract_emails": "正则匹配提取所有邮箱地址并去重",
        "script.preset.preset_strip_newlines": "去除所有空行",
        "script.preset_desc.preset_strip_newlines": "清理文本中所有孤立与连续空行",
        "script.preset.preset_snake_case": "转下划线命名",
        "script.preset_desc.preset_snake_case": "将空格或驼峰文本转换为 snake_case 下划线命名",

        // 设置项 - 关于
        "about.version": "版本 %@（macOS 原生架构）",
        "about.card_arch": "原生设计与极致体验",
        "about.arch_bullet1_title": "100% 纯原生架构",
        "about.arch_bullet1_desc": "完全基于 Swift & SwiftUI 原生构筑，零 Electron，极致内存轻量常驻。",
        "about.arch_bullet2_title": "毛玻璃与现代视觉",
        "about.arch_bullet2_desc": "统一 Liquid Glass 设计语言，自适应 macOS 浅色与深色外观。",
        "about.arch_bullet3_title": "本地 SQLite 事务引擎",
        "about.arch_bullet3_desc": "采用 SQLite FTS5 倒排索引，海量历史瞬间模糊匹配与高亮。",
        "about.arch_bullet4_title": "AI 智能原生融合",
        "about.arch_bullet4_desc": "内置本地句向量语义检索与多模型工作台，对话与润色行云流水。",
        "about.card_privacy": "隐私与数据安全",
        "about.privacy_bullet1": "100% 本地存储：所有剪贴板历史与图片全部保存在本机 SQLite 数据库，绝无任何网络上报。",
        "about.privacy_bullet2": "系统安全自适应：密码框（Concealed Type）与锁屏状态下全自动静默停止采集。",
        "about.privacy_bullet3": "辅助功能权限：仅用于通过模拟按键完成选中文本的原生自动粘贴回写。",
        // 设置项 - 软件更新
        "update.card_title": "版本与软件更新",
        "update.current_version": "当前版本 v%@ (Build %@)",
        "update.auto_check": "自动检查更新",
        "update.auto_check_sub": "后台静默检测新版本，在有重要更新时提醒你",
        "update.check_now": "检查更新",
        "update.checking": "正在检查更新…",
        "update.up_to_date": "当前已是最新版本 (v%@)",
        "update.available": "发现新版本 v%@，建议更新以体验最新功能",
        "update.download": "前往下载",
        "update.failed": "检查更新失败，请检查网络后重试",

        // 菜单栏
        "menu.tooltip": "ClipMate 剪贴板历史",
        "menu.empty": "  （暂无历史记录）",
        "menu.open_panel": "打开主面板",
        "menu.resume_capture": "恢复采集",
        "menu.pause_capture": "暂停采集",
        "menu.clear_history": "清空历史（保留固定）",
        "menu.export": "导出历史…",
        "menu.import": "导入历史…",
        "menu.check_updates": "检查更新…",
        "menu.settings": "设置…",
        "menu.quit": "退出 ClipMate",

        // 首次引导
        "onboarding.window_title": "欢迎使用 ClipMate",
        "onboarding.title": "欢迎使用 ClipMate",
        "onboarding.subtitle": "原生的剪贴板历史工具 — 快速、本地、隐私优先",
        "onboarding.feature_hotkey": "按下 %@ 呼出搜索面板",
        "onboarding.feature_privacy": "全部历史保留在本地 SQLite，不上传云端",
        "onboarding.card1_title": "%@ 唤起",
        "onboarding.card1_desc": "⏎ 粘贴 · ⌘⏎ 复制\n⌘K AI · ⇧⏎ 入队连贴",
        "onboarding.card2_title": "隐私默认安全",
        "onboarding.card2_desc": "全本地存储 · 无上报\n密码管理器自动排除",
        "onboarding.card3_title": "AI 与语义搜索",
        "onboarding.card3_desc": "翻译/摘要 · 按含义搜历史\n图片文字识别 · 自定义脚本",
        "onboarding.accessibility_notice": "粘贴回写需要「辅助功能」权限：仅用于替你按一次 ⌘V，不读取屏幕内容，可随时在系统设置中关闭。",
        "onboarding.start": "开始使用",
    ]

    private static let enStrings: [String: String] = [
        "app.launch_failed": "Failed to launch ClipMate",
        // Main Panel
        "search.placeholder": "Search clipboard history…",
        "search.help": "Toggle AI Q&A Sidebar (⌘K / ⌘⇧A)",
        "empty.title": "No clipboard history",
        "empty.subtitle": "Press ⌘C to copy anything, it will automatically appear here",
        "empty.no_match": "No matching items",
        "empty.no_match_sub": "Try a different keyword or category filter",
        "footer.paste": "Paste",
        "footer.copy": "Copy",
        "footer.edit": "Edit",
        "footer.ai": "AI",
        "footer.preview": "Detail",
        "footer.delete": "Delete",
        "footer.cancel": "Cancel",
        "batch.selected": "%d selected",
        "batch.paste_queue": "Paste Queue",
        "batch.copy_all": "Copy Combined",
        "batch.pin_all": "Pin",
        "batch.delete_all": "Delete",
        "batch.cancel": "Cancel",

        // Categories & States
        "filter.all": "All",
        "filter.text": "Text",
        "filter.image": "Image",
        "filter.file": "File",
        "filter.link": "Link",
        "filter.snippet": "Snippets",
        "filter.pinned": "Pinned",
        "filter.queue": "Queue %d",
        "filter.queue_tip": "Press ⌘⇧⏎ to paste queue items in order",
        "filter.paused": "Capture Paused",
        "filter.all_snippets": "All Snippets",
        "filter.new_snippet": "New Snippet",

        // Clip kinds
        "kind.text": "Text",
        "kind.url": "Link",
        "kind.richText": "Rich Text",
        "kind.image": "Image",
        "kind.file": "File",
        "kind.pdf": "PDF",

        // Auto Tags
        "tag.code": "Code",
        "tag.long_text": "Long Text",
        "tag.link": "Link",
        "tag.image": "Image",
        "tag.file": "File",
        "tag.rich_text": "Rich Text",
        "tag.email": "Email",
        "tag.has_link": "Has Link",
        "tag.color": "Color",
        "tag.snippet": "Snippet",
        "tag.pdf": "PDF",
        "tag.json": "JSON",

        // Relative time
        "time.now": "Just now",
        "time.mins_ago": "%dm ago",
        "time.hours_ago": "%dh ago",
        "time.days_ago": "%dd ago",

        // Metadata & Units
        "meta.source": "Source",
        "meta.time": "Time",
        "meta.size": "Size",
        "meta.used": "Used",
        "meta.uses_count": "%d times",
        "meta.chars": "%d characters",
        "meta.chars_unit": "%d chars",
        "meta.lines": "%d lines",
        "meta.items": "%d items",

        // Common actions
        "action.copy": "Copy",
        "action.copied": "Copied",
        "action.paste": "Paste",
        "action.direct_paste": "Direct Paste ⏎",
        "action.edit": "Edit",
        "action.delete": "Delete",
        "action.cancel": "Cancel",
        "action.save": "Save",
        "action.confirm": "Confirm",
        "action.open": "Open",
        "action.add": "Add",
        "action.reset": "Reset",
        "action.close": "Close",
        "action.paste_plain": "Paste as Plain Text",
        "action.copy_plain": "Copy as Plain Text",
        "action.pin": "Pin ★",
        "action.unpin": "Unpin",
        "action.edit_snippet": "Edit Snippet…",
        "action.remove_snippet": "Remove from Snippets",
        "action.save_snippet": "Save as Snippet…",
        "action.edit_item": "Edit…",
        "toast.paste_fallback.title": "Unable to paste to target app",
        "toast.paste_fallback.manual_hint": "Content kept in clipboard, press ⌘V to paste manually",
        "toast.paste_fallback.permission": "Accessibility permission missing",
        "toast.paste_fallback.permission_hint": "Content written to clipboard, press ⌘V to paste (grant in System Settings)",
        "toast.paste_fallback.target_lost": "Target app is unavailable or has terminated",
        "toast.paste_queue_aborted": "New copy detected, queue paste aborted",
        "toast.paste_queue_aborted_hint": "Your latest clipboard content is preserved",
        "action.mute_action": "Recommend this action less",
        "action.copy_only": "Copy Only",
        "action.more_fields": "+%d more",
        "action.collapse_fields": "Less",
        "action.copy_ocr": "Copy Text",
        "action.fix_line_breaks": "Fix Line Breaks",
        "action.deduplicate_list": "Deduplicate",
        "action.format_json": "Format JSON",
        "action.translate": "Translate",
        "action.translate_to_zh": "Translate to Chinese",
        "action.translate_to_en": "Translate to English",
        "action.view_original": "View Original",
        "action.view_result": "View Result",
        "action.retry": "Retry",
        "action.cancelling": "Cancelling…",
        "action.processing": "Processing…",
        "action.diff_deduped": "Removed %d duplicates",
        "action.diff_breaks_fixed": "Line breaks fixed",
        "action.diff_json_formatted": "JSON formatted",
        "action.target_language": "Target Language",
        "action.need_ai_config": "Please configure AI endpoint & model in Settings",
        "action.open_settings": "Settings",
        "action.compare": "Compare",
        "action.result_card_title": "Action Result",
        "rec.title": "Smart Suggestions",
        "rec.app_frequent": "Common in this App",
        "rec.same_material": "Same Source",
        "rec.sequence": "Frequently Used Next",
        "rec.dismiss": "Hide Suggestion",
        "settings.recommendations_title": "Smart Suggestions",
        "settings.recommendations_desc": "Show up to 3 context-aware suggestions at the top based on app and usage history",
        "settings.clear_rec_learning": "Clear Learning History",
        "settings.clear_rec_learning_done": "Learning history cleared",
        "preview.extracted_fields": "Extracted Fields",
        "preview.highlight_in_source": "Locate in Source",
        "search.syntax_hint": "Search syntax:\n#11 = exactly 11 digits · #>8 / #<12 = digit count range\nlen:>8 = content longer than 8 · app:Slack = source app\nbefore:yesterday / after:2026-09-01 = date range · 138* = prefix match",
        "filter.number": "Numbers",
        "tag.phone": "Phone",
        "tag.telephone": "Landline",
        "tag.bank_card": "Bank Card",
        "tag.id_card": "ID Card",
        "tag.tracking": "Tracking No.",
        "tag.ip": "IP",
        "tag.amount": "Amount",
        "tag.number": "Number",
        "filter.all_sources": "All Sources",
        "filter.clear_context": "Clear source & time filters",
        "time.all": "All Time",
        "time.today": "Today",
        "time.yesterday": "Yesterday",
        "time.last3Days": "Last 3 Days",
        "time.thisWeek": "This Week",
        "time.thisMonth": "This Month",
        "action.rename": "Rename…",
        "action.clear_title": "Clear Custom Title",
        "action.preview": "Detail Preview",
        "overlay.rename.title": "Rename Item",
        "overlay.rename.subtitle": "Give this clip a memorable name so you can find it by name later",
        "overlay.rename.placeholder": "e.g. Bank card number / Office phone / Order 2026-09",
        "overlay.rename.clear": "Clear Title",
        "action.queue_add": "Add to Paste Queue",
        "action.queue_remove": "Remove from Paste Queue",
        "action.ai_actions": "AI Actions…",
        "batch.copy_count": "Copy %d Selected",
        "batch.toggle_pin": "Toggle Pin for Selected",
        "batch.add_queue": "Add Selected to Queue",
        "batch.delete_count": "Delete %d Selected",

        // Overlays
        "overlay.edit.title": "Edit Content",
        "overlay.edit.subtitle": "Changes will update history and copy to clipboard",
        "overlay.edit.save_copy": "Save & Copy",
        "overlay.clear.title": "Clear All History?",
        "overlay.clear.subtitle": "Pinned items will be preserved, but unpinned records cannot be recovered.",
        "overlay.clear.confirm": "Confirm Clear",
        "overlay.snippet.title_new": "New Snippet",
        "overlay.snippet.title_edit": "Edit Snippet",
        "overlay.snippet.subtitle": "Save reusable text templates with shortcode support",
        "overlay.snippet.title_label": "Snippet Title (Optional)",
        "overlay.snippet.title_placeholder": "e.g. Invoice Info, Git Flow, Signature…",
        "overlay.snippet.group_label": "Group",
        "overlay.snippet.group_placeholder": "Dev / General / Email…",
        "overlay.snippet.shortcode_label": "Shortcode (Optional)",
        "overlay.snippet.shortcode_placeholder": ";tax / ;git / ;sig…",
        "overlay.snippet.content_label": "Snippet Body",
        "overlay.snippet.content_placeholder": "Paste or type snippet text here…",
        "overlay.snippet.save": "Save Snippet",

        // Detail Preview (⌘I)
        "preview.pinned": "Pinned",
        "preview.image_unavailable": "Image data unavailable",
        "preview.ocr_title": "Detected Text (Vision OCR)",
        "preview.ocr_copy": "Copy Text",
        "preview.pdf_unavailable": "PDF preview unavailable",
        "preview.pdf_extracted": "Extracted Text",
        "preview.url_default": "Web Link",
        "preview.url_open_tip": "Open link in default browser",
        "preview.url_full": "Full Link",
        "preview.url_copy": "Copy Link",
        "preview.json_title": "JSON Data",
        "preview.json_format": "Format JSON",
        "preview.json_raw": "Raw View",
        "preview.json_copy": "Copy Formatted",
        "preview.code_title": "Code Highlighting",
        "preview.code_copy": "Copy Code",
        "preview.file_title": "File List",
        "preview.file_locate_tip": "Locate in Finder",
        "preview.text_title": "Body Text",
        "preview.tip_delete": "Delete item (⌫)",
        "preview.tip_edit": "Edit item (⌘E)",
        "preview.tip_snippet_edit": "Snippet Settings",
        "preview.tip_snippet_save": "Save as Snippet",
        "preview.tip_queue_remove": "Remove from Queue",
        "preview.tip_queue_add": "Add to Queue",
        "preview.shortcut_bar": "⏎ Paste · ⌘⏎ Copy · Esc Close",

        // AI Sidebar & Workspace
        "ai.sidebar_title": "AI Q&A",
        "ai.workspace_title": "AI Workspace · Ask Clipboard",
        "ai.status_configured": "OpenAI Compatible",
        "ai.status_unconfigured": "Not configured (Settings → AI)",
        "ai.tip_clear_chat": "Reset conversation & clear history",
        "ai.clear_chat": "Clear Chat",
        "ai.tip_collapse_sidebar": "Collapse AI Sidebar (⌘K / ⌘⇧A)",
        "ai.tip_close_esc": "Close (Esc)",
        "ai.select_item_hint": "Select an item on the left to analyze and chat",
        "ai.image_ocr_hint": "(Image item: you can ask about recognized text)",
        "ai.empty_chat_title": "Ask AI / Follow-up",
        "ai.empty_chat_subtitle": "Click a quick template above or ask freely below.\nSupports multi-turn follow-ups and code/text analysis.",
        "ai.workspace_empty_subtitle": "Press ⌘K in the main panel to open this workspace for multi-turn chat on any clipboard content.",
        "ai.response_title": "AI Response",
        "ai.role_user": "You",
        "ai.drag_hint": "Drag empty space to move",
        "ai.thinking": "Thinking and analyzing…",
        "ai.prompt_placeholder_new": "Ask AI freely about clipboard (⏎ to send)…",
        "ai.prompt_placeholder_followup": "Follow up…",
        "ai.tip_send": "Send (Return)",
        "ai.copy_latest": "Copy Latest",
        "ai.save_as_new": "Save as New Item",
        "ai.direct_paste": "Direct Paste ⏎",
        "ai.tpl.translate": "Translate",
        "ai.tpl.summary": "Summary",
        "ai.tpl.summarize": "Key Points",
        "ai.tpl.explainCode": "Explain Code",
        "ai.tpl.grammar": "Fix Grammar",
        "ai.tpl.rewrite": "Rewrite",
        "ai.tpl.unitTest": "Unit Tests",
        "ai.tpl.jsonToTS": "JSON to TS",

        // Panel position & Language
        "position.center": "Center Screen (Active Display)",
        "position.followCursor": "Follow Mouse Cursor",
        "position.remember": "Remember Last Position",
        "language.system": "System Default",

        // Settings Tabs
        "tab.general": "General",
        "tab.snippets": "Snippets",
        "tab.capture": "Capture",
        "tab.privacy": "Privacy",
        "tab.ai": "AI",
        "tab.scripts": "Scripts",
        "tab.about": "About",

        // Settings items - Theme & Appearance
        "settings.theme.card_title": "Appearance & Theme",
        "settings.theme.desc": "Curated popular color palettes with instant live preview, combining macOS vibrancy with iconic editor aesthetics.",
        "theme.default": "Default Glass",
        "theme.desc.default": "Native macOS vibrancy, clean frosted glass, adapts to light/dark",
        "theme.oneDarkPro": "One Dark Pro",
        "theme.desc.oneDarkPro": "Iconic Atom & VS Code dark slate with signature cyan and blue accents",
        "theme.dracula": "Dracula",
        "theme.desc.dracula": "Iconic vampire dark palette with signature purple, neon pink, cyan & green",
        "theme.darcula": "Dracula",
        "theme.desc.darcula": "Iconic vampire dark palette with signature purple, neon pink, cyan & green",
        "theme.tokyoNight": "Tokyo Night",
        "theme.desc.tokyoNight": "Cyberpunk deep indigo night with vivid neon pink & cyan accents",
        "theme.nord": "Nord",
        "theme.desc.nord": "Arctic polar night palette with clean frost & ice accents",
        "theme.monokai": "Monokai",
        "theme.desc.monokai": "Classic high-contrast hacker dark with vibrant yellow & magenta",
        "theme.githubLight": "GitHub Light",
        "theme.desc.githubLight": "Crisp paper white canvas with GitHub signature blue accents",

        // Settings items - General
        "settings.general.card_interaction": "Interaction & General",
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
        "settings.backup.card_title": "Backup & Migration",
        "settings.backup.stats": "History: %d · Snippets: %d",
        "settings.backup.desc": "Export all local clipboard history and snippets to a JSON backup file for lossless migration and restoration.",
        "settings.backup.export": "Export Full Backup (JSON)",
        "settings.backup.import": "Restore from Backup (JSON)",
        "settings.backup.export_title": "Export Clipboard History & Snippets Backup",
        "settings.backup.export_success": "Export Successful",
        "settings.backup.export_success_msg": "Successfully backed up %d items to:\n%@",
        "settings.backup.export_failed": "Export Failed",
        "settings.backup.import_title": "Restore from Backup File",
        "settings.backup.import_success": "Restore Successful",
        "settings.backup.import_success_msg": "Successfully imported %d items (duplicates skipped).",
        "settings.backup.import_failed": "Restore Failed",
        "settings.shortcuts.card_title": "Main Panel Shortcuts Guide",
        "settings.shortcuts.paste": "Paste at current cursor",
        "settings.shortcuts.copy": "Copy to clipboard & top",
        "settings.shortcuts.edit": "Quick edit inline",
        "settings.shortcuts.ai": "Summon AI Assistant",
        "settings.shortcuts.preview": "Toggle Detail Preview drawer",
        "settings.shortcuts.quick_paste": "Quick paste item by index",
        "settings.shortcuts.multiselect": "Select multiple records",
        "settings.shortcuts.switch_tab": "Cycle through category tabs",

        // Settings items - Snippets
        "snippets.search_placeholder": "Search snippet title, content, or shortcode…",
        "snippets.all_groups": "All Groups",
        "snippets.new": "New Snippet",
        "snippets.empty": "No snippets yet",
        "snippets.empty_sub": "Click 'New Snippet' above or save any item from the main panel",
        "snippets.no_match": "No matching snippets",
        "snippets.editor_title_new": "New Snippet",
        "snippets.editor_title_edit": "Edit Snippet",
        "snippets.editor_subtitle": "Enter snippet details for quick insertion across the app",
        "snippets.title_optional": "Snippet Title (Optional)",
        "snippets.title_placeholder": "e.g. Invoice Info, Git Flow, Signature…",
        "snippets.group": "Group",
        "snippets.group_placeholder": "e.g. Dev / General / Email",
        "snippets.shortcode_optional": "Shortcode (Optional)",
        "snippets.shortcode_placeholder": "e.g. ;tax, ;sig",
        "snippets.existing_groups": "Existing Groups:",
        "snippets.content": "Snippet Body",
        "snippets.save": "Save Snippet",
        "snippets.copy_tip": "Copy snippet content",
        "snippets.edit_tip": "Edit snippet",
        "snippets.delete_tip": "Delete snippet",

        // Settings items - Capture
        "capture.card_retention": "Retention & Capacity Policy",
        "capture.max_items": "Max Stored Items",
        "capture.max_items_sub": "Oldest non-pinned items are automatically purged when limit is reached",
        "capture.items_unit": "%d items",
        "capture.max_days": "Retention Period",
        "capture.max_days_sub": "Maximum duration clipboard history is preserved",
        "capture.days_unit": "%d days",
        "capture.max_size": "Max Item Size",
        "capture.max_size_sub": "Items exceeding this threshold are discarded to prevent memory overload",
        "capture.card_smart": "Smart Recognition & Metadata",
        "capture.smart_title": "Smart Title Generation",
        "capture.smart_title_sub": "Extract recognizable titles for code functions, SQL, CLI commands, Markdown headers and OCR text",
        "capture.ocr": "Vision OCR Recognition",
        "capture.ocr_sub": "Automatically extract text from images to make images searchable",
        "capture.link_metadata": "URL Metadata Fetching",
        "capture.link_metadata_sub": "Fetch title and favicon in background for copied web URLs",
        "capture.card_db": "Database & Search Engine",
        "capture.fts_ready": "SQLite FTS5 Full-Text Search Engine is ready",
        "capture.fts_fallback": "System SQLite lacks FTS5, running in LIKE fallback mode",
        "capture.fts_ready_sub": "Supports tokenization, inverted indexing, and sub-millisecond highlighted search.",
        "capture.fts_fallback_sub": "Basic fuzzy search is active, but large history queries may take slightly longer.",

        // Settings items - Privacy
        "privacy.card_blacklist": "Excluded Applications (Blacklist)",
        "privacy.blacklist_desc": "When any of the following applications are active, copied contents will not be recorded:",
        "privacy.empty_blacklist": "No excluded applications added",
        "privacy.input_placeholder": "Enter Application Bundle ID (e.g. com.1password.mac)",
        "privacy.add_frontmost": "Add Current Frontmost App",
        "privacy.card_security": "Capture Safety & Pause",
        "privacy.pause": "Temporarily Pause Capture",
        "privacy.pause_sub": "Disable capture while handling sensitive or confidential data",
        "privacy.security_note": "Adaptive System Safety: When a password field (NSSecureTextField / Concealed) or screen lock is detected, ClipMate automatically and silently suspends capture without manual intervention.",

        // Settings items - AI
        "ai.card_core": "Core AI Features",
        "ai.enable": "Enable AI Smart Actions",
        "ai.enable_sub": "Press ⌘K on any item in main panel to open AI workspace for rewrites, summaries, and chat",
        "ai.semantic": "Local Semantic Vector Search",
        "ai.semantic_sub": "Search history by meaning using on-device macOS embeddings with zero network requests and complete privacy",
        "ai.semantic_unavailable": "On-device embeddings are unavailable on this system; keyword search remains fully functional",
        "ai.card_model": "Model Service & API Configuration",
        "ai.endpoint": "API Endpoint (OpenAI / Ollama / DeepSeek / Local compatible)",
        "ai.endpoint_placeholder": "https://api.openai.com/v1 or http://localhost:11434/v1",
        "ai.model_name": "Model Name",
        "ai.model_placeholder": "e.g. gpt-4o-mini / deepseek-chat / qwen2.5:7b",
        "ai.api_key": "API Key (Stored securely in macOS Keychain; optional for local models)",
        "ai.save_key": "Save Key",
        "ai.key_saved": "Key saved to macOS Keychain",
        "ai.test_connection": "Test Connection",
        "ai.card_prompts": "Custom Prompt Templates",
        "ai.reset_prompts": "Reset to Default Templates",
        "ai.prompt_var_note": "Use {content} in prompt text; it will be automatically replaced with the selected clipboard content.",
        "ai.prompt_name_placeholder": "Template name (e.g. Code to TS)",
        "ai.prompt_content_placeholder": "Prompt text (includes {content} variable)",

        // Settings items - Scripts & Quick Actions
        "scripts.card_spec": "Script & Shortcut Action Specification",
        "scripts.spec_desc": "Supports Shell commands and native macOS Shortcuts. Custom actions appear in the quick action bar and AI workspace. Selected clipboard text is passed via stdin, and stdout becomes the result. Scripts run with your user permissions; do not configure untrusted commands.",
        "scripts.card_presets": "Action Preset Library (Power Tools)",
        "scripts.preset_desc": "One-click access to curated developer and productivity tools. Pure native, zero external dependencies.",
        "scripts.add_preset": "Add",
        "scripts.preset_added": "Added",
        "scripts.add_all_presets": "Add All Presets",
        "scripts.reset_presets": "Reset to Defaults",
        "scripts.card_list": "Configured Quick Actions",
        "scripts.empty": "No quick actions configured yet",
        "scripts.card_add": "Add Custom Action",
        "scripts.type_label": "Action Type",
        "scripts.type_shell": "Shell Command",
        "scripts.type_shortcut": "macOS Shortcut",
        "scripts.name_label": "Action Name",
        "scripts.name_placeholder": "e.g. Extract URLs / Clean Emails / Prettify JSON",
        "scripts.command_label": "Command or Shortcut",
        "scripts.command_placeholder": "e.g. grep -oE 'https?://[^[:space:]]+' | sort -u",
        "scripts.shortcut_placeholder": "Shortcut name in macOS Shortcuts app, e.g. Polish Text",
        "scripts.add_button": "Add Action",

        // Preset action names and descriptions
        "script.preset.preset_timestamp_date": "Timestamp to Date",
        "script.preset_desc.preset_timestamp_date": "Convert timestamp (ms/s) to readable date format",
        "script.preset.preset_base64_decode": "Base64 Decode",
        "script.preset_desc.preset_base64_decode": "Decode standard Base64 string",
        "script.preset.preset_base64_encode": "Base64 Encode",
        "script.preset_desc.preset_base64_encode": "Encode input text into Base64 format",
        "script.preset.preset_json_format": "JSON Prettify",
        "script.preset_desc.preset_json_format": "Format JSON with clean 4-space indentation",
        "script.preset.preset_json_minify": "JSON Minify",
        "script.preset_desc.preset_json_minify": "Minify JSON into single line compact string",
        "script.preset.preset_url_decode": "URL Decode",
        "script.preset_desc.preset_url_decode": "Decode percent-encoded URL characters",
        "script.preset.preset_url_encode": "URL Encode",
        "script.preset_desc.preset_url_encode": "Percent-encode string for safe URL usage",
        "script.preset.preset_sha256": "SHA-256 Hash",
        "script.preset_desc.preset_sha256": "Compute 256-bit cryptographic SHA-256 checksum",
        "script.preset.preset_md5": "MD5 Hash",
        "script.preset_desc.preset_md5": "Compute 128-bit MD5 checksum",
        "script.preset.preset_word_count": "Word & Line Count",
        "script.preset_desc.preset_word_count": "Calculate lines, words, and characters count",
        "script.preset.preset_extract_urls": "Extract All URLs",
        "script.preset_desc.preset_extract_urls": "Regex extract all http/https links with deduplication",
        "script.preset.preset_extract_emails": "Extract All Emails",
        "script.preset_desc.preset_extract_emails": "Regex extract all email addresses with deduplication",
        "script.preset.preset_strip_newlines": "Remove Blank Lines",
        "script.preset_desc.preset_strip_newlines": "Strip all empty and redundant blank lines",
        "script.preset.preset_snake_case": "Convert to snake_case",
        "script.preset_desc.preset_snake_case": "Convert spaces and camelCase to snake_case",

        // Settings items - About
        "about.version": "Version %@ (Native macOS Architecture)",
        "about.card_arch": "Native Design & Peak Experience",
        "about.arch_bullet1_title": "100% Pure Native Architecture",
        "about.arch_bullet1_desc": "Built entirely with Swift & SwiftUI, zero Electron, ultra-lightweight background memory footprint.",
        "about.arch_bullet2_title": "Liquid Glass Visuals",
        "about.arch_bullet2_desc": "Unified Liquid Glass design language, adapting seamlessly to light and dark macOS appearance.",
        "about.arch_bullet3_title": "Local SQLite Transaction Engine",
        "about.arch_bullet3_desc": "Powered by SQLite FTS5 inverted indexing for instantaneous matching and search highlighting.",
        "about.arch_bullet4_title": "Seamless AI Integration",
        "about.arch_bullet4_desc": "Built-in local semantic embeddings and multi-model workspace for seamless chat and rewrites.",
        "about.card_privacy": "Privacy & Data Safety",
        "about.privacy_bullet1": "100% Local Storage: All clipboard history and images are stored in a local SQLite database, with zero data uploaded.",
        "about.privacy_bullet2": "Adaptive System Safety: Capture automatically and silently suspends on password fields (Concealed Type) and screen lock.",
        "about.privacy_bullet3": "Accessibility Permission: Used strictly to simulate keystrokes for native automatic pasteback.",
        "about.copyright": "Copyright © 2026 ClipMate. Designed for macOS.",

        // Settings - Software Update
        "update.card_title": "Version & Software Update",
        "update.current_version": "Current version v%@ (Build %@)",
        "update.auto_check": "Automatically check for updates",
        "update.auto_check_sub": "Silently check for new versions in the background and notify on important updates",
        "update.check_now": "Check for Updates",
        "update.checking": "Checking for updates…",
        "update.up_to_date": "ClipMate is up to date (v%@)",
        "update.available": "New version v%@ is available. Update recommended.",
        "update.download": "Download",
        "update.failed": "Failed to check for updates. Please check your network connection.",

        // MenuBar
        "menu.tooltip": "ClipMate Clipboard History",
        "menu.empty": "  (No clipboard history)",
        "menu.open_panel": "Open Main Panel",
        "menu.resume_capture": "Resume Capture",
        "menu.pause_capture": "Pause Capture",
        "menu.clear_history": "Clear History (Keep Pinned)",
        "menu.export": "Export History…",
        "menu.import": "Import History…",
        "menu.check_updates": "Check for Updates…",
        "menu.settings": "Settings…",
        "menu.quit": "Quit ClipMate",

        // Onboarding
        "onboarding.window_title": "Welcome to ClipMate",
        "onboarding.title": "Welcome to ClipMate",
        "onboarding.subtitle": "Native clipboard manager — fast, local, privacy-first",
        "onboarding.feature_hotkey": "Press %@ to summon the search panel",
        "onboarding.feature_privacy": "All history stays in local SQLite, never uploaded to cloud",
        "onboarding.card1_title": "Press %@ to Summon",
        "onboarding.card1_desc": "⏎ Paste · ⌘⏎ Copy\n⌘K AI · ⇧⏎ Queue",
        "onboarding.card2_title": "Privacy First",
        "onboarding.card2_desc": "100% Local · No Telemetry\nPassword Managers Excluded",
        "onboarding.card3_title": "AI & Semantic Search",
        "onboarding.card3_desc": "Translate/Summarize · Meaning Search\nVision OCR · Custom Scripts",
        "onboarding.accessibility_notice": "Auto-paste requires Accessibility permission: solely used to simulate ⌘V once, never reads screen content, and can be revoked at any time.",
        "onboarding.start": "Get Started",
    ]
}
