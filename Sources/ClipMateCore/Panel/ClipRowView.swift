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
struct ClipRowView: View {
    let item: ClipItem
    let selected: Bool
    var hovered: Bool = false
    var multiSelected: Bool = false
    let thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .foregroundStyle(item.kind == .image ? .secondary : .primary)
                HStack(spacing: 6) {
                    if !item.sourceName.isEmpty {
                        Text(item.sourceName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(item.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(item.kind.tintColor.opacity(0.13)))
                            .foregroundStyle(item.kind.tintColor)
                    }
                }
            }
            Spacer(minLength: 4)
            if multiSelected && !selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
            }
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.pin)
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
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 22)
                    .padding(.leading, 3)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if selected { return Color.accentColor.opacity(0.16) }
        if multiSelected { return Color.accentColor.opacity(0.08) }
        if hovered { return Color.primary.opacity(0.05) }
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
        } else {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15))
                .foregroundStyle(item.kind.tintColor)
                .frame(width: 22)
        }
    }
}
