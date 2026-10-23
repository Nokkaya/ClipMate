import SwiftUI
import AppKit

extension ClipKind {
    var systemImage: String {
        switch self {
        case .text: return "doc.on.doc"
        case .url: return "link"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .file: return "folder"
        case .pdf: return "doc.text"
        }
    }

    var tintColor: Color {
        switch self {
        case .text: return Palette.text
        case .url: return Palette.url
        case .richText: return Palette.richText
        case .image: return Palette.image
        case .file: return Palette.file
        case .pdf: return Palette.pdf
        }
    }
}

/// 历史列表行：类型图标/缩略图 + 内容预览 + 来源应用 + 时间 + 标签。
/// 悬停高亮用行内 @State：只有该行重算，避免鼠标划过时整列表刷新。
public struct ClipRowView: View, Equatable {
    public let item: ClipItem
    public let selected: Bool
    public var multiSelected: Bool = false
    public let thumbnail: NSImage?
    public var searchHighlight: String = ""
    public var language: AppLanguage = .system
    public var theme: AppTheme = .default
    public var fields: [ExtractedField] = []
    public var selectedFieldIndex: Int? = nil
    public var isExpanded: Bool = false
    public var onToggleExpand: (() -> Void)? = nil
    public var onPasteField: ((ExtractedField) -> Void)? = nil
    public var onCopyField: ((ExtractedField) -> Void)? = nil
    public var onCopyOCR: (() -> Void)? = nil

    public var recommendedAction: RecommendedAction? = nil
    public var activeActionResult: InlineActionResult? = nil
    public var onExecuteAction: ((ContentActionKind) -> Void)? = nil
    public var onCancelAction: (() -> Void)? = nil
    public var onRetryAction: (() -> Void)? = nil
    public var onToggleOriginal: (() -> Void)? = nil
    public var onDismissAction: (() -> Void)? = nil
    public var onPasteActionResult: (() -> Void)? = nil
    public var onCopyActionResult: (() -> Void)? = nil
    public var onChangeTargetLanguage: ((String) -> Void)? = nil
    public var onMuteAction: ((ContentActionKind) -> Void)? = nil

    public var interactiveSessionBinding: Binding<InteractiveSession>? = nil
    public var onPasteInteractive: (() -> Void)? = nil
    public var onCopyInteractive: (() -> Void)? = nil
    public var onResetInteractive: (() -> Void)? = nil
    public var onToggleInteractiveLock: ((String) -> Void)? = nil
    public var onResolveInteractiveMissing: ((Double) -> Void)? = nil

    @State private var hovered = false

    public init(item: ClipItem, selected: Bool, multiSelected: Bool = false,
                thumbnail: NSImage? = nil, searchHighlight: String = "",
                language: AppLanguage = .system,
                theme: AppTheme = .default,
                fields: [ExtractedField] = [],
                selectedFieldIndex: Int? = nil,
                isExpanded: Bool = false,
                onToggleExpand: (() -> Void)? = nil,
                onPasteField: ((ExtractedField) -> Void)? = nil,
                onCopyField: ((ExtractedField) -> Void)? = nil,
                onCopyOCR: (() -> Void)? = nil,
                recommendedAction: RecommendedAction? = nil,
                activeActionResult: InlineActionResult? = nil,
                onExecuteAction: ((ContentActionKind) -> Void)? = nil,
                onCancelAction: (() -> Void)? = nil,
                onRetryAction: (() -> Void)? = nil,
                onToggleOriginal: (() -> Void)? = nil,
                onDismissAction: (() -> Void)? = nil,
                onPasteActionResult: (() -> Void)? = nil,
                onCopyActionResult: (() -> Void)? = nil,
                onChangeTargetLanguage: ((String) -> Void)? = nil,
                onMuteAction: ((ContentActionKind) -> Void)? = nil,
                interactiveSessionBinding: Binding<InteractiveSession>? = nil,
                onPasteInteractive: (() -> Void)? = nil,
                onCopyInteractive: (() -> Void)? = nil,
                onResetInteractive: (() -> Void)? = nil,
                onToggleInteractiveLock: ((String) -> Void)? = nil,
                onResolveInteractiveMissing: ((Double) -> Void)? = nil) {
        self.item = item
        self.selected = selected
        self.multiSelected = multiSelected
        self.thumbnail = thumbnail
        self.searchHighlight = searchHighlight
        self.language = language
        self.theme = theme
        self.fields = fields
        self.selectedFieldIndex = selectedFieldIndex
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onPasteField = onPasteField
        self.onCopyField = onCopyField
        self.onCopyOCR = onCopyOCR
        self.recommendedAction = recommendedAction
        self.activeActionResult = activeActionResult
        self.onExecuteAction = onExecuteAction
        self.onCancelAction = onCancelAction
        self.onRetryAction = onRetryAction
        self.onToggleOriginal = onToggleOriginal
        self.onDismissAction = onDismissAction
        self.onPasteActionResult = onPasteActionResult
        self.onCopyActionResult = onCopyActionResult
        self.onChangeTargetLanguage = onChangeTargetLanguage
        self.onMuteAction = onMuteAction
        self.interactiveSessionBinding = interactiveSessionBinding
        self.onPasteInteractive = onPasteInteractive
        self.onCopyInteractive = onCopyInteractive
        self.onResetInteractive = onResetInteractive
        self.onToggleInteractiveLock = onToggleInteractiveLock
        self.onResolveInteractiveMissing = onResolveInteractiveMissing
    }

