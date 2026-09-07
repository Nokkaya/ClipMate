import SwiftUI
import AppKit

/// 详情预览浮层（⌘I）：大图/全文/文件清单 + 元信息 + 常用操作。
struct PreviewOverlay: View {
    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        if let item = viewModel.previewItem {
            ZStack {
                Color.black.opacity(0.28)
                VStack(alignment: .leading, spacing: 10) {
                    header(item)
                    content(item)
                    metaGrid(item)
                    footer(item)
                }
                .padding(16)
                .frame(width: 500)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(color: .black.opacity(0.3), radius: 14)
                .padding(24)
            }
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .foregroundStyle(item.kind.tintColor)
            Text(item.displayText)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.pin)
            }
            Button {
                viewModel.previewItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let url = viewModel.store.imageURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            } else {
                Text("图片数据不可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            if !item.plainText.isEmpty {
                textSection(item, title: "识别到的文字（可搜索）")
            }
        case .pdf:
            if let url = viewModel.store.imageURL(for: item),
               let data = try? Data(contentsOf: url),
               let image = PDFHelper.firstPageImage(from: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            } else {
                Text("PDF 数据不可用")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            if !item.plainText.isEmpty {
                textSection(item, title: "提取的文字（可检索）")
            }
        case .file:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(filePaths(item), id: \.self) { path in
                    Label(URL(string: path)?.lastPathComponent ?? path, systemImage: "doc")
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        default:
            ScrollView {
                Text(item.plainText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 240)
            .scrollIndicators(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private func textSection(_ item: ClipItem, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "text.viewfinder")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(item.plainText)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 100)
            .scrollIndicators(.hidden)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.text.opacity(0.06)))
    }

    private func metaGrid(_ item: ClipItem) -> some View {
        HStack(spacing: 14) {
            if !item.sourceName.isEmpty { metaCell("来源", item.sourceName) }
            metaCell("时间", TimeHelper.relative(item.createdAt))
            metaCell("大小", SizeHelper.human(item.byteSize))
            if item.useCount > 1 { metaCell("使用", "×\(item.useCount)") }
            Spacer()
            ForEach(item.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(item.kind.tintColor.opacity(0.13)))
                    .foregroundStyle(item.kind.tintColor)
            }
        }
    }

    private func metaCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }

    private func footer(_ item: ClipItem) -> some View {
        HStack {
            Button("复制") { viewModel.copy(item: item) }
            Button("粘贴") { viewModel.paste(item: item) }
            if item.kind != .image {
                Button("编辑") { viewModel.previewItem = nil; viewModel.beginEdit(item: item) }
            }
            Button(viewModel.queue.contains { $0.id == item.id } ? "移出队列" : "加入队列") {
                _ = viewModel.toggleQueue(item: item)
            }
            Spacer()
            Button("删除", role: .destructive) {
                viewModel.previewItem = nil
                viewModel.delete(item: item)
            }
        }
    }

    private func filePaths(_ item: ClipItem) -> [String] {
        item.plainText.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}
