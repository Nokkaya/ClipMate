import AppKit
import SwiftUI
import Combine

/// 单条 AI 问答对话记录
public struct AIChatMessage: Identifiable, Equatable {
    public let id = UUID()
    public let role: String // "user" or "assistant"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// AI 侧边栏状态模型（主面板内嵌，⌘K / ⌘⇧A 切换）。
public final class AIWorkspaceModel: ObservableObject {
    @Published public var item: ClipItem?
    @Published public var output = ""
    @Published public var chatHistory: [AIChatMessage] = []
    @Published public var isRunning = false
    @Published public var finished = false
    @Published public var errorText: String?
    @Published public var customPrompt = ""

    public let ai: AIService
    public let store: ClipStore
    public let monitor: ClipboardMonitor
    public let settings: AppSettings

    public var pasteTargetProvider: (() -> NSRunningApplication?)?
    public var hidePanel: (() -> Void)?
    private var task: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(ai: AIService, store: ClipStore, monitor: ClipboardMonitor, settings: AppSettings) {
        self.ai = ai
        self.store = store
        self.monitor = monitor
        self.settings = settings

        settings.$appTheme
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    public var scriptList: [ScriptAction] { settings.customScripts }
    public var promptTemplates: [PromptTemplate] { settings.customPrompts }

    public var statusText: String {
        ai.isConfigured ? L10n.tr("ai.status_configured") : L10n.tr("ai.status_unconfigured")
    }

    /// 打开/切换条目：重置结果区与会话，保留自定义指令。
    public func load(item: ClipItem) {
        cancel()
        self.item = item
        output = ""
        chatHistory = []
        finished = false
        errorText = nil
        isRunning = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func beginRun() -> ClipItem? {
        guard let item else { return nil }
        cancel()
        finished = false
        errorText = nil
        isRunning = true
        return item
    }

    private func endRun(success: Bool) {
        if isRunning {
            isRunning = false
            finished = success
        }
    }

    /// 执行自定义提示词模板
    public func runTemplate(_ template: PromptTemplate) {
        guard let item = beginRun() else { return }
        guard ai.isConfigured else {
            isRunning = false
            errorText = AIError.notConfigured.localizedDescription
            return
        }
        let prompt = template.prompt(for: item.plainText)
        chatHistory.append(AIChatMessage(role: "user", content: template.name))
        chatHistory.append(AIChatMessage(role: "assistant", content: ""))
        let assistantIndex = chatHistory.count - 1

        output = ""
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.ai.stream(prompt: prompt) {
                    self.output += delta
                    if assistantIndex < self.chatHistory.count {
                        self.chatHistory[assistantIndex].content += delta
                    }
                }
                self.endRun(success: true)
                HapticHelper.feedback()
            } catch {
                self.isRunning = false
                self.errorText = "请求失败：\(error.localizedDescription)"
            }
        }
    }

    /// “问剪贴板”：多轮连续对话追问
    public func askQuestion(_ question: String) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let item = beginRun() else { return }
        guard ai.isConfigured else {
            isRunning = false
            errorText = AIError.notConfigured.localizedDescription
            return
        }

        // 构造消息列表：System + 原文上下文 + 历史轮次 + 当前问题
        var messages: [[String: String]] = [
            ["role": "system", "content": "你是 macOS 剪贴板 AI 助手。请基于剪贴板内容提供专业、简明、准确的回答，支持格式清晰的 Markdown 与代码块。"]
        ]
        messages.append([
            "role": "user",
            "content": "剪贴板原文上下文如下：\n```\n\(String(item.plainText.prefix(6000)))\n```"
        ])
        for msg in chatHistory where !msg.content.isEmpty {
            messages.append(["role": msg.role, "content": msg.content])
        }
        messages.append(["role": "user", "content": trimmed])

        chatHistory.append(AIChatMessage(role: "user", content: trimmed))
        chatHistory.append(AIChatMessage(role: "assistant", content: ""))
        let assistantIndex = chatHistory.count - 1

        output = ""
        customPrompt = ""
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await delta in self.ai.stream(messages: messages) {
                    self.output += delta
                    if assistantIndex < self.chatHistory.count {
                        self.chatHistory[assistantIndex].content += delta
                    }
                }
                self.endRun(success: true)
                HapticHelper.feedback()
            } catch {
                self.isRunning = false
                self.errorText = "请求失败：\(error.localizedDescription)"
            }
        }
    }

    public func clearChat() {
        cancel()
        chatHistory = []
        output = ""
        errorText = nil
        finished = false
        HapticHelper.alignment()
    }

    public func copyMessage(_ content: String) {
        guard !content.isEmpty else { return }
        PasteBack.write(.text(content))
        monitor.suppress(seconds: 1.5)
        HapticHelper.feedback()
    }

    public func runScript(_ script: ScriptAction) {

        guard let item = beginRun() else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let output = try await ScriptRunner.run(script, input: item.plainText)
                if self.isRunning {
                    self.output = output
                    self.isRunning = false
                    self.finished = true
                    self.chatHistory.append(AIChatMessage(role: "user", content: "脚本：\(script.name)"))
                    self.chatHistory.append(AIChatMessage(role: "assistant", content: output))
                    HapticHelper.feedback()
                }
            } catch {
                self.isRunning = false
                self.errorText = "脚本失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 结果处置

    public var hasResult: Bool { (finished || !chatHistory.isEmpty) && !output.isEmpty }

    public func copyResult() {
        guard hasResult else { return }
        PasteBack.write(.text(output))
        monitor.suppress(seconds: 1.5)
        HapticHelper.feedback()
    }

    /// 结果作为新条目入库（原内容保留在历史中）。
    public func replaceAsNewItem() {
        guard hasResult else { return }
        _ = try? store.capture(
            kind: .text,
            plainText: output,
            sourceBundle: Bundle.main.bundleIdentifier ?? "",
            sourceName: "ClipMate",
            tags: ["AI"]
        )
        HapticHelper.generic()
    }

    /// 直接粘贴到唤起面板前的目标应用，随后关闭工作台与主面板。
    public func pasteResult() {
        guard hasResult else { return }
        let target = pasteTargetProvider?()
        let content = PasteboardContent.text(output)
        hidePanel?()
        PasteBack.paste(content: content, toPID: target?.processIdentifier) { [weak self] seconds in
            self?.monitor.suppress(seconds: seconds)
        }
        if target == nil || !PasteBack.isAccessibilityGranted() {
            NSSound(named: "Basso")?.play()
        }
        HapticHelper.feedback()
    }
}
