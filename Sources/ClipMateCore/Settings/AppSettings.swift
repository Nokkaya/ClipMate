import Foundation
import Combine
import ServiceManagement
import Carbon.HIToolbox

public struct HotkeyPreset: Identifiable, Equatable {
    public let id: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let display: String
}

public enum PanelPositionMode: String, CaseIterable, Identifiable, Codable {
    case center = "center"
    case followCursor = "followCursor"
    case remember = "remember"

    public var id: String { rawValue }
}

public enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case system = "system"
    case zhHans = "zhHans"
    case en = "en"

    public var id: String { rawValue }
}


public enum ScriptType: String, Codable, CaseIterable {
    case shell = "shell"
    case shortcut = "shortcut"
}

/// 用户自定义脚本与快捷指令动作：剪贴板文本经 stdin 传入命令，stdout 作为结果。
public struct ScriptAction: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var command: String
    public var type: ScriptType
    public var icon: String

    public init(id: String = UUID().uuidString, name: String, command: String, type: ScriptType = .shell, icon: String = "terminal") {
        self.id = id
        self.name = name
        self.command = command
        self.type = type
        self.icon = icon
    }

    enum CodingKeys: String, CodingKey {
        case id, name, command, type, icon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.name = try container.decode(String.self, forKey: .name)
        self.command = try container.decode(String.self, forKey: .command)
        self.type = try container.decodeIfPresent(ScriptType.self, forKey: .type) ?? .shell
        self.icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? (self.type == .shortcut ? "bolt.horizontal.fill" : "terminal")
    }

    /// 极客预置动作库
    public static let presetLibrary: [ScriptAction] = [
        ScriptAction(
            id: "preset_timestamp_date",
            name: "时间戳转日期",
            command: "python3 -c \"import sys, datetime; raw=sys.stdin.read().strip(); ts=float(raw); print(datetime.datetime.fromtimestamp(ts/1000 if ts>1e11 else ts).strftime('%Y-%m-%d %H:%M:%S'))\"",
            type: .shell,
            icon: "clock.arrow.circlepath"
        ),
        ScriptAction(
            id: "preset_base64_decode",
            name: "Base64 解码",
            command: "base64 --decode",
            type: .shell,
            icon: "lock.open.fill"
        ),
        ScriptAction(
            id: "preset_base64_encode",
            name: "Base64 编码",
            command: "base64",
            type: .shell,
            icon: "lock.fill"
        ),
        ScriptAction(
            id: "preset_json_format",
            name: "JSON 美化排版",
            command: "python3 -m json.tool",
            type: .shell,
            icon: "curlybraces"
        ),
        ScriptAction(
            id: "preset_json_minify",
            name: "JSON 紧凑压缩",
            command: "python3 -c \"import sys, json; print(json.dumps(json.loads(sys.stdin.read()), separators=(',', ':')))\"",
            type: .shell,
            icon: "arrow.right.to.line.compact"
        ),
        ScriptAction(
            id: "preset_url_decode",
            name: "URL 解码",
            command: "python3 -c \"import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))\"",
            type: .shell,
            icon: "link"
        ),
        ScriptAction(
            id: "preset_url_encode",
            name: "URL 编码",
            command: "python3 -c \"import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))\"",
            type: .shell,
            icon: "link.badge.plus"
        ),
        ScriptAction(
            id: "preset_sha256",
            name: "SHA-256 哈希",
            command: "shasum -a 256 | awk '{print $1}'",
            type: .shell,
            icon: "number"
        ),
        ScriptAction(
            id: "preset_md5",
            name: "MD5 哈希",
            command: "md5 -q",
            type: .shell,
            icon: "number.circle"
        ),
        ScriptAction(
            id: "preset_word_count",
            name: "字数与行数统计",
            command: "wc -l -w -m | awk '{print \"行数: \" $1 \"  词数: \" $2 \"  字符数: \" $3}'",
            type: .shell,
            icon: "text.word.spacing"
        ),
        ScriptAction(
            id: "preset_extract_urls",
            name: "提取所有网址",
            command: "grep -oE 'https?://[^[:space:]<>\"]+' | sort -u",
            type: .shell,
            icon: "globe"
        ),
        ScriptAction(
            id: "preset_extract_emails",
            name: "提取所有邮箱",
            command: "grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}' | sort -u",
            type: .shell,
            icon: "envelope"
        ),
        ScriptAction(
            id: "preset_strip_newlines",
            name: "去除所有空行",
            command: "awk 'NF'",
            type: .shell,
            icon: "line.horizontal.3.decrease"
        ),
        ScriptAction(
            id: "preset_snake_case",
            name: "转下划线命名",
            command: "tr '[:upper:]' '[:lower:]' | tr ' ' '_'",
            type: .shell,
            icon: "textformat.characters"
        ),
    ]

    /// 首次启动默认启用的预置动作
    public static let defaultPresets: [ScriptAction] = [
        presetLibrary[0], // 时间戳转日期
        presetLibrary[1], // Base64 解码
        presetLibrary[3], // JSON 美化排版
        presetLibrary[9], // 字数与行数统计
    ]
}

