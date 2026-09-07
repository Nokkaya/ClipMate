import SwiftUI

/// 通用浮层容器：采用与主面板统一的毛玻璃质感、半透明卡片、内描边与柔和投影。
private func overlayContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.32)

        content()
            .padding(16)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
            .padding(14)
    }
}

/// 编辑浮层：修改条目文本后保存并复制。
struct EditOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(alignment: .leading, spacing: 12) {
                // 头部
                HStack(spacing: 8) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.accentColor.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("编辑内容")
                            .font(.system(size: 14, weight: .semibold))
                        Text("修改后将更新历史记录并复制到剪贴板")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.showEditOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                // 文本输入区
                VStack(alignment: .leading, spacing: 4) {
                    TextEditor(text: $viewModel.editText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .modernScrollbar()
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 240)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    HStack {
                        Spacer()
                        Text("\(viewModel.editText.count) 字符")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                // 底部操作
                HStack {
                    HStack(spacing: 4) {
                        Text("Esc")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text("取消")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("⌘⏎")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text("保存并复制")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("取消") {
                        viewModel.showEditOverlay = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button {
                        viewModel.saveEdit()
                    } label: {
                        Label("保存并复制", systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(width: 440)
        }
    }
}

/// 清空确认浮层（替代模态弹窗，保持面板内交互）。
struct ConfirmClearOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "trash.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red)
                }

                VStack(spacing: 4) {
                    Text("清空全部历史？")
                        .font(.system(size: 15, weight: .semibold))
                    Text("已固定（Pinned）的条目会完整保留，未固定的全部历史将无法恢复。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 10) {
                    Button("取消") {
                        viewModel.showConfirmClear = false
                    }
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)

                    Button(role: .destructive) {
                        viewModel.confirmClearAll()
                    } label: {
                        Label("确认清空", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .frame(width: 280)
        }
    }
}

/// 片段新建与编辑浮层（标题、分组、短码与正文）。
struct SnippetEditOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        overlayContainer {
            VStack(alignment: .leading, spacing: 12) {
                // 顶部标题栏
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.purple)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.purple.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.snippetTargetID == nil ? "新建常用片段" : "编辑片段")
                            .font(.system(size: 14, weight: .semibold))
                        Text("保存高频文本模板，支持快捷短码快速检索")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.showSnippetOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                // 表单字段
                VStack(alignment: .leading, spacing: 10) {
                    // 标题字段
                    VStack(alignment: .leading, spacing: 4) {
                        Label("片段标题（可选）", systemImage: "textformat")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            TextField("如：开票抬头、Git rebase 常用流、邮箱签名…", text: $viewModel.snippetDraftTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                        )
                    }

                    // 分组与快捷短码双列
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("分组", systemImage: "folder.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.purple.opacity(0.8))
                                TextField("开发 / 常用 / 邮件…", text: $viewModel.snippetDraftGroup)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Label("快捷短码（可选）", systemImage: "bolt.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "command")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.orange.opacity(0.8))
                                TextField(";tax / ;git / ;sig…", text: $viewModel.snippetDraftShortcode)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                        }
                    }

                    // 已有分组快速选取胶囊
                    if !viewModel.availableSnippetGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                Text("已有分组:")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)

                                ForEach(viewModel.availableSnippetGroups, id: \.self) { g in
                                    let isCurrent = viewModel.snippetDraftGroup == g
                                    Button {
                                        viewModel.snippetDraftGroup = g
                                        HapticHelper.alignment()
                                    } label: {
                                        HStack(spacing: 3) {
                                            if isCurrent {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 8, weight: .bold))
                                            }
                                            Text(g)
                                        }
                                        .font(.system(size: 10, weight: isCurrent ? .semibold : .regular))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2.5)
                                        .background(
                                            Capsule().fill(
                                                isCurrent ? Color.purple.opacity(0.2) : Color.primary.opacity(0.06)
                                            )
                                        )
                                        .foregroundStyle(isCurrent ? Color.purple : Color.primary.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 1)
                        }
                        .modernScrollbar()
                    }

                    // 片段内容输入框
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("片段正文", systemImage: "doc.text.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(viewModel.snippetDraftContent.count) 字符")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }

                        TextEditor(text: $viewModel.snippetDraftContent)
                            .font(.system(size: 12, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .modernScrollbar()
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 115, maxHeight: 165)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.04)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                            )
                    }
                }

                // 底部操作条
                HStack {
                    HStack(spacing: 4) {
                        Text("Esc")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text("取消")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("⌘⏎")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text("保存")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("取消") {
                        viewModel.showSnippetOverlay = false
                    }
                    .keyboardShortcut(.cancelAction)

                    Button {
                        viewModel.saveSnippet()
                    } label: {
                        Label("保存片段", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.purple)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.snippetDraftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 2)
            }
            .frame(width: 410)
        }
    }
}

