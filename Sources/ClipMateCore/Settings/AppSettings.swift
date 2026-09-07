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

/// 用户自定义脚本动作：剪贴板文本经 stdin 传入命令，stdout 作为结果。
public struct ScriptAction: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var command: String

    public init(id: String = UUID().uuidString, name: String, command: String) {
        self.id = id
        self.name = name
        self.command = command
    }
}

/// 应用设置（UserDefaults 持久化；API Key 走 Keychain）。
public final class AppSettings: ObservableObject {
    public static let hotkeyChangedNotification = Notification.Name("clipmate.hotkeyChanged")

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
            "launchAtLogin": false,
            "pauseCapture": false,
            "aiEnabled": false,
            "aiEndpoint": "https://api.openai.com/v1",
            "aiModel": "gpt-4o-mini",
            "imageOCREnabled": true,
            "semanticSearchEnabled": true,
            "fetchLinkMetadata": true,
        ])
        hotkeyPresetID = defaults.string(forKey: "hotkeyPresetID") ?? "cmdShiftV"
        retentionMaxItems = defaults.integer(forKey: "retentionMaxItems")
        retentionMaxAgeDays = defaults.integer(forKey: "retentionMaxAgeDays")
        maxCaptureMB = defaults.integer(forKey: "maxCaptureMB")
        excludedApps = defaults.array(forKey: "excludedApps") as? [String] ?? Self.defaultExcludedApps
        soundOnCapture = defaults.bool(forKey: "soundOnCapture")
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        pauseCapture = defaults.bool(forKey: "pauseCapture")
        aiEnabled = defaults.bool(forKey: "aiEnabled")
        aiEndpoint = defaults.string(forKey: "aiEndpoint") ?? "https://api.openai.com/v1"
        aiModel = defaults.string(forKey: "aiModel") ?? "gpt-4o-mini"
        imageOCREnabled = defaults.object(forKey: "imageOCREnabled") as? Bool ?? true
        semanticSearchEnabled = defaults.object(forKey: "semanticSearchEnabled") as? Bool ?? true
        fetchLinkMetadata = defaults.object(forKey: "fetchLinkMetadata") as? Bool ?? true
        if let scriptData = defaults.data(forKey: "customScripts") {
            customScripts = (try? JSONDecoder().decode([ScriptAction].self, from: scriptData)) ?? []
        } else {
            customScripts = []
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
