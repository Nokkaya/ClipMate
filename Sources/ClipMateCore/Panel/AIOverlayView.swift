import SwiftUI

/// ⌘K AI 快速操作浮层：动作网格 + 流式结果预览 + 结果处置。
struct AIOverlayView: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        if let state = viewModel.aiState {
            ZStack {
                Color.black.opacity(0.3)
                VStack(alignment: .leading, spacing: 10) {
                    header(state)
                    actionGrid(state)
                    TextField("自定义指令（配合“自定义”动作使用）", text: $viewModel.aiCustomPrompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    outputArea(state)
                    if let error = state.errorText {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    footer(state)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(color: .black.opacity(0.3), radius: 14)
                .padding(24)
            }
        }
    }

    private func header(_ state: AIOverlayState) -> some View {
        HStack {
            Label("AI 快速操作", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
            Spacer()
            Text(viewModel.ai.isConfigured ? "OpenAI 兼容端点" : "未配置")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func actionGrid(_ state: AIOverlayState) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(AIAction.allCases) { action in
                Button {
                    viewModel.runAI(action)
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.isRunning)
            }
        }
    }

    private func outputArea(_ state: AIOverlayState) -> some View {
        ScrollView {
            Text(displayText(state))
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
    }

    private func displayText(_ state: AIOverlayState) -> String {
        if state.isRunning && state.output.isEmpty { return "生成中…" }
        if state.errorText != nil && state.output.isEmpty { return "" }
        return state.output
    }

    private func footer(_ state: AIOverlayState) -> some View {
        HStack {
            if state.isRunning {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button("关闭") { viewModel.closeAI() }
                .keyboardShortcut(.cancelAction)
            Button("复制结果") { viewModel.copyAIResult() }
                .disabled(!state.finished || state.output.isEmpty)
            Button("替换为新条目") { viewModel.replaceWithAIResult() }
                .disabled(!state.finished || state.output.isEmpty)
            Button("直接粘贴") { viewModel.pasteAIResult() }
                .keyboardShortcut(.defaultAction)
                .disabled(!state.finished || state.output.isEmpty)
        }
    }
}
