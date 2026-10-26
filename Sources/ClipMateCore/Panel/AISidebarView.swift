import SwiftUI
import AppKit

/// AI 问答侧边栏视图：嵌于主面板右侧，支持实时联动选中条目、预置功能与多轮追问。
public struct AISidebarView: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var model: AIWorkspaceModel
    @State private var copiedMessageID: UUID?
    @FocusState private var isInputFocused: Bool

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
            Divider().overlay(Color.primary.opacity(0.05))
            footer
        }
        .padding(14)
        .background(Color.primary.opacity(0.015))
        .onDisappear {
            viewModel.isAIPromptFocused = false
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text(L10n.tr("ai.sidebar_title"))
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
                }
                .clipMateIconButton(size: 22)
                .help(L10n.tr("ai.tip_clear_chat"))
            }

            Button {
                viewModel.toggleAISidebar()
            } label: {
                Image(systemName: "sidebar.right")
            }
            .clipMateIconButton(size: 22)
            .help(L10n.tr("ai.tip_collapse_sidebar"))
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
                    Text((item.title?.isEmpty == false ? item.title : nil) ?? (item.sourceName.isEmpty ? item.kind.title : item.sourceName))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(L10n.tr("meta.chars_unit", sourceText(item).count))
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
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.8))
        } else {
            HStack {
                Image(systemName: "hand.point.left")
                    .font(.system(size: 11))
                Text(L10n.tr("ai.select_item_hint"))
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
            if item.kind == .image { text += " " + L10n.tr("ai.image_ocr_hint") }
            return text
        }
        return String(content.prefix(1600))
    }

    // MARK: - 快捷功能芯片栏

    private var actionChips: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3),
            spacing: 5
        ) {
            ForEach(allTemplates) { template in
                chipButton {
                    model.runTemplate(template)
                } content: {
                    Label(L10n.templateName(template.id, defaultName: template.name), systemImage: template.icon)
                }
            }

            ForEach(model.scriptList) { script in
                chipButton {
                    model.runScript(script)
                } content: {
                    Label(L10n.scriptName(script), systemImage: script.type == .shortcut ? "bolt.horizontal.fill" : script.icon)
                }
            }
        }
        .padding(.vertical, 1)
    }

    /// 等宽芯片按钮：统一宽度与左对齐，避免长短不一导致换行错落。
    private func chipButton<Content: View>(
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipMateAIChip()
        .disabled(model.isRunning || model.item == nil)
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
            Text(L10n.tr("ai.empty_chat_title"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(L10n.tr("ai.empty_chat_subtitle"))
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
                        .foregroundStyle(Color.accentColor)
                    Text(L10n.tr("ai.response_title"))
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
                                Text(copiedMessageID == msg.id ? L10n.tr("action.copied") : L10n.tr("action.copy"))
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
                        Text(L10n.tr("ai.thinking"))
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
        HStack(spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isInputFocused ? Color.accentColor : Color.secondary.opacity(0.6))
                .padding(.leading, 3)

            TextField(
                model.chatHistory.isEmpty ? L10n.tr("ai.prompt_placeholder_new") : L10n.tr("ai.prompt_placeholder_followup"),
                text: $model.customPrompt
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isInputFocused)
            .onChange(of: isInputFocused) { focused in
                viewModel.isAIPromptFocused = focused
            }
            .onSubmit {
                submitQuestion()
            }

            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .frame(width: 22, height: 22)
            } else {
                let hasText = !model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty
                Button {
                    submitQuestion()
                } label: {
                    ZStack {
                        Circle()
                            .fill(hasText ? Color.accentColor : Color.primary.opacity(0.06))
                            .frame(width: 22, height: 22)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(hasText ? Color.white : Color.secondary.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isRunning || model.item == nil || !hasText)
                .help(L10n.tr("ai.tip_send"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isInputFocused ? 0.05 : 0.03))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isInputFocused ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.09),
                    lineWidth: 0.8
                )
        }
        .shadow(
            color: isInputFocused ? Color.accentColor.opacity(0.12) : .clear,
            radius: 4,
            y: 1
        )
        .animation(.easeInOut(duration: 0.16), value: isInputFocused)
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
                Button(L10n.tr("ai.copy_latest")) { model.copyResult() }
                    .clipMateGlass(size: .small)
                Button(L10n.tr("ai.save_as_new")) { model.replaceAsNewItem() }
                    .clipMateGlass(size: .small)
                Button(L10n.tr("ai.direct_paste")) { model.pasteResult() }
                    .clipMateAccent(size: .small)
            }
        }
    }
}
