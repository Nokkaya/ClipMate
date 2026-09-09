import SwiftUI

/// 通用浮层容器：采用与主面板统一的毛玻璃质感、半透明卡片、内描边与柔和投影。
private func overlayContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Color.black.opacity(0.32)

        content()
            .padding(14)
            .background(VisualEffectBackground())
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Text(L10n.tr("overlay.edit.title"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.tr("overlay.edit.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.showEditOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                    }
                    .clipMateIconButton(size: 22)
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
                        Text(L10n.tr("meta.chars", viewModel.editText.count))
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
                        Text(L10n.tr("action.cancel"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("⌘⏎")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text(L10n.tr("overlay.edit.save_copy"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(L10n.tr("action.cancel")) {
                        viewModel.showEditOverlay = false
                    }
                    .clipMateGlass(size: .regular)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        viewModel.saveEdit()
                    } label: {
                        Label(L10n.tr("overlay.edit.save_copy"), systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .clipMateAccent(size: .regular)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .frame(maxWidth: 396)
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
                    Text(L10n.tr("overlay.clear.title"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.tr("overlay.clear.subtitle"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                HStack(spacing: 10) {
                    Button(L10n.tr("action.cancel")) {
                        viewModel.showConfirmClear = false
                    }
                    .clipMateGlass(size: .regular)
                    .keyboardShortcut(.cancelAction)
                    .frame(maxWidth: .infinity)

                    Button(role: .destructive) {
                        viewModel.confirmClearAll()
                    } label: {
                        Label(L10n.tr("overlay.clear.confirm"), systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .clipMateDanger(prominent: true, size: .regular)
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
                        .foregroundStyle(Palette.snippet)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.snippet.opacity(0.15)))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.snippetTargetID == nil ? L10n.tr("overlay.snippet.title_new") : L10n.tr("overlay.snippet.title_edit"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.tr("overlay.snippet.subtitle"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        viewModel.showSnippetOverlay = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                    }
                    .clipMateIconButton(size: 22)
                    .keyboardShortcut(.cancelAction)
                }

                // 表单字段
                VStack(alignment: .leading, spacing: 10) {
                    // 标题字段
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L10n.tr("overlay.snippet.title_label"), systemImage: "textformat")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Image(systemName: "quote.opening")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            TextField(L10n.tr("overlay.snippet.title_placeholder"), text: $viewModel.snippetDraftTitle)
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
                            Label(L10n.tr("overlay.snippet.group_label"), systemImage: "folder.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Palette.snippet.opacity(0.85))
                                TextField(L10n.tr("overlay.snippet.group_placeholder"), text: $viewModel.snippetDraftGroup)
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
                            Label(L10n.tr("overlay.snippet.shortcode_label"), systemImage: "bolt.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 6) {
                                Image(systemName: "command")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.orange.opacity(0.8))
                                TextField(L10n.tr("overlay.snippet.shortcode_placeholder"), text: $viewModel.snippetDraftShortcode)
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
                                Text(L10n.tr("snippets.existing_groups"))
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
                                                isCurrent ? Palette.snippet.opacity(0.18) : Color.primary.opacity(0.06)
                                            )
                                        )
                                        .foregroundStyle(isCurrent ? Palette.snippet : Color.primary.opacity(0.8))
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
                            Label(L10n.tr("overlay.snippet.content_label"), systemImage: "doc.text.fill")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L10n.tr("meta.chars", viewModel.snippetDraftContent.count))
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
                        Text(L10n.tr("action.cancel"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text("⌘⏎")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                        Text(L10n.tr("action.save"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(L10n.tr("action.cancel")) {
                        viewModel.showSnippetOverlay = false
                    }
                    .clipMateGlass(size: .regular)
                    .keyboardShortcut(.cancelAction)

                    Button {
                        viewModel.saveSnippet()
                    } label: {
                        Label(L10n.tr("overlay.snippet.save"), systemImage: "checkmark")
                    }
                    .clipMateAccent(size: .regular, tint: Palette.snippet)
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.snippetDraftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: 396)
        }
    }
}

