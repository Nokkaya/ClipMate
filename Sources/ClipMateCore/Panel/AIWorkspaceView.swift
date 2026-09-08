import SwiftUI
import AppKit

/// AI 工作台：独立窗口视图。
/// 布局分区：头部与源内容卡片 → 快捷动作芯片 → 多轮问答对话流 → 对话提问输入栏 → 结果回写操作。
struct AIWorkspaceView: View {
    @ObservedObject var model: AIWorkspaceModel
    @State private var copiedMessageID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            sourceCard
            actionChips
            chatStream
            if let error = model.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
            }
            promptBar
            Divider().overlay(Color.primary.opacity(0.08))
            footer
        }
        .padding(20)
        .frame(width: 620, height: 720) // 窗口留边，阴影在窗口内绘制
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.purple)
            Text("AI 工作台 · 问剪贴板")
                .font(.system(size: 14, weight: .semibold))

            Text(model.statusText)
                .font(.system(size: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .foregroundStyle(.secondary)

            Spacer()

            if !model.chatHistory.isEmpty {
                Button {
                    model.clearChat()
                } label: {
                    Label("清空会话", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("重置会话并清空历史")
            }

            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭（Esc）")
        }
    }

    // MARK: - 源内容卡片

    @ViewBuilder
    private var sourceCard: some View {
        if let item = model.item {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.kind.tintColor)
                    Text(item.title?.isEmpty == false ? item.title! : (item.sourceName.isEmpty ? item.kind.title : item.sourceName))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                ScrollView {
                    Text(sourceText(item))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 52)
                .modernScrollbar()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.08)))
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

    // MARK: - 快捷操作芯片栏

    private var actionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(AIAction.allCases) { action in
                    Button {
                        model.runAI(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning || model.item == nil)
                }

                ForEach(model.promptTemplates) { template in
                    Button {
                        model.runTemplate(template)
                    } label: {
                        Label(template.name, systemImage: template.icon)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
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
                            .font(.system(size: 11))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning || model.item == nil)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 多轮对话问答流

    private var chatStream: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.chatHistory.isEmpty {
                    emptyChatPlaceholder
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.chatHistory) { msg in
                            chatBubble(msg)
                                .id(msg.id)
                        }
                    }
                    .padding(8)
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
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var emptyChatPlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.accentColor.opacity(0.4))
            Text("基于选中的剪贴板内容提问")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.primary)
            Text("点击上方快捷芯片，或在下方输入框中自由提问。\n支持连续多轮追问、代码审查、格式转换与一键回写。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    @ViewBuilder
    private func chatBubble(_ msg: AIChatMessage) -> some View {
        if msg.role == "user" {
            // 用户提问气泡：靠右
            HStack {
                Spacer(minLength: 40)
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("你")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(msg.content)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentColor.opacity(0.12))
                        )
                }
            }
        } else {
            // AI 助手回答卡片：靠左
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.purple)
                    Text("AI 助手")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.purple)

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
                                    .font(.system(size: 9.5))
                                Text(copiedMessageID == msg.id ? "已复制" : "复制")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if msg.content.isEmpty && model.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("正在思考并组织回答…")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                } else {
                    Text(msg.content)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                        )
                }
            }
        }
    }

    // MARK: - 对话提问输入栏

    private var promptBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("向 AI 提问 / 连续追问（⏎ 发送）…", text: $model.customPrompt)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit {
                    sendQuestion()
                }

            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .padding(.horizontal, 4)
            } else {
                Button {
                    sendQuestion()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(model.customPrompt.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("发送提问（Return）")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func sendQuestion() {
        let text = model.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isRunning else { return }
        model.askQuestion(text)
    }

    // MARK: - 底部结果回写操作

    private var footer: some View {
        HStack(spacing: 8) {
            Text("拖动空白可移动")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Spacer()

            Button("关闭") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.cancelAction)

            Button("复制最新回复") { model.copyResult() }
                .disabled(!model.hasResult)

            Button("存为新条目") { model.replaceAsNewItem() }
                .disabled(!model.hasResult)

            Button("直接粘贴 ⏎") { model.pasteResult() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasResult)
        }
    }
}