    public static func == (lhs: ClipRowView, rhs: ClipRowView) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.selected == rhs.selected &&
        lhs.multiSelected == rhs.multiSelected &&
        lhs.searchHighlight == rhs.searchHighlight &&
        lhs.language == rhs.language &&
        lhs.theme == rhs.theme &&
        lhs.item.pinned == rhs.item.pinned &&
        lhs.item.useCount == rhs.item.useCount &&
        lhs.item.tags == rhs.item.tags &&
        lhs.item.title == rhs.item.title &&
        lhs.item.meta == rhs.item.meta &&
        lhs.item.displayText == rhs.item.displayText &&
        lhs.thumbnail === rhs.thumbnail &&
        lhs.fields == rhs.fields &&
        lhs.selectedFieldIndex == rhs.selectedFieldIndex &&
        lhs.isExpanded == rhs.isExpanded &&
        lhs.recommendedAction == rhs.recommendedAction &&
        lhs.activeActionResult == rhs.activeActionResult &&
        (lhs.interactiveSessionBinding?.wrappedValue == rhs.interactiveSessionBinding?.wrappedValue)
    }

    public var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                if let title = item.title, !title.isEmpty {
                    if !searchHighlight.isEmpty {
                        Text(TextHighlighter.highlight(text: title, query: searchHighlight))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    } else {
                        Text(title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    let subtitleText: String = {
                        if item.kind == .url { return item.plainText }
                        if item.kind == .image { return item.meta["display"] ?? item.plainText }
                        return item.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    }()
                    if !subtitleText.isEmpty && subtitleText != title {
                        if let numberText = NumberRecognizer.displayText(subtitleText) {
                            // 号码按人类习惯分组 + 等宽，扫视识别更快
                            Text(numberText)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        } else if !searchHighlight.isEmpty {
                            Text(TextHighlighter.highlight(text: subtitleText, query: searchHighlight))
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(subtitleText)
                                .font(.system(size: 10.5))
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let numberText = NumberRecognizer.displayText(item.displayText) {
                    // 号码类内容：分组展示（138 1234 5678）并放大字号
                    Text(numberText)
                        .font(.system(size: 13.5, weight: .medium, design: .monospaced))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else {
                    let textToDisplay = (interactiveSessionBinding?.wrappedValue.isModified == true)
                        ? (interactiveSessionBinding?.wrappedValue.effectiveText ?? item.displayText)
                        : item.displayText
                    if !searchHighlight.isEmpty {
                        Text(TextHighlighter.highlight(text: textToDisplay, query: searchHighlight))
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundStyle(item.kind == .image ? .secondary : .primary)
                    } else {
                        Text(textToDisplay)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundStyle(item.kind == .image ? .secondary : .primary)
                    }
                }


                HStack(spacing: 5) {
                    let metaText: String = {
                        let timeStr = L10n.relativeTime(item.createdAt, lang: language)
                        return item.sourceName.isEmpty ? timeStr : "\(item.sourceName) • \(timeStr)"
                    }()
                    Text(metaText)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    if let group = item.snippetGroup, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.snippet.opacity(0.12)))
                            .foregroundStyle(Palette.snippet)
                    }
                    if let shortcode = item.snippetShortcode, !shortcode.isEmpty {
                        Text(shortcode)
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                            .foregroundStyle(Color.orange)
                    }
                    ForEach(item.tags.filter { $0 != FilterKind.snippetTag && $0 != item.snippetGroup }.prefix(2), id: \.self) { tag in
                        Text(L10n.tagTitle(tag, lang: language))
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(item.kind.tintColor.opacity(0.10)))
                            .foregroundStyle(item.kind.tintColor)
                    }
                }

                if selected && !fields.isEmpty {
                    fieldSection
                }

                if selected {
                    if let sessionBinding = interactiveSessionBinding {
                        InteractiveControlCard(
                            session: sessionBinding,
                            theme: theme,
                            language: language,
                            onPaste: { onPasteInteractive?() },
                            onCopy: { onCopyInteractive?() },
                            onReset: { onResetInteractive?() },
                            onToggleLock: { onToggleInteractiveLock?($0) },
                            onResolveMissing: { onResolveInteractiveMissing?($0) }
                        )
                    } else if let result = activeActionResult, result.itemID == item.id {
                        InlineActionResultCard(
                            result: result,
                            theme: theme,
                            language: language,
                            onPaste: { onPasteActionResult?() },
                            onCopy: { onCopyActionResult?() },
                            onToggleOriginal: { onToggleOriginal?() },
                            onDismiss: { onDismissAction?() },
                            onCancel: { onCancelAction?() },
                            onRetry: { onRetryAction?() },
                            onChangeLanguage: { onChangeTargetLanguage?($0) }
                        )
                    } else if let rec = recommendedAction {
                        recommendedActionSection(rec)
                    }
                }
            }
            Spacer(minLength: 4)
            if selected && item.kind == .image && !item.plainText.isEmpty {
                Button {
                    onCopyOCR?()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "text.viewfinder")
                            .font(.system(size: 8.5))
                        Text(L10n.tr("action.copy_ocr", lang: language))
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent.opacity(0.14)))
                    .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("action.copy_ocr", lang: language))
            }
            if multiSelected && !selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.pinColor)
            }
            Text("×\(item.useCount)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .opacity(item.useCount > 1 ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(theme.accent)
                    .frame(width: 3, height: 18)
                    .padding(.leading, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var rowBackground: Color {
        if selected { return theme.selectionBackground }
        if multiSelected { return theme.selectionBackground.opacity(0.5) }
        if hovered { return theme.hoverBackground }
        return .clear
    }

    @ViewBuilder
    private var leading: some View {
        if let hex = item.meta["color"], let swatch = Palette.color(hexString: hex) {
            // 色值条目：直接展示色卡
            Circle()
                .fill(swatch)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.16), lineWidth: 0.8))
                .shadow(color: swatch.opacity(0.35), radius: 2.5, y: 1)
                .frame(width: 24)

        } else if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
        } else if item.kind == .url, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 24)
        } else if item.isSnippet {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 14))
                .foregroundStyle(Palette.snippet)
                .frame(width: 24)
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(item.kind.tintColor)
                .frame(width: 24)
        }
    }

    @ViewBuilder
    private var fieldSection: some View {
        let displayFields = isExpanded ? fields : Array(fields.prefix(3))
        FlowLayout(spacing: 4, rowSpacing: 4) {
            ForEach(Array(displayFields.enumerated()), id: \.element.id) { index, field in
                FieldPillView(
                    field: field,
                    index: index,
                    isFocused: selectedFieldIndex == index,
                    theme: theme,
                    language: language,
                    onPaste: { onPasteField?(field) },
                    onCopy: { onCopyField?(field) }
                )
            }
            if fields.count > 3 {
                Button {
                    onToggleExpand?()
                } label: {
                    Text(isExpanded ? L10n.tr("action.collapse_fields", lang: language) : String(format: L10n.tr("action.more_fields", lang: language), fields.count - 3))
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func recommendedActionSection(_ rec: RecommendedAction) -> some View {
        HStack(spacing: 3) {
            Button {
                onExecuteAction?(rec.kind)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 8.5))
                    Text(rec.title)
                        .font(.system(size: 9.5, weight: .semibold))
                    if let badge = rec.badge {
                        Text(badge)
                            .font(.system(size: 8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.accent.opacity(0.14)))
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(theme.accent.opacity(0.10))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(theme.accent.opacity(0.24), lineWidth: 0.8)
                )
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)

            if let onMuteAction {
                Menu {
                    Button(role: .destructive) {
                        onMuteAction(rec.kind)
                    } label: {
                        Label(L10n.tr("action.mute_action", lang: language), systemImage: "bell.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(L10n.tr("action.mute_action", lang: language))
            }
        }
        .padding(.top, 2)
    }
}

/// 局部字段胶囊视图
struct FieldPillView: View {
    let field: ExtractedField
    let index: Int
    let isFocused: Bool
    let theme: AppTheme
    let language: AppLanguage
    let onPaste: () -> Void
    let onCopy: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: onPaste) {
                HStack(spacing: 3) {
                    Image(systemName: field.kind.systemImage)
                        .font(.system(size: 8))
                        .foregroundStyle(isFocused ? theme.accent : Color.secondary)

                    Text("\(field.label):")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.secondary)

                    Text(field.value)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Color.primary)
                }
            }
            .buttonStyle(.plain)

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 7.5))
                    .foregroundStyle(hovered ? theme.accent : Color.secondary.opacity(0.6))
                    .padding(.horizontal, 1)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("action.copy_only", lang: language))

            if index < 3 {
                Text("⌥\(index + 1)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isFocused ? theme.accent : Color.secondary.opacity(0.45))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 5)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isFocused ? theme.accent.opacity(0.18) : (hovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isFocused ? theme.accent.opacity(0.45) : (hovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.05)), lineWidth: 0.8)
        )
        .onHover { hovered = $0 }
        .help(field.value)
    }
}