/// 应用设置（UserDefaults 持久化；API Key 走 Keychain）。
public final class AppSettings: ObservableObject {
    public static let hotkeyChangedNotification = Notification.Name("clipmate.hotkeyChanged")
    public static let languageChangedNotification = Notification.Name("clipmate.languageChanged")
    public static let themeChangedNotification = Notification.Name("clipmate.themeChanged")

    public static let hotkeyPresets: [HotkeyPreset] = [
        HotkeyPreset(id: "cmdShiftV", keyCode: UInt32(kVK_ANSI_V),
                     modifiers: UInt32(cmdKey) | UInt32(shiftKey), display: "⌘⇧V"),
        HotkeyPreset(id: "cmdOptV", keyCode: UInt32(kVK_ANSI_V),
                     modifiers: UInt32(cmdKey) | UInt32(optionKey), display: "⌘⌥V"),
        HotkeyPreset(id: "ctrlOptV", keyCode: UInt32(kVK_ANSI_V),
                     modifiers: UInt32(controlKey) | UInt32(optionKey), display: "⌃⌥V"),
        HotkeyPreset(id: "f9", keyCode: UInt32(kVK_F9), modifiers: 0, display: "F9"),
    ]

    /// 内置敏感应用黑名单（可由用户增删）。
    public static let defaultExcludedApps = [
        "com.1password.1password",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "io.github.keepassxc.KeePassXC",
    ]

    private let defaults: UserDefaults

