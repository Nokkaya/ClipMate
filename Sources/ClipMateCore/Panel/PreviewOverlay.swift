import SwiftUI
import AppKit

/// 详情预览浮层（⌘I）：大图/全文/代码高亮/JSON格式化/文件清单 + 元信息 + 快捷操作。
struct PreviewOverlay: View {
    @ObservedObject var viewModel: PanelViewModel
    @State private var previewImage: NSImage?
    @State private var isLoadingMedia = false
    @State private var isRawJSON = false
    @State private var copiedFeedback = false

    var body: some View {
        if let item = viewModel.previewItem {
            ZStack {
                // 半透明背景，限制在圆角面板内部；点击背景关闭预览
                Color.black.opacity(0.32)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.previewItem = nil
                    }

                // 悬浮毛玻璃预览卡片
                VStack(alignment: .leading, spacing: 10) {
                    header(item)
                    content(item)
                    metaGrid(item)
                    footer(item)
                }
                .padding(14)
                .frame(width: 580)
                .background(VisualEffectBackground())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
                .padding(14)
                .task(id: item.id) {
                    previewImage = nil
                    isRawJSON = false
                    copiedFeedback = false
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

    // MARK: - 头部
    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(item.kind.tintColor)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(item.kind.tintColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                let headerText = item.title?.isEmpty == false ? item.title! : item.displayText
                if !viewModel.query.isEmpty {
                    Text(TextHighlighter.highlight(text: headerText, query: viewModel.query))
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                } else {
                    Text(headerText)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                }


                HStack(spacing: 6) {
                    Text(item.kind.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(item.kind.tintColor)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(TimeHelper.relative(item.createdAt))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if !item.sourceName.isEmpty {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(item.sourceName)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if item.pinned {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                    Text("已固定")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Palette.pin)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Palette.pin.opacity(0.15)))
            }

            Button {
                viewModel.previewItem = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    // MARK: - 内容展示
    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            imageSection(item)
        case .pdf:
            pdfSection(item)
        case .file:
            fileSection(item)
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

    // MARK: - 图片
    @ViewBuilder
    private func imageSection(_ item: ClipItem) -> some View {
        VStack(spacing: 6) {
            Group {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let thumb = viewModel.thumbnail(for: item) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoadingMedia {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("图片数据不可用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: item.plainText.isEmpty ? 220 : 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

            if !item.plainText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("识别到的文本 (Vision OCR)", systemImage: "text.viewfinder")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Button("复制文字") {
                            PasteBack.write(.text(item.plainText))
                            HapticHelper.feedback()
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10.5))
                    }
                    ScrollView {
                        if !viewModel.query.isEmpty {
                            Text(TextHighlighter.highlight(text: item.plainText, query: viewModel.query))
                                .font(.system(size: 11.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        } else {
                            Text(item.plainText)
                                .font(.system(size: 11.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }

                    .frame(maxHeight: 55)
                    .modernScrollbar()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.text.opacity(0.06)))
            }
        }
    }

    // MARK: - PDF
    @ViewBuilder
    private func pdfSection(_ item: ClipItem) -> some View {
        VStack(spacing: 6) {
            Group {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if isLoadingMedia {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("PDF 预览暂不可用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: item.plainText.isEmpty ? 220 : 160)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

            if !item.plainText.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("提取的正文", systemImage: "text.viewfinder")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.pdf)
                    ScrollView {
                        Text(item.plainText)
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 55)
                    .modernScrollbar()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.pdf.opacity(0.06)))
            }
        }
    }

    // MARK: - 网址链接
    @ViewBuilder
    private func urlSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let thumb = viewModel.thumbnail(for: item) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.1)))
                } else {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 30))
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
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let url = URL(string: item.plainText) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("在浏览器中打开", systemImage: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.url.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("完整链接")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("复制链接") {
                        viewModel.copy(item: item)
                        HapticHelper.feedback()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
                }

                ScrollView {
                    Text(item.plainText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .modernScrollbar()
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
            }
        }
    }

    // MARK: - JSON 数据
    @ViewBuilder
    private func jsonSection(_ item: ClipItem) -> some View {
        let highlighted = SyntaxHighlighter.highlightJSON(item.plainText)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("JSON 数据", systemImage: "curlybraces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.url)
                Spacer()
                Button(isRawJSON ? "格式化显示" : "原始显示") {
                    isRawJSON.toggle()
                    HapticHelper.alignment()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))

                if let formatted = highlighted?.formatted {
                    Button("复制格式化") {
                        PasteBack.write(.text(formatted))
                        HapticHelper.feedback()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5))
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
            .frame(maxHeight: 185)
            .modernScrollbar()
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    // MARK: - 代码高亮
    @ViewBuilder
    private func codeSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("代码高亮", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                let lineCount = item.plainText.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                Text("\(lineCount) 行")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button("复制代码") {
                    viewModel.copy(item: item)
                    HapticHelper.feedback()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
            }

            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    let lineCount = item.plainText.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                    let displayCount = min(lineCount, 500)
                    let lineNumbers = (1...displayCount).map(String.init).joined(separator: "\n")
                    Text(lineNumbers)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 24, alignment: .trailing)

                    Text(SyntaxHighlighter.highlightCode(item.plainText))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(8)
            }
            .frame(maxHeight: 185)
            .modernScrollbar()
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    // MARK: - 文件清单
    @ViewBuilder
    private func fileSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("文件清单", systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.file)
                Spacer()
                Text("\(filePaths(item).count) 个项目")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filePaths(item), id: \.self) { path in
                        let filename = URL(fileURLWithPath: path).lastPathComponent
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.file)
                            Text(filename)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("在访达中定位文件")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
            .frame(maxHeight: 185)
            .modernScrollbar()
        }
    }

    // MARK: - 普通文本
    @ViewBuilder
    private func defaultTextSection(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("文本正文", systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(item.plainText.count) 字符")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button("复制") {
                    viewModel.copy(item: item)
                    HapticHelper.feedback()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10.5))
            }

            ScrollView {
                if !viewModel.query.isEmpty {
                    Text(TextHighlighter.highlight(text: item.plainText, query: viewModel.query))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text(item.plainText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }

            .frame(maxHeight: 185)
            .modernScrollbar()
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        }
    }

    // MARK: - 元信息栏
    private func metaGrid(_ item: ClipItem) -> some View {
        HStack(spacing: 12) {
            if !item.sourceName.isEmpty {
                metaCell("来源", item.sourceName)
            }
            metaCell("时间", TimeHelper.relative(item.createdAt))
            metaCell("大小", SizeHelper.human(item.byteSize))
            if item.useCount > 1 {
                metaCell("使用", "\(item.useCount) 次")
            }

            Spacer()

            HStack(spacing: 4) {
                ForEach(item.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.kind.tintColor.opacity(0.14)))
                        .foregroundStyle(item.kind.tintColor)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
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

    // MARK: - 底部操作
    private func footer(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text("⏎")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                Text("粘贴")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text("⌘⏎")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                Text("复制")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(role: .destructive) {
                viewModel.previewItem = nil
                viewModel.delete(item: item)
            } label: {
                Label("删除", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if item.kind != .image {
                Button {
                    viewModel.previewItem = nil
                    viewModel.beginEdit(item: item)
                } label: {
                    Label("编辑…", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if item.isSnippet {
                Button {
                    viewModel.openEditSnippet(item: item)
                } label: {
                    Label("片段设置", systemImage: "bookmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    viewModel.openEditSnippet(item: item)
                } label: {
                    Label("存为片段", systemImage: "bookmark.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                _ = viewModel.toggleQueue(item: item)
                HapticHelper.alignment()
            } label: {
                Label(viewModel.queue.contains { $0.id == item.id } ? "移出队列" : "加入队列",
                      systemImage: "list.number")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                viewModel.copy(item: item)
                viewModel.previewItem = nil
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                viewModel.paste(item: item)
                viewModel.previewItem = nil
            } label: {
                Label("粘贴", systemImage: "arrow.right.doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func filePaths(_ item: ClipItem) -> [String] {
        item.plainText.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

