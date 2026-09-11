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
                onCopyOCR: (() -> Void)? = nil) {
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
        lhs.isExpanded == rhs.isExpanded
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
                    if !searchHighlight.isEmpty {
                        Text(TextHighlighter.highlight(text: item.displayText, query: searchHighlight))
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundStyle(item.kind == .image ? .secondary : .primary)
                    } else {
                        Text(item.displayText)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundStyle(item.kind == .image ? .secondary : .primary)
                    }
                }


                HStack(spacing: 6) {
                    if !item.sourceName.isEmpty {
                        Text(item.sourceName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(L10n.relativeTime(item.createdAt, lang: language))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if let group = item.snippetGroup, !group.isEmpty {
                        Text("🏷 \(group)")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.snippet.opacity(0.14)))
                            .foregroundStyle(Palette.snippet)
                    }
                    if let shortcode = item.snippetShortcode, !shortcode.isEmpty {
                        Text("⚡️ \(shortcode)")
                            .font(.system(size: 9, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(Color.orange)
                    }
                    ForEach(item.tags.filter { $0 != FilterKind.snippetTag && $0 != item.snippetGroup }.prefix(2), id: \.self) { tag in
                        Text(L10n.tagTitle(tag, lang: language))
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(item.kind.tintColor.opacity(0.13)))
                            .foregroundStyle(item.kind.tintColor)
                    }
                }

                if selected && !fields.isEmpty {
                    fieldSection
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(rowBackground)
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1)
                    .fill(theme.accent)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 3)
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
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                .shadow(color: swatch.opacity(0.4), radius: 3, y: 1)
                .frame(width: 22)

        } else if item.kind == .image, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 46, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        } else if item.kind == .url, let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(width: 22)
        } else if item.isSnippet {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 15))
                .foregroundStyle(Palette.snippet)
                .frame(width: 22)
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(item.kind.tintColor)
                .frame(width: 22)
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
                    .foregroundStyle(hovered ? theme.accent : Color.secondary.opacity(0.7))
                    .padding(.horizontal, 1)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("action.copy_only", lang: language))

            if index < 3 {
                Text("⌥\(index + 1)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isFocused ? theme.accent : Color.secondary.opacity(0.5))
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isFocused ? theme.accent.opacity(0.2) : (hovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(isFocused ? theme.accent : (hovered ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08)), lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .help(field.value)
    }
}