    @Published public var hotkeyPresetID: String {
        didSet { defaults.set(hotkeyPresetID, forKey: "hotkeyPresetID")
            NotificationCenter.default.post(name: Self.hotkeyChangedNotification, object: nil) }
    }
    @Published public var retentionMaxItems: Int {
        didSet { defaults.set(retentionMaxItems, forKey: "retentionMaxItems") }
    }
    @Published public var retentionMaxAgeDays: Int {
        didSet { defaults.set(retentionMaxAgeDays, forKey: "retentionMaxAgeDays") }
    }
    @Published public var maxCaptureMB: Int {
        didSet { defaults.set(maxCaptureMB, forKey: "maxCaptureMB") }
    }
    @Published public var excludedApps: [String] {
        didSet { defaults.set(excludedApps, forKey: "excludedApps") }
    }
    @Published public var soundOnCapture: Bool {
        didSet { defaults.set(soundOnCapture, forKey: "soundOnCapture") }
    }
    @Published public var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: "launchAtLogin"); applyLaunchAtLogin() }
    }
    @Published public var pauseCapture: Bool {
        didSet { defaults.set(pauseCapture, forKey: "pauseCapture") }
    }
    @Published public var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: "aiEnabled") }
    }
    @Published public var aiEndpoint: String {
        didSet { defaults.set(aiEndpoint, forKey: "aiEndpoint") }
    }
    @Published public var aiModel: String {
        didSet { defaults.set(aiModel, forKey: "aiModel") }
    }
    @Published public var imageOCREnabled: Bool {
        didSet { defaults.set(imageOCREnabled, forKey: "imageOCREnabled") }
    }
    @Published public var semanticSearchEnabled: Bool {
        didSet { defaults.set(semanticSearchEnabled, forKey: "semanticSearchEnabled") }
    }
    @Published public var fetchLinkMetadata: Bool {
        didSet { defaults.set(fetchLinkMetadata, forKey: "fetchLinkMetadata") }
    }
    @Published public var customScripts: [ScriptAction] {
        didSet {
            if let data = try? JSONEncoder().encode(customScripts) {
                defaults.set(data, forKey: "customScripts")
            }
        }
    }
    @Published public var hapticFeedbackEnabled: Bool {
        didSet {
            defaults.set(hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled")
            HapticHelper.isEnabled = hapticFeedbackEnabled
        }
    }
    @Published public var customPrompts: [PromptTemplate] {
        didSet {
            if let data = try? JSONEncoder().encode(customPrompts) {
                defaults.set(data, forKey: "customPrompts")
            }
        }
    }
    @Published public var panelPositionMode: PanelPositionMode {
        didSet { defaults.set(panelPositionMode.rawValue, forKey: "panelPositionMode") }
    }
    @Published public var smartTitleEnabled: Bool {
        didSet { defaults.set(smartTitleEnabled, forKey: "smartTitleEnabled") }
    }
    @Published public var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: "appLanguage")
            L10n.overrideLanguage = appLanguage
            NotificationCenter.default.post(name: Self.languageChangedNotification, object: nil)
        }
    }
    @Published public var appTheme: AppTheme {
        didSet {
            defaults.set(appTheme.rawValue, forKey: "appTheme")
            Palette.currentTheme = appTheme
            NotificationCenter.default.post(name: Self.themeChangedNotification, object: appTheme)
        }
    }
    @Published public var lastPanelPositionX: Double? {
        didSet { defaults.set(lastPanelPositionX, forKey: "lastPanelPositionX") }
    }
    @Published public var lastPanelPositionY: Double? {
        didSet { defaults.set(lastPanelPositionY, forKey: "lastPanelPositionY") }
    }
    @Published public var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: "autoCheckUpdates") }
    }
    @Published public var lastUpdateCheckDate: Date? {
        didSet { defaults.set(lastUpdateCheckDate, forKey: "lastUpdateCheckDate") }
    }

    /// 智能内容推荐开关
    @Published public var enableSmartRecommendations: Bool {
        didSet { defaults.set(enableSmartRecommendations, forKey: "enableSmartRecommendations") }
    }
    /// 内容控件开关
    @Published public var enableInteractiveClips: Bool {
        didSet { defaults.set(enableInteractiveClips, forKey: "enableInteractiveClips") }
    }
    /// 内容控件仅本地离线识别
    @Published public var interactiveClipsLocalOnly: Bool {
        didSet { defaults.set(interactiveClipsLocalOnly, forKey: "interactiveClipsLocalOnly") }
    }
    /// 粘贴变焦开关
    @Published public var enablePasteZoom: Bool {
        didSet { defaults.set(enablePasteZoom, forKey: "enablePasteZoom") }
    }
    /// 推荐学习本地存储数据
    @Published public var recommendationStore: RecommendationLearningStore {
        didSet {
            if let data = try? JSONEncoder().encode(recommendationStore) {
                defaults.set(data, forKey: "recommendationStore")
            }
        }
    }

    public func clearRecommendationLearningData() {
        recommendationStore.clear()
        defaults.removeObject(forKey: "recommendationStore")
    }


    /// API Key 只进 Keychain，不落 UserDefaults。
    public var aiAPIKey: String {
        get { KeychainStore.string(forKey: "aiAPIKey") ?? "" }
        set { try? KeychainStore.setString(newValue, forKey: "aiAPIKey") }
    }

    public var maxCaptureBytes: Int { maxCaptureMB * 1024 * 1024 }

    public var currentPreset: HotkeyPreset {
        Self.hotkeyPresets.first { $0.id == hotkeyPresetID } ?? Self.hotkeyPresets[0]
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "hotkeyPresetID": "cmdShiftV",
            "retentionMaxItems": 1000,
            "retentionMaxAgeDays": 30,
            "maxCaptureMB": 20,
            "excludedApps": Self.defaultExcludedApps,
            "soundOnCapture": false,
            "hapticFeedbackEnabled": true,
            "launchAtLogin": false,
            "pauseCapture": false,
            "aiEnabled": false,
            "aiEndpoint": "https://api.openai.com/v1",
            "aiModel": "gpt-4o-mini",
            "imageOCREnabled": true,
            "semanticSearchEnabled": true,
            "fetchLinkMetadata": true,
            "panelPositionMode": "center",
            "smartTitleEnabled": true,
            "appLanguage": "system",
            "appTheme": "default",
            "autoCheckUpdates": true,
            "enableInteractiveClips": true,
            "interactiveClipsLocalOnly": true,
            "enablePasteZoom": true,
        ])
        hotkeyPresetID = defaults.string(forKey: "hotkeyPresetID") ?? "cmdShiftV"
        retentionMaxItems = defaults.integer(forKey: "retentionMaxItems")
        retentionMaxAgeDays = defaults.integer(forKey: "retentionMaxAgeDays")
        maxCaptureMB = defaults.integer(forKey: "maxCaptureMB")
        excludedApps = defaults.array(forKey: "excludedApps") as? [String] ?? Self.defaultExcludedApps
        soundOnCapture = defaults.bool(forKey: "soundOnCapture")
        let hapticEnabled = defaults.object(forKey: "hapticFeedbackEnabled") as? Bool ?? true
        hapticFeedbackEnabled = hapticEnabled
        HapticHelper.isEnabled = hapticEnabled
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        pauseCapture = defaults.bool(forKey: "pauseCapture")
        aiEnabled = defaults.bool(forKey: "aiEnabled")
        aiEndpoint = defaults.string(forKey: "aiEndpoint") ?? "https://api.openai.com/v1"
        aiModel = defaults.string(forKey: "aiModel") ?? "gpt-4o-mini"
        imageOCREnabled = defaults.object(forKey: "imageOCREnabled") as? Bool ?? true
        semanticSearchEnabled = defaults.object(forKey: "semanticSearchEnabled") as? Bool ?? true
        fetchLinkMetadata = defaults.object(forKey: "fetchLinkMetadata") as? Bool ?? true
        let modeRaw = defaults.string(forKey: "panelPositionMode") ?? "center"
        panelPositionMode = PanelPositionMode(rawValue: modeRaw) ?? .center
        smartTitleEnabled = defaults.object(forKey: "smartTitleEnabled") as? Bool ?? true
        let langRaw = defaults.string(forKey: "appLanguage") ?? "system"
        let initialLang = AppLanguage(rawValue: langRaw) ?? .system
        appLanguage = initialLang
        L10n.overrideLanguage = initialLang
        let themeRaw = defaults.string(forKey: "appTheme") ?? "default"
        let initialTheme = AppTheme(rawValue: themeRaw) ?? .default
        appTheme = initialTheme
        Palette.currentTheme = initialTheme
        autoCheckUpdates = defaults.object(forKey: "autoCheckUpdates") as? Bool ?? true
        lastUpdateCheckDate = defaults.object(forKey: "lastUpdateCheckDate") as? Date
        if defaults.object(forKey: "lastPanelPositionX") != nil {
            lastPanelPositionX = defaults.double(forKey: "lastPanelPositionX")
        } else {
            lastPanelPositionX = nil
        }
        if defaults.object(forKey: "lastPanelPositionY") != nil {
            lastPanelPositionY = defaults.double(forKey: "lastPanelPositionY")
        } else {
            lastPanelPositionY = nil
        }

        if let scriptData = defaults.data(forKey: "customScripts") {
            customScripts = (try? JSONDecoder().decode([ScriptAction].self, from: scriptData)) ?? []
        } else {
            customScripts = ScriptAction.defaultPresets
        }
        if let promptData = defaults.data(forKey: "customPrompts") {
            customPrompts = (try? JSONDecoder().decode([PromptTemplate].self, from: promptData)) ?? PromptTemplate.defaults
        } else {
            customPrompts = PromptTemplate.defaults
        }

        enableSmartRecommendations = defaults.object(forKey: "enableSmartRecommendations") as? Bool ?? true
        enableInteractiveClips = defaults.object(forKey: "enableInteractiveClips") as? Bool ?? true
        interactiveClipsLocalOnly = defaults.object(forKey: "interactiveClipsLocalOnly") as? Bool ?? true
        enablePasteZoom = defaults.object(forKey: "enablePasteZoom") as? Bool ?? true
        if let recData = defaults.data(forKey: "recommendationStore"),
           let store = try? JSONDecoder().decode(RecommendationLearningStore.self, from: recData) {
            recommendationStore = store
        } else {
            recommendationStore = RecommendationLearningStore()
        }
    }

    private func applyLaunchAtLogin() {
        // 未打包成 .app（swift run 开发模式）时注册会失败，静默忽略。
        if launchAtLogin {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
