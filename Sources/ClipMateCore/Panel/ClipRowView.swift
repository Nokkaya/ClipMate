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
        }
    }

    var tintColor: Color {
        switch self {
        case .text: return .blue
        case .url: return .cyan
        case .richText: return .indigo
        case .image: return .purple
        case .file: return .orange
        }
    }
}

/// 历史列表行：类型图标/缩略图 + 内容预览 + 来源应用 + 时间 + 标签。
struct ClipRowView: View {
    let item: ClipItem
    let selected: Bool
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
                        Label(item.sourceName, systemImage: "app")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    ForEach(item.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(item.kind.tintColor.opacity(0.15)))
                            .foregroundStyle(item.kind.tintColor)
                    }
                }
            }
            Spacer(minLength: 4)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Text("×\(item.useCount)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .opacity(item.useCount > 1 ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leading: some View {
        if item.kind == .image, let thumbnail {
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
