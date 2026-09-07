import SwiftUI
import AppKit

/// AI 工作台：独立窗口视图。
/// 布局分区：源内容 → 操作 → 结果；源条目信息始终可见，结果区大且可选中。
struct AIWorkspaceView: View {
    @ObservedObject var model: AIWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            sourceCard
            sectionLabel("操作")
            actionArea
            promptField
            sectionLabel("结果")
            outputArea
            if let error = model.errorText {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
            }
            footer
        }
        .padding(30)
        .frame(width: 600, height: 700) // 窗口留边，阴影在窗口内绘制
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundStyle(Color.accentColor)
            Text("AI 工作台")
                .font(.system(size: 15, weight: .semibold))
            Text(model.statusText)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .foregroundStyle(.secondary)
            Spacer()
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

    // MARK: - 源内容卡片（始终可见）

    @ViewBuilder
    private var sourceCard: some View {
        if let item = model.item {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage)
                        .font(.system(size: 11))
                        .foregroundStyle(item.kind.tintColor)
                    Text(item.sourceName.isEmpty ? item.kind.title : item.sourceName)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                ScrollView {
                    Text(sourceText(item))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 76)
                .modernScrollbar()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
        } else {
            Text("未选择条目")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func sourceText(_ item: ClipItem) -> String {
        let content = item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            var text = item.displayText
            if item.kind == .image { text += "（图片条目：若含文字请先确认 OCR 已开启）" }
            return text
        }
        return String(content.prefix(1600))
    }

    // MARK: - 操作

    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(AIAction.allCases) { action in
                    Button {
                        model.runAI(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                            .font(.system(size: 11))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning || model.item == nil)
                }
            }
            scriptRow
        }
    }

    @ViewBuilder
    private var scriptRow: some View {
        // 自定义脚本与 AI 动作共用结果区
        if !scriptList.isEmpty {
            HStack(spacing: 6) {
                Text("脚本")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                ForEach(scriptList) { script in
                    Button {
                        model.runScript(script)
                    } label: {
                        Label(script.name, systemImage: "terminal")
                            .font(.system(size: 11))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isRunning || model.item == nil)
                }
            }
        }
    }

    private var scriptList: [ScriptAction] {
        model.scriptList
    }

    @ViewBuilder
    private var promptField: some View {
        HStack(spacing: 6) {
            TextField("自定义指令（配合“自定义”动作，⏎ 执行）", text: $model.customPrompt)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { model.runAI(.custom) }
            if !model.customPrompt.isEmpty {
                Button("执行") { model.runAI(.custom) }
                    .disabled(model.isRunning || model.item == nil)
            }
        }
    }

    // MARK: - 结果

    private var outputArea: some View {
        ZStack(alignment: .top) {
            ScrollView {
                Text(outputPlaceholder)
                    .font(.system(size: 12.5, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .modernScrollbar()
            if model.isRunning {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var outputPlaceholder: String {
        if model.isRunning && model.output.isEmpty { return "生成中…" }
        if model.hasResult || !model.output.isEmpty { return model.output }
        return "选择上方动作，或输入自定义指令。\n结果可选中复制，也能替换为新条目或直接粘贴。"
    }

    // MARK: - 底部动作

    private var footer: some View {
        HStack(spacing: 8) {
            Text("拖动空白处可移动窗口，位置会记忆")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("关闭") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.cancelAction)
            Button("复制结果") { model.copyResult() }
                .disabled(!model.hasResult)
            Button("存为新条目") { model.replaceAsNewItem() }
                .disabled(!model.hasResult)
            Button("直接粘贴 ⏎") { model.pasteResult() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.hasResult)
        }
    }
}
