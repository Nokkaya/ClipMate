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
                    .modernScrollbar()
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

/// 片段新建与编辑浮层（标题、分组、短码与正文）。
struct SnippetEditOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bookmark.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(viewModel.snippetTargetID == nil ? "新建片段" : "编辑片段")
                        .font(.headline)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("标题（名称）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("如：开票抬头、Git rebase 常用流、邮箱签名", text: $viewModel.snippetDraftTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("分组")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("开发 / 常用 / 邮件…", text: $viewModel.snippetDraftGroup)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("快捷短码（可选）")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField(";tax / ;git…", text: $viewModel.snippetDraftShortcode)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }
                    }

                    if !viewModel.availableSnippetGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                Text("已有分组:")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                ForEach(viewModel.availableSnippetGroups, id: \.self) { g in
                                    Button(g) {
                                        viewModel.snippetDraftGroup = g
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                                    .foregroundStyle(.primary)
                                }
                            }
                        }
                        .modernScrollbar()
                    }

                    Text("片段内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.snippetDraftContent)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .modernScrollbar()
                        .padding(6)
                        .frame(maxWidth: .infinity, minHeight: 110, maxHeight: 160)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                }

                HStack {
                    Button("取消") { viewModel.showSnippetOverlay = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("保存片段") { viewModel.saveSnippet() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(viewModel.snippetDraftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .frame(width: 360)
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