/// 就地动作处理结果卡片（支持结果滚动预览、对比原文、复制与直接粘贴、取消与重试）
struct InlineActionResultCard: View {
    let result: InlineActionResult
    let theme: AppTheme
    let language: AppLanguage
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onToggleOriginal: () -> Void
    let onDismiss: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onChangeLanguage: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 顶栏：图标 + 动作名 + 状态/差异 Badge + 语言切换 + 关闭
            HStack(spacing: 5) {
                Image(systemName: result.actionKind.icon)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text(headerTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accent)

                if let badge = result.badge {
                    Text(badge)
                        .font(.system(size: 8.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.accent.opacity(0.15)))
                        .foregroundStyle(theme.accent)
                }

                if result.actionKind == .translate {
                    Menu {
                        Button("简体中文") { onChangeLanguage?("zh-Hans") }
                        Button("English") { onChangeLanguage?("en") }
                        Button("日本語") { onChangeLanguage?("ja") }
                        Button("한국어") { onChangeLanguage?("ko") }
                        Button("Français") { onChangeLanguage?("fr") }
                        Button("Deutsch") { onChangeLanguage?("de") }
                    } label: {
                        HStack(spacing: 2) {
                            Text(result.targetLanguage == "en" ? "EN" : "中")
                                .font(.system(size: 8.5, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("action.close", lang: language))
            }

            // 内容展示区
            if let error = result.errorMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.red)
                    Text(error)
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .foregroundStyle(Color.red)
                    Spacer()
                    Button(action: onRetry) {
                        Text(L10n.tr("action.retry", lang: language))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.15)))
                            .foregroundStyle(Color.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.06)))
            } else {
                let displayText = result.showOriginal ? result.originalText : result.text
                ScrollView {
                    Text(displayText.isEmpty && result.isStreaming ? L10n.tr("action.processing", lang: language) : displayText)
                        .font(result.actionKind == .formatJSON ? .system(size: 10, design: .monospaced) : .system(size: 10.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(displayText.isEmpty ? Color.secondary : Color.primary)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 75)
                .modernScrollbar()
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
            }

            // 底栏操作按钮：直接粘贴、仅复制、比对、取消
            HStack(spacing: 5) {
                if result.isStreaming {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text(L10n.tr("action.processing", lang: language))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    Button(action: onCancel) {
                        Text(L10n.tr("action.cancel", lang: language))
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                } else if result.errorMessage == nil {
                    Button(action: onPaste) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.right.doc.on.clipboard")
                                .font(.system(size: 8))
                            Text(L10n.tr("action.paste", lang: language))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent))
                        .foregroundStyle(Color.white)
                    }
                    .buttonStyle(.plain)

                    Button(action: onCopy) {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 8))
                            Text(L10n.tr("action.copy", lang: language))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                        .foregroundStyle(Color.primary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button(action: onToggleOriginal) {
                        Text(result.showOriginal ? L10n.tr("action.view_result", lang: language) : L10n.tr("action.view_original", lang: language))
                            .font(.system(size: 8.5))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.accent.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.18), lineWidth: 0.8)
        )
        .padding(.top, 2)
    }

    private var headerTitle: String {
        switch result.actionKind {
        case .fixLineBreaks: return L10n.tr("action.fix_line_breaks", lang: language)
        case .deduplicateList: return L10n.tr("action.deduplicate_list", lang: language)
        case .formatJSON: return L10n.tr("action.format_json", lang: language)
        case .translate: return L10n.tr("action.translate", lang: language)
        }
    }
}
