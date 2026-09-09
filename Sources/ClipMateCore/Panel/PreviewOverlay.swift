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
                .frame(width: viewModel.isAISidebarOpen ? 680 : 396)
                .background(
                    ZStack {
                        VisualEffectBackground()
                        viewModel.settings.appTheme.backgroundTint
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(viewModel.settings.appTheme.borderColor, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
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
            .frame(width: viewModel.isAISidebarOpen ? 880 : 440, height: 520)
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
                    Text(L10n.tr("preview.pinned"))
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
            }
            .clipMateIconButton(size: 22)
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
                        Text(L10n.tr("preview.image_unavailable"))
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
                        Label(L10n.tr("preview.ocr_title"), systemImage: "text.viewfinder")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Button(L10n.tr("preview.ocr_copy")) {
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
                        Text(L10n.tr("preview.pdf_unavailable"))
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
                    Label(L10n.tr("preview.pdf_extracted"), systemImage: "text.viewfinder")
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
                        Text(URL(string: item.plainText)?.host ?? L10n.tr("preview.url_default"))
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
                        Label(L10n.tr("action.open"), systemImage: "arrow.up.forward.app")
                    }
                    .clipMateAccent(size: .small, tint: Palette.url)
                    .help(L10n.tr("preview.url_open_tip"))
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Palette.url.opacity(0.08)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L10n.tr("preview.url_full"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(L10n.tr("preview.url_copy")) {
                        viewModel.copy(item: item)
                        HapticHelper.feedback()
                    }
                    .clipMateGlass(size: .small)
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
                Label(L10n.tr("preview.json_title"), systemImage: "curlybraces")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.url)
                Spacer()
                Button(isRawJSON ? L10n.tr("preview.json_format") : L10n.tr("preview.json_raw")) {
                    isRawJSON.toggle()
                    HapticHelper.alignment()
                }
                .clipMateGlass(size: .small)

                if let formatted = highlighted?.formatted {
                    Button(L10n.tr("preview.json_copy")) {
                        PasteBack.write(.text(formatted))
                        HapticHelper.feedback()
                    }
                    .clipMateGlass(size: .small)
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
                Label(L10n.tr("preview.code_title"), systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Spacer()
                let lineCount = item.plainText.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                Text(L10n.tr("meta.lines", lineCount))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button(L10n.tr("preview.code_copy")) {
                    viewModel.copy(item: item)
                    HapticHelper.feedback()
                }
                .clipMateGlass(size: .small)
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
                Label(L10n.tr("preview.file_title"), systemImage: "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.file)
                Spacer()
                Text(L10n.tr("meta.items", filePaths(item).count))
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
                            }
                            .clipMateIconButton(size: 22)
                            .help(L10n.tr("preview.file_locate_tip"))
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
                Label(L10n.tr("preview.text_title"), systemImage: "text.alignleft")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(L10n.tr("meta.chars", item.plainText.count))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button(L10n.tr("action.copy")) {
                    viewModel.copy(item: item)
                    HapticHelper.feedback()
                }
                .clipMateGlass(size: .small)
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
        HStack(spacing: 10) {
            if !item.sourceName.isEmpty {
                metaCell(L10n.tr("meta.source", lang: viewModel.settings.appLanguage), item.sourceName)
                    .frame(maxWidth: 80, alignment: .leading)
            }
            metaCell(L10n.tr("meta.time", lang: viewModel.settings.appLanguage), L10n.relativeTime(item.createdAt, lang: viewModel.settings.appLanguage))
            metaCell(L10n.tr("meta.size", lang: viewModel.settings.appLanguage), SizeHelper.human(item.byteSize))
            if item.useCount > 1 {
                metaCell(L10n.tr("meta.used", lang: viewModel.settings.appLanguage), L10n.tr("meta.uses_count", item.useCount, lang: viewModel.settings.appLanguage))
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                ForEach(item.tags.prefix(2), id: \.self) { tag in
                    Text(L10n.tagTitle(tag, lang: viewModel.settings.appLanguage))
                        .font(.system(size: 9.5))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(item.kind.tintColor.opacity(0.14)))
                        .foregroundStyle(item.kind.tintColor)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }

    private func metaCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
        }
    }

    // MARK: - 底部操作
    private func footer(_ item: ClipItem) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                // 次要动作图标按钮组
                HStack(spacing: 4) {
                    Button(role: .destructive) {
                        viewModel.previewItem = nil
                        viewModel.delete(item: item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .clipMateIconButton(size: 26, tint: .red)
                    .help(L10n.tr("preview.tip_delete"))

                    if item.kind != .image {
                        Button {
                            viewModel.previewItem = nil
                            viewModel.beginEdit(item: item)
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .clipMateIconButton(size: 26)
                        .help(L10n.tr("preview.tip_edit"))
                    }

                    Button {
                        viewModel.openEditSnippet(item: item)
                    } label: {
                        Image(systemName: item.isSnippet ? "bookmark.fill" : "bookmark")
                    }
                    .clipMateIconButton(size: 26, tint: item.isSnippet ? Palette.snippet : nil)
                    .help(item.isSnippet ? L10n.tr("preview.tip_snippet_edit") : L10n.tr("preview.tip_snippet_save"))

                    Button {
                        _ = viewModel.toggleQueue(item: item)
                        HapticHelper.alignment()
                    } label: {
                        Image(systemName: "list.number")
                    }
                    .clipMateIconButton(size: 26, tint: viewModel.queue.contains { $0.id == item.id } ? Color.accentColor : nil)
                    .help(viewModel.queue.contains { $0.id == item.id } ? L10n.tr("preview.tip_queue_remove") : L10n.tr("preview.tip_queue_add"))
                }

                Spacer(minLength: 4)

                // 主要操作：复制 / 粘贴
                HStack(spacing: 6) {
                    Button {
                        viewModel.copy(item: item)
                        viewModel.previewItem = nil
                    } label: {
                        Label(L10n.tr("action.copy"), systemImage: "doc.on.doc")
                    }
                    .clipMateGlass(size: .small)

                    Button {
                        viewModel.paste(item: item)
                        viewModel.previewItem = nil
                    } label: {
                        Label(L10n.tr("action.paste"), systemImage: "arrow.right.doc.on.clipboard")
                    }
                    .clipMateAccent(size: .small)
                }
            }

            // 快捷键提示条
            HStack(spacing: 4) {
                Text(L10n.tr("preview.shortcut_bar"))
                Spacer()
            }
            .font(.system(size: 9.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 2)
        }
    }

    private func filePaths(_ item: ClipItem) -> [String] {
        item.plainText.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}

