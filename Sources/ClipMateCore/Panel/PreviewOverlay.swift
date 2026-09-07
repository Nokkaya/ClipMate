import SwiftUI
import AppKit

/// 详情预览浮层（⌘I）：大图/全文/文件清单 + 元信息 + 常用操作。
struct PreviewOverlay: View {
    @ObservedObject var viewModel: PanelViewModel
    @State private var previewImage: NSImage?
    @State private var isLoadingMedia = false
    @State private var isRawJSON = false

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
                .frame(width: 520)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(color: .black.opacity(0.3), radius: 14)
                .padding(24)
                .task(id: item.id) {
                    previewImage = nil
                    isRawJSON = false
                    guard item.kind == .image || item.kind == .pdf else { return }
                    guard let url = viewModel.store.imageURL(for: item) else { return }
                    isLoadingMedia = true
                    defer { isLoadingMedia = false }
                    let fileData = await Task.detached(priority: .userInitiated) { () -> Data? in
                        try? Data(contentsOf: url)
                    }.value
                    guard !Task.isCancelled, let fileData else { return }
                    if item.kind == .image {
                        self.previewImage = NSImage(data: fileData)
                    } else if item.kind == .pdf {
                        self.previewImage = PDFHelper.firstPageImage(from: fileData)
                    }
                }
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
            imageSection(item)
            if !item.plainText.isEmpty {
                textSection(item, title: "识别到的文字（可搜索）")
            }
        case .pdf:
            pdfSection(item)
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
        case .url:
            urlSection(item)
        default:
            if item.tags.contains("JSON") || ((item.plainText.hasPrefix("{") || item.plainText.hasPrefix("[")) && SyntaxHighlighter.formatJSON(item.plainText) != nil) {
                jsonSection(item)
            } else if item.tags.contains("代码") || AutoTagger.isCode(item.plainText) {
                codeSection(item)
            } else {
                defaultTextSection(item)
            }
        }
    }

    @ViewBuilder
    private func defaultTextSection(_ item: ClipItem) -> some View {
        ScrollView {
            Text(item.plainText)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 240)
        .modernScrollbar()
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private func urlSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let thumb = viewModel.thumbnail(for: item) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                } else {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.url)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title = item.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                    } else {
                        Text(URL(string: item.plainText)?.host ?? "网页链接")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    if let host = URL(string: item.plainText)?.host {
                        Text(host)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let url = URL(string: item.plainText) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("打开", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Palette.url.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                Text("完整网址")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                ScrollView {
                    Text(item.plainText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .modernScrollbar()
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    @ViewBuilder
    private func jsonSection(_ item: ClipItem) -> some View {
        let highlighted = SyntaxHighlighter.highlightJSON(item.plainText)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("JSON", systemImage: "curlybraces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.url)
                Spacer()
                Button(isRawJSON ? "格式化" : "原始") {
                    isRawJSON.toggle()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))

                if let formatted = highlighted?.formatted {
                    Button("复制格式化") {
                        PasteBack.write(.text(formatted))
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                }
            }
            ScrollView {
                if isRawJSON || highlighted == nil {
                    Text(item.plainText)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else if let attr = highlighted?.attributed {
                    Text(attr)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(maxHeight: 240)
            .modernScrollbar()
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private func codeSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("代码高亮", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                Button("复制代码") {
                    viewModel.copy(item: item)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
            }
            ScrollView {
                HStack(alignment: .top, spacing: 8) {
                    let lineCount = item.plainText.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                    let displayCount = min(lineCount, 500)
                    let lineNumbers = (1...displayCount).map(String.init).joined(separator: "\n")
                    Text(lineNumbers)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 20, alignment: .trailing)

                    Text(SyntaxHighlighter.highlightCode(item.plainText))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(8)
            }
            .frame(maxHeight: 240)
            .modernScrollbar()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private func imageSection(_ item: ClipItem) -> some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        } else if let thumb = viewModel.thumbnail(for: item) {
            Image(nsImage: thumb)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        } else if isLoadingMedia {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Text("图片数据不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        }
    }

    @ViewBuilder
    private func pdfSection(_ item: ClipItem) -> some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        } else if isLoadingMedia {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            Text("PDF 数据不可用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
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
            .modernScrollbar()
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
