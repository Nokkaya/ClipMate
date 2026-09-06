import SwiftUI

/// 编辑浮层：修改条目文本后保存并复制。
struct EditOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("编辑内容")
                    .font(.headline)
                TextEditor(text: $viewModel.editText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 170)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
                HStack {
                    Button("取消") { viewModel.showEditOverlay = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("保存并复制") { viewModel.saveEdit() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

/// 清空确认浮层（替代模态弹窗，保持面板内交互）。
struct ConfirmClearOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 26))
                    .foregroundStyle(.red)
                Text("清空全部历史？")
                    .font(.headline)
                Text("已固定的条目会保留")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("取消") { viewModel.showConfirmClear = false }
                        .keyboardShortcut(.cancelAction)
                    Button("清空", role: .destructive) { viewModel.confirmClearAll() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 240)
        }
    }
}

private func overlayContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.28)
        content()
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
            .shadow(color: .black.opacity(0.3), radius: 14)
            .padding(24)
    }
}
