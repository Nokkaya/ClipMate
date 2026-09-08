import SwiftUI
import AppKit

/// AI 问答侧边栏视图：嵌于主面板右侧，支持实时联动选中条目、预置功能与多轮追问。
public struct AISidebarView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var model: AIWorkspaceModel
    @State private var copiedMessageID: UUID?

    public init(viewModel: PanelViewModel, model: AIWorkspaceModel) {
        self.viewModel = viewModel
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            sourceCard
            actionChips
            chatStream
            if let error = model.errorText {
                errorBanner(error)
            }
            promptBar
            Divider().overlay(Color.primary.opacity(0.08))
            footer
        }
        .padding(14)
        .background(Color.primary.opacity(0.015))
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.purple, Color.indigo, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("AI 问答")
                .font(.system(size: 13, weight: .semibold))

            Text(model.statusText)
                .font(.system(size: 9.5))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .foregroundStyle(.secondary)

            Spacer()

            if !model.chatHistory.isEmpty {
                Button {
                    model.clearChat()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("重置会话并清空历史")
            }

            Button {
                viewModel.toggleAISidebar()
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("收起 AI 侧边栏 (⌘K / ⌘⇧A)")
        }
    }

    // MARK: - 选中条目源卡片

    @ViewBuilder
    private var sourceCard: some View {
        if let item = model.item {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 10))
                        .foregroundStyle(item.kind.tintColor)
                    Text(item.title?.isEmpty == false ? item.title! : (item.sourceName.isEmpty ? item.kind.title : item.sourceName))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(sourceText(item).count) 字")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                ScrollView {
                    Text(sourceText(item))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 46)
                .modernScrollbar()
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.07)))
        } else {
            HStack {
                Image(systemName: "hand.point.left")
                    .font(.system(size: 11))
                Text("在左侧列表选择条目以分析与问答")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.tertiary)
            .padding(6)
        }
    }

    private func sourceText(_ item: ClipItem) -> String {
        let content = item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            var text = item.displayText
            if item.kind == .image { text += "（图片条目：可提问图中的识别文字）" }
            return text
        }
        return String(content.prefix(1600))
    }

    // MARK: - 快捷功能芯片栏

    private var actionChips: some View {
        FlowLayout(spacing: 5, rowSpacing: 5) {
            ForEach(allTemplates) { template in
                Button {
                    model.runTemplate(template)
                } label: {
                    Label(template.name, systemImage: template.icon)
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning || model.item == nil)
            }

            ForEach(model.scriptList) { script in
                Button {
                    model.runScript(script)
                } label: {
                    Label(script.name, systemImage: "terminal")
                        .font(.system(size: 10.5, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .disabled(model.isRunning || model.item == nil)
            }
        }
        .padding(.vertical, 1)
    }

    private var allTemplates: [PromptTemplate] {
        var list = model.promptTemplates
        if list.isEmpty {
            list = PromptTemplate.defaults
        }
        let existingIDs = Set(list.map { $0.id })
        let existingNames = Set(list.map { $0.name })
        for def in PromptTemplate.defaults {
            if !existingIDs.contains(def.id) && !existingNames.contains(def.name) {
                list.append(def)
            }
        }
        return list
    }

    // MARK: - 多轮对话问答流

    private var chatStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.chatHistory.isEmpty {
                    emptyChatPlaceholder
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.chatHistory) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(4)
                }
            }
            .modernScrollbar()
            .onChange(of: model.chatHistory.count) { _ in
                if let lastID = model.chatHistory.last?.id {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: model.output) { _ in
                if let lastID = model.chatHistory.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var emptyChatPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("向 AI 提问 / 连续追问")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("点击上方快捷模板，或在下方输入框自由提问。\n支持多轮连续追问与代码/文本分析。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func chatBubble(_ msg: AIChatMessage) -> some View {
        if msg.role == "user" {
            HStack {
                Spacer(minLength: 28)
                Text(msg.content)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.85)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
            }
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.purple)
                    Text("AI 回复")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !msg.content.isEmpty {
                        Button {
                            model.copyMessage(msg.content)
                            copiedMessageID = msg.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedMessageID == msg.id { copiedMessageID = nil }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: copiedMessageID == msg.id ? "checkmark" : "doc.on.doc")
                                Text(copiedMessageID == msg.id ? "已复制" : "复制")
                            }
                            .font(.system(size: 9.5))
                            .foregroundStyle(copiedMessageID == msg.id ? Color.green : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if msg.content.isEmpty && model.isRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text("正在思考分析中…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    Text(msg.content)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func errorBanner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 10.5))
            .foregroundStyle(.red)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.08)))
    }

    // MARK: - 提问输入栏

    private var promptBar: some View {
        HStack(spacing: 6) {
            TextField(model.chatHistory.isEmpty ? "向 AI 自由提问当前剪贴板（⏎ 发送）…" : "连续追问…", text: $model.customPrompt)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11.5))
                .onSubmit {
                    submitQuestion()
                }

            Button {
                submitQuestion()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.5) : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning || model.item == nil || model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func submitQuestion() {
        guard !model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.askQuestion(model.customPrompt)
    }

    // MARK: - 底部结果操作

    private var footer: some View {
        HStack(spacing: 6) {
            Spacer()
            if model.hasResult {
                Button("复制最新") { model.copyResult() }
                    .font(.system(size: 10.5))
                    .buttonStyle(.bordered)
                Button("存为新条目") { model.replaceAsNewItem() }
                    .font(.system(size: 10.5))
                    .buttonStyle(.bordered)
                Button("直接粘贴 ⏎") { model.pasteResult() }
                    .font(.system(size: 10.5))
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
