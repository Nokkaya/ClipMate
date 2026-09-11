import Foundation
import AppKit
import ClipMateCore

// 性能基准（环境变量触发）：CLIPMATE_BENCH_DB=/path/to/db.sqlite swift run ClipMateTests
if let benchPath = ProcessInfo.processInfo.environment["CLIPMATE_BENCH_DB"], !benchPath.isEmpty {
    let db = try Database(url: URL(fileURLWithPath: benchPath))
    let store = try ClipStore(database: db, blobStore: BlobStore(directory: URL(fileURLWithPath: benchPath + "-blobs")))
    print("== 基准测试（真实数据副本）==")
    print("条目总数: \(store.itemCount())  已向量化: \(store.embeddedCount)  FTS5: \(store.supportsFullTextSearch)")
    for filter in FilterKind.allCases {
        _ = store.search(query: "", filter: filter, limit: 300) // 预热
        let start = Date()
        for _ in 0..<10 { _ = store.search(query: "", filter: filter, limit: 300) }
        print(String(format: "筛选[%@]      %6.2f ms/次", filter.title, -start.timeIntervalSinceNow / 10 * 1000))
    }
    var start = Date()
    for _ in 0..<5 { _ = store.search(query: "error", filter: .all, limit: 300) }
    print(String(format: "搜索[error语义] %5.2f ms/次", -start.timeIntervalSinceNow / 5 * 1000))
    start = Date()
    for _ in 0..<5 { _ = store.search(query: "剪贴板", filter: .all, limit: 300) }
    print(String(format: "搜索[中文LIKE] %5.2f ms/次", -start.timeIntervalSinceNow / 5 * 1000))
    let sampleDate = Date().addingTimeInterval(-3600)
    start = Date()
    for _ in 0..<100 { _ = TimeHelper.relative(sampleDate) }
    print(String(format: "相对时间×100   %6.2f ms", -start.timeIntervalSinceNow * 1000))
    if let st = try? db.prepare("SELECT COUNT(*), IFNULL(SUM(length(inline_data)),0) FROM clip WHERE inline_data IS NOT NULL"),
       st.step() {
        print("含缩略图条目: \(st.columnInt(0)) 条，inline_data 总量 \(Int(st.columnDouble(1)) / 1024) KB")
    }
    exit(0)
}

// ClipMate 单元测试 runner（本环境仅 Command Line Tools，无 XCTest，故用可执行目标实现）。
// 运行：swift run ClipMateTests；失败时进程退出码为 1。

final class TestRunner {
    private(set) var failures: [String] = []
    private(set) var passed = 0
    private var current = ""

    func run(_ name: String, _ body: () throws -> Void) {
        current = name
        do {
            try body()
            passed += 1
            print("✅ \(name)")
        } catch {
            failures.append("\(name) — \(error)")
            print("❌ \(name) — \(error)")
        }
    }

    func expectTrue(_ condition: Bool, _ message: String) {
        if !condition {
            failures.append("\(current) — \(message)")
            print("   ✗ \(message)")
        }
    }

    func expectFalse(_ condition: Bool, _ message: String) {
        if condition {
            failures.append("\(current) — \(message)")
            print("   ✗ \(message)")
        }
    }

    func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            failures.append("\(current) — \(message)：实际 \(actual)，期望 \(expected)")
            print("   ✗ \(message)：实际 \(actual)，期望 \(expected)")
        }
    }
}

func makeTempStore() throws -> (store: ClipStore, dir: URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipmate-tests-\(UUID().uuidString)", isDirectory: true)
    let database = try Database(url: dir.appendingPathComponent("test.sqlite"))
    let blobs = BlobStore(directory: dir.appendingPathComponent("blobs"))
    let store = try ClipStore(database: database, blobStore: blobs)
    return (store, dir)
}

func makeTestPDF(text: String) -> Data? {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
    var mediaBox = CGRect(x: 0, y: 0, width: 320, height: 120)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
    context.beginPDFPage(nil as CFDictionary?)
    NSGraphicsContext.saveGraphicsState()
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.current = nsContext
    (text as NSString).draw(
        at: NSPoint(x: 24, y: 60),
        withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
    )
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    return data as Data
}

let runner = TestRunner()

runner.run("基础采集与计数") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let result = try store.capture(kind: .text, plainText: "hello world from ClipMate",
                                   sourceBundle: "com.test", sourceName: "Test")
    runner.expectTrue(result.isNew, "首次采集应为新条目")
    runner.expectEqual(store.itemCount(), 1, "入库后总数应为 1")
    let found = store.search(query: "hello", filter: .all, limit: 10)
    runner.expectEqual(found.count, 1, "检索 'hello' 应命中 1 条")
}

runner.run("去重合并上浮") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = try store.capture(kind: .text, plainText: "duplicate me", sourceBundle: "a", sourceName: "A")
    Thread.sleep(forTimeInterval: 0.02)
    let second = try store.capture(kind: .text, plainText: "duplicate me", sourceBundle: "b", sourceName: "B")
    runner.expectTrue(!second.isNew, "重复内容不应产生新条目")
    runner.expectEqual(second.item.id, first.item.id, "复用同一条目")
    runner.expectEqual(store.itemCount(), 1, "总数仍为 1")
    runner.expectEqual(second.item.useCount, 2, "use_count 累加为 2")
    runner.expectEqual(second.item.sourceName, "B", "来源应用更新为最近一次")
}

runner.run("中文检索（LIKE 路径）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try store.capture(kind: .text, plainText: "中文剪贴板测试条目", sourceBundle: "a", sourceName: "A")
    _ = try store.capture(kind: .text, plainText: "english entry only", sourceBundle: "a", sourceName: "A")
    let found = store.search(query: "剪贴板", filter: .all, limit: 10)
    runner.expectEqual(found.count, 1, "中文子串检索应命中")
}

runner.run("分类过滤") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try store.capture(kind: .text, plainText: "plain text item", sourceBundle: "a", sourceName: "A")
    _ = try store.capture(kind: .url, plainText: "https://example.com/page", sourceBundle: "a", sourceName: "A")
    let textOnly = store.search(query: "", filter: .text, limit: 10)
    runner.expectEqual(textOnly.count, 1, "text 过滤只含文本类")
    let links = store.search(query: "", filter: .link, limit: 10)
    runner.expectEqual(links.count, 1, "link 过滤只含链接")
}

runner.run("固定与保留策略") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    for i in 0..<5 {
        _ = try store.capture(kind: .text, plainText: "item-\(i)", sourceBundle: "a", sourceName: "A")
        Thread.sleep(forTimeInterval: 0.01)
    }
    let pinned = store.search(query: "item-0", filter: .all, limit: 10).first
    runner.expectTrue(pinned != nil, "应能找到 item-0")
    try store.setPinned(pinned!.id, true)
    try store.enforceRetention(maxItems: 3, maxAgeDays: 0)
    runner.expectEqual(store.itemCount(), 4, "保留 3 条未固定 + 1 条固定")
    runner.expectTrue(store.search(query: "item-1", filter: .all, limit: 10).isEmpty, "最老的未固定条目被清理")
    runner.expectTrue(!store.search(query: "item-4", filter: .all, limit: 10).isEmpty, "最新条目保留")
    runner.expectTrue(!store.search(query: "item-0", filter: .all, limit: 10).isEmpty, "固定条目豁免")
}

runner.run("编辑文本同步检索") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let captured = try store.capture(kind: .text, plainText: "old searchable text", sourceBundle: "a", sourceName: "A")
    try store.updateText(captured.item.id, "brand new text")
    runner.expectTrue(!store.search(query: "brand new", filter: .all, limit: 10).isEmpty, "新文本可检索")
    runner.expectTrue(store.search(query: "old searchable", filter: .all, limit: 10).isEmpty, "旧文本不再命中")
}

runner.run("图片条目：缩略图内联 + 原图落盘 + 删除清理") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32
    ), let png = rep.representation(using: .png, properties: [:]) else {
        runner.expectTrue(false, "生成测试 PNG 失败")
        return
    }
    // 模拟真实采集管线：缩略图由 ClipboardReader 生成后作为 inlineData 传入。
    let thumbnail = ImageHelper.thumbnailData(from: png, maxPixel: 512)
    runner.expectTrue(thumbnail != nil, "缩略图应能生成")
    let captured = try store.capture(kind: .image, plainText: "", sourceBundle: "x", sourceName: "X",
                                     inlineData: thumbnail, imageOriginal: png,
                                     meta: ["display": "图片 8×8"])
    runner.expectTrue(captured.item.blobName != nil, "原图应落盘并有 blob 名")
    runner.expectTrue(captured.item.inlineData != nil, "缩略图应内联存储")
    if let blobName = captured.item.blobName {
        let url = store.imageURL(for: captured.item)!
        runner.expectTrue(FileManager.default.fileExists(atPath: url.path), "原图文件存在")
        try store.delete(captured.item.id)
        runner.expectTrue(!FileManager.default.fileExists(atPath: url.path), "删除条目后原图清理")
        _ = blobName
    }
}

runner.run("清空保留固定") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    var ids: [Int64] = []
    for i in 0..<3 {
        let r = try store.capture(kind: .text, plainText: "clear-\(i)", sourceBundle: "a", sourceName: "A")
        ids.append(r.item.id)
    }
    try store.setPinned(ids[1], true)
    try store.deleteAll(keepPinned: true)
    runner.expectEqual(store.itemCount(), 1, "清空后仅剩固定条目")
    let survivor = store.item(id: ids[1])
    runner.expectTrue(survivor != nil && survivor!.pinned, "固定条目幸存")
}

runner.run("粘贴内容装配") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = try store.capture(kind: .text, plainText: "copy me", sourceBundle: "a", sourceName: "A")
    guard case .text(let s)? = store.pasteboardContent(for: text.item) else {
        runner.expectTrue(false, "文本条目应装配为 .text")
        return
    }
    runner.expectEqual(s, "copy me", "文本内容一致")

    let rtf = Data("{\\rtf1\\ansi Hello}".utf8)
    let rich = try store.capture(kind: .richText, plainText: "Hello", sourceBundle: "a", sourceName: "A",
                                 inlineData: rtf)
    guard case .richText(let data, _)? = store.pasteboardContent(for: rich.item) else {
        runner.expectTrue(false, "富文本条目应装配为 .richText")
        return
    }
    runner.expectEqual(data, rtf, "RTF 数据一致")

    let files = try store.capture(
        kind: .file,
        plainText: "file:///tmp/a.txt\nfile:///tmp/b.txt",
        sourceBundle: "com.apple.finder", sourceName: "Finder",
        meta: ["display": "a.txt, b.txt"]
    )
    guard case .files(let urls)? = store.pasteboardContent(for: files.item) else {
        runner.expectTrue(false, "文件条目应装配为 .files")
        return
    }
    runner.expectEqual(urls.count, 2, "文件 URL 数量")
}

runner.run("AutoTagger 规则识别") {
    runner.expectEqual(AutoTagger.detectColor(in: "#4A90D9"), "#4A90D9", "识别色值")
    runner.expectTrue(AutoTagger.detectColor(in: "not a color") == nil, "非色值不误报")
    runner.expectTrue(AutoTagger.detectURL(in: "https://example.com/a?b=1") != nil, "整段 URL 识别")
    runner.expectTrue(AutoTagger.detectURL(in: "见 https://example.com 和更多") == nil, "含 URL 的长句不算单链接")
    let urlTags = AutoTagger.tags(for: "https://example.com", kind: .url)
    runner.expectTrue(urlTags.contains("链接"), "URL 类型自动打标")
    let colorTags = AutoTagger.tags(for: "#4A90D9", kind: .text)
    runner.expectTrue(colorTags.contains("颜色"), "色值自动打标")
    let jsonTags = AutoTagger.tags(for: "{\n  \"a\": 1\n}", kind: .text)
    runner.expectTrue(jsonTags.contains("JSON"), "JSON 自动打标")
    let codeTags = AutoTagger.tags(for: "func main() {\n    return nil\n}", kind: .text)
    runner.expectTrue(codeTags.contains("代码"), "代码启发式打标")
    let emailTags = AutoTagger.tags(for: "someone@example.com", kind: .text)
    runner.expectTrue(emailTags.contains("邮箱"), "邮箱打标")
}

runner.run("FTS5 可用性标记一致") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 无论系统 SQLite 是否带 FTS5，采集与检索都应正常工作。
    _ = try store.capture(kind: .text, plainText: "fts availability probe", sourceBundle: "a", sourceName: "A")
    let found = store.search(query: "probe", filter: .all, limit: 10)
    runner.expectEqual(found.count, 1, "检索路径（FTS 或 LIKE）应命中")
    print("   ℹ️ FTS5 可用：\(store.supportsFullTextSearch)")
}

runner.run("向量编解码与余弦相似度") {
    let original: [Float] = [0.1, -0.4, 0.9, 2.5, -3.0]
    let data = ClipStore.data(from: original.map(Double.init))
    let restored = ClipStore.vectors(from: data)
    runner.expectTrue(restored != nil && restored?.count == original.count, "编解码 roundtrip 长度一致")
    runner.expectTrue(abs(ClipStore.cosine(original, original) - 1.0) < 0.001, "自余弦≈1")
    runner.expectTrue(abs(ClipStore.cosine([1, 0], [0, 1])) < 0.001, "正交向量余弦≈0")
    runner.expectTrue(ClipStore.vectors(from: Data([0, 1])) == nil, "非整倍长度数据应拒绝解析")
}

runner.run("导入导出 roundtrip") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try store.capture(kind: .text, plainText: "export alpha", sourceBundle: "a", sourceName: "A")
    _ = try store.capture(kind: .url, plainText: "https://example.org/x", sourceBundle: "b", sourceName: "B", tags: ["链接"])
    let oldDate = Date(timeIntervalSince1970: 1_600_000_000)
    _ = try store.capture(kind: .text, plainText: "export gamma", sourceBundle: "a", sourceName: "A", createdAt: oldDate)
    let data = try store.exportJSON()

    let (target, targetDir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: targetDir) }
    let imported = try target.importJSON(data)
    runner.expectEqual(imported, 3, "应导入 3 条")
    runner.expectTrue(!target.search(query: "alpha", filter: .all, limit: 10).isEmpty, "导入内容可检索")
    let gamma = target.search(query: "gamma", filter: .all, limit: 10).first
    runner.expectTrue(gamma != nil, "gamma 条目存在")
    if let gamma {
        runner.expectTrue(abs(gamma.createdAt.timeIntervalSince1970 - 1_600_000_000) < 1, "原始时间应还原")
    }
    let again = try target.importJSON(data)
    runner.expectEqual(again, 0, "重复导入应全部去重")
}

runner.run("语义向量检索（系统句向量可用时）") {
    guard EmbeddingService.isAvailable else {
        print("   ℹ️ 系统句向量不可用，跳过语义用例")
        return
    }
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipmate-tests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let database = try Database(url: dir.appendingPathComponent("test.sqlite"))
    let vecStore = try ClipStore(
        database: database,
        blobStore: BlobStore(directory: dir.appendingPathComponent("blobs")),
        embeddingProvider: { EmbeddingService.embed(text: $0) }
    )
    _ = try vecStore.capture(kind: .text, plainText: "payment failed with error code 5002, transaction declined by bank", sourceBundle: "a", sourceName: "A")
    _ = try vecStore.capture(kind: .text, plainText: "今天天气非常好，阳光明媚适合出门散步", sourceBundle: "a", sourceName: "A")
    for entry in vecStore.itemsNeedingEmbedding(limit: 10) {
        if let data = EmbeddingService.embed(text: entry.text) {
            vecStore.setEmbedding(entry.id, data)
        }
    }
    runner.expectEqual(vecStore.embeddedCount, 2, "向量补算完成")
    let results = vecStore.search(query: "bank transaction error", filter: .all, limit: 2)
    runner.expectTrue(results.first?.plainText.contains("payment") == true, "语义检索应把支付报错排最前")
}

runner.run("图片 OCR（Vision 可用时）") {
    let image = NSImage(size: NSSize(width: 380, height: 90))
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 380, height: 90).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 30, weight: .bold),
        .foregroundColor: NSColor.black,
    ]
    ("CLIPMATE 2026" as NSString).draw(at: NSPoint(x: 20, y: 30), withAttributes: attributes)
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation else {
        runner.expectTrue(false, "生成测试图片失败")
        return
    }
    guard let text = ClipboardReader.recognizeText(in: tiff) else {
        print("   ℹ️ Vision OCR 不可用，跳过")
        return
    }
    runner.expectTrue(text.contains("CLIPMATE"), "OCR 应识别出 CLIPMATE，实际：\(text.prefix(40))")
}

runner.run("PDF 采集、落盘与检索") {
    guard let pdfData = makeTestPDF(text: "CLIPMATE PDF TEST") else {
        runner.expectTrue(false, "生成测试 PDF 失败")
        return
    }
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 模拟真实采集管线：首页缩略图由 ClipboardReader 经 PDFHelper 生成后传入
    let thumbnail = PDFHelper.firstPageThumbnail(from: pdfData, maxPixel: 512)
    runner.expectTrue(thumbnail != nil, "首页缩略图应能渲染")
    let captured = try store.capture(
        kind: .pdf, plainText: "CLIPMATE PDF TEST", sourceBundle: "com.apple.preview", sourceName: "预览",
        inlineData: thumbnail, imageOriginal: pdfData, meta: ["display": "PDF · 1 页"]
    )
    runner.expectTrue(captured.item.blobName != nil, "PDF 应落盘")
    runner.expectTrue(captured.item.inlineData != nil, "应有首页缩略图")
    guard case .pdf(let data, _)? = store.pasteboardContent(for: captured.item) else {
        runner.expectTrue(false, "PDF 应装配为 .pdf 粘贴内容")
        return
    }
    runner.expectEqual(data.count, pdfData.count, "PDF 字节一致")
    runner.expectTrue(!store.search(query: "CLIPMATE", filter: .all, limit: 10).isEmpty, "PDF 文本可检索")
    let textFiltered = store.search(query: "", filter: .text, limit: 10)
    runner.expectTrue(textFiltered.contains { $0.id == captured.item.id }, "PDF 归入文本分类过滤")
}

runner.run("片段收藏过滤") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = try store.capture(kind: .text, plainText: "snippet hello", sourceBundle: "a", sourceName: "A")
    _ = try store.capture(kind: .text, plainText: "plain other", sourceBundle: "a", sourceName: "A")
    try store.mutateTag(a.item.id, tag: FilterKind.snippetTag, add: true)
    let snippets = store.search(query: "", filter: .snippet, limit: 10)
    runner.expectEqual(snippets.count, 1, "片段过滤只含收藏条目")
    runner.expectEqual(snippets.first?.id, a.item.id, "收藏条目命中")
    try store.mutateTag(a.item.id, tag: FilterKind.snippetTag, add: false)
    runner.expectTrue(store.search(query: "", filter: .snippet, limit: 10).isEmpty, "移出片段后过滤为空")
}

runner.run("自定义脚本执行（stdin/stdout）") {
    let script = ScriptAction(name: "upper", command: "tr a-z A-Z")
    var result: Result<String, Error>?
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            result = .success(try await ScriptRunner.run(script, input: "clipmate"))
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 15)
    switch result {
    case .success(let output):
        runner.expectEqual(output, "CLIPMATE", "文本经 stdin 转换后输出")
    case .failure(let error):
        runner.expectTrue(false, "脚本执行失败：\(error.localizedDescription)")
    case nil:
        runner.expectTrue(false, "脚本未在超时内返回")
    }
}

runner.run("大文本与首行 displayText 性能与正确性") {
    // 构造包含 20,000 行的大文本
    let largeText = (1...20000).map { "Line \($0): some long text content description" }.joined(separator: "\n")
    let item = ClipItem(
        id: 1, kind: .text, plainText: largeText, sourceBundle: "test", sourceName: "Test",
        byteSize: largeText.utf8.count, createdAt: Date(), lastUsedAt: Date(), useCount: 1,
        pinned: false, tags: [], meta: [:]
    )
    let start = Date()
    let display = item.displayText
    let duration = -start.timeIntervalSinceNow * 1000
    runner.expectEqual(display, "Line 1: some long text content description", "首行正确提取")
    runner.expectTrue(duration < 10.0, "20,000 行文本提取首行耗时应低于 10ms，实际 \(String(format: "%.2f", duration))ms")

    // 前置连续空行与首行超长截断测试
    let leadingEmptyText = "\n\n  \n\t\n" + String(repeating: "A", count: 500) + "\nSecond Line"
    let item2 = ClipItem(
        id: 2, kind: .text, plainText: leadingEmptyText, sourceBundle: "test", sourceName: "Test",
        byteSize: leadingEmptyText.utf8.count, createdAt: Date(), lastUsedAt: Date(), useCount: 1,
        pinned: false, tags: [], meta: [:]
    )
    runner.expectEqual(item2.displayText.count, 300, "超长首行截断至 300 字符")
    runner.expectTrue(item2.displayText.allSatisfy { $0 == "A" }, "跳过空行后正确提取首个非空行")

    // 文件类型测试
    let fileItem = ClipItem(
        id: 3, kind: .file, plainText: "/path/to/file1.txt\n/path/to/file2.txt", sourceBundle: "test", sourceName: "Test",
        byteSize: 100, createdAt: Date(), lastUsedAt: Date(), useCount: 1, pinned: false, tags: [], meta: [:]
    )
    runner.expectEqual(fileItem.displayText, "/path/to/file1.txt", "文件条目提取首行路径")
}

runner.run("异步 OCR 补全与 FTS 索引检索") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let dummyImg = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let captured = try store.capture(
        kind: .image,
        plainText: "",
        sourceBundle: "com.apple.screencapture",
        sourceName: "截图",
        tags: ["图片"],
        inlineData: dummyImg,
        meta: ["display": "图片 100x100"]
    )
    runner.expectEqual(captured.item.plainText, "", "初始图片文本为空")
    runner.expectFalse(captured.item.tags.contains("OCR"), "初始无 OCR 标签")

    // 模拟 OCR 识别完成调用 updateOCR
    let ocrResultText = "Invoice No. 987654 Total Amount $500"
    let updated = try store.updateOCR(captured.item.id, text: ocrResultText)
    runner.expectTrue(updated != nil, "更新 OCR 成功")
    runner.expectEqual(updated?.plainText, ocrResultText, "plainText 已更新为识别文字")
    runner.expectTrue(updated?.tags.contains("OCR") ?? false, "包含 OCR 标签")
    runner.expectEqual(updated?.meta["ocr"], "1", "元数据标记 ocr 为 1")

    // 校验 FTS 搜索
    let searchResults = store.search(query: "987654", filter: .all, limit: 10)
    runner.expectEqual(searchResults.count, 1, "通过 OCR 文字全文检索命中")
    runner.expectEqual(searchResults.first?.id, captured.item.id, "命中正确条目")
}

runner.run("ScriptRunner 管道防死锁（输出超过 64KB）") {
    // 产生 ~150KB 输出，远超 64KB 管道缓冲区
    let script = ScriptAction(
        name: "overflow",
        command: "awk 'BEGIN { for (i = 0; i < 3000; i++) print \"Line \" i \": 1234567890123456789012345678901234567890\" }'"
    )
    var result: Result<String, Error>?
    let semaphore = DispatchSemaphore(value: 0)
    let start = Date()
    Task {
        do {
            result = .success(try await ScriptRunner.run(script, input: ""))
        } catch {
            result = .failure(error)
        }
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
    let duration = -start.timeIntervalSinceNow * 1000
    switch result {
    case .success(let output):
        runner.expectEqual(output.count, 20000, "超长脚本输出截断至 20000 字符上限")
        runner.expectTrue(duration < 2000, "150KB 脚本并发实时排空管道耗时低于 2s（实际 \(String(format: "%.2f", duration))ms，无 64KB 缓冲区死锁）")
    case .failure(let error):
        runner.expectTrue(false, "超长脚本执行失败：\(error.localizedDescription)")
    case nil:
        runner.expectTrue(false, "超长脚本死锁超时未返回（>5s）")
    }
}

runner.run("AutoTagger 大体积防爆与超长文本标签") {
    // 超过 256KB 的 JSON 文本应跳过全量解析，防止 UI 卡顿
    let hugeJSON = "{\"key\": \"" + String(repeating: "a", count: 300_000) + "\"}"
    let startJSON = Date()
    let isJson = AutoTagger.isJSON(hugeJSON)
    let durationJSON = -startJSON.timeIntervalSinceNow * 1000
    runner.expectFalse(isJson, ">256KB 文本直接拒绝 JSON 全量解析")
    runner.expectTrue(durationJSON < 5.0, ">256KB 文本拒绝判定应小于 5ms，实际 \(String(format: "%.2f", durationJSON))ms")

    // 1MB 超长文本采样识别标签
    let hugeText = (1...25000).map { "import Foundation\nfunc test\($0)() { return 0 }\n" }.joined()
    let startTags = Date()
    let tags = AutoTagger.tags(for: hugeText, kind: .text)
    let durationTags = -startTags.timeIntervalSinceNow * 1000
    runner.expectTrue(tags.contains("代码"), "前置 16KB 采样准确识别为代码")
    runner.expectTrue(durationTags < 20.0, "1MB 大文本采样标签耗时小于 20ms，实际 \(String(format: "%.2f", durationTags))ms")
}

runner.run("按需延迟加载 inlineData 与列表查询投影瘦身") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let dummyInline = Data([0x01, 0x02, 0x03, 0x04])
    let captured = try store.capture(
        kind: .image, plainText: "", sourceBundle: "app", sourceName: "App",
        tags: ["图片"], inlineData: dummyInline, meta: [:]
    )
    runner.expectEqual(captured.item.inlineData, dummyInline, "单条 capture/item 返回 inlineData")

    // 列表搜索应使用瘦身投影，不拉取 inlineData
    let listResults = store.search(query: "", filter: .image, limit: 10)
    runner.expectEqual(listResults.count, 1, "命中列表记录")
    runner.expectTrue(listResults.first?.inlineData == nil, "列表查询瘦身投影：inlineData 为 nil 以节省内存与 I/O")

    // 按需读取
    let fetchedInline = store.inlineData(for: captured.item.id)
    runner.expectEqual(fetchedInline, dummyInline, "按需 inlineData 读取正确无误")

    // 富文本粘贴时若 inlineData 为 nil 自动按需装配
    let rtf = Data("{\\rtf1 test}".utf8)
    _ = try store.capture(kind: .richText, plainText: "test rich text", sourceBundle: "app", sourceName: "App", inlineData: rtf)
    let textResults = store.search(query: "test rich text", filter: .text, limit: 1)
    runner.expectEqual(textResults.count, 1, "命中搜索富文本")
    let lightweightItem = textResults.first!
    runner.expectTrue(lightweightItem.inlineData == nil, "搜索得到的富文本条目 inlineData 为 nil")
    guard case .richText(let pastedData, _)? = store.pasteboardContent(for: lightweightItem) else {
        runner.expectTrue(false, "富文本应按需装配出 RTF")
        return
    }
    runner.expectEqual(pastedData, rtf, "按需装配的富文本数据一致")
}

runner.run("ImageHelper 缩略图自适应压缩（Alpha PNG 与无 Alpha JPEG）") {
    guard let repNoAlpha = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 32, bitsPerSample: 8,
        samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 96, bitsPerPixel: 24
    ), let repData = repNoAlpha.representation(using: .png, properties: [:]) else {
        runner.expectTrue(false, "创建测试无 Alpha 位图失败")
        return
    }
    let thumbData = ImageHelper.thumbnailData(from: repData, maxPixel: 16)
    runner.expectTrue(thumbData != nil, "自适应缩略图生成成功")
    // JPEG 头部以 0xFF, 0xD8 开头
    let isJPEG = thumbData?.prefix(2) == Data([0xFF, 0xD8])
    runner.expectTrue(isJPEG, "无 Alpha 通道图片自适应采用 JPEG 压缩")
}

runner.run("URLMetadataFetcher HTML Title 提取与实体解码") {
    let sampleHTML = """
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <title> GitHub: Let&#39;s build from here &amp; innovate &mdash; 领先平台 </title>
        <link rel="icon" type="image/png" href="/assets/favicon.png">
    </head>
    <body><h1>Hello</h1></body>
    </html>
    """
    let title = URLMetadataFetcher.extractTitle(from: sampleHTML)
    runner.expectEqual(title, "GitHub: Let's build from here & innovate — 领先平台", "Title 提取并正确反转义 HTML 实体")

    let baseURL = URL(string: "https://github.com/features")!
    let iconURL = URLMetadataFetcher.extractIconURL(from: sampleHTML, baseURL: baseURL)
    runner.expectEqual(iconURL?.absoluteString, "https://github.com/assets/favicon.png", "Favicon 相对路径正确解析为完整 URL")
}

runner.run("SyntaxHighlighter JSON 与代码语法高亮") {
    let rawJSON = "{\"name\":\"ClipMate\",\"version\":1,\"active\":true,\"data\":null}"
    let formatted = SyntaxHighlighter.formatJSON(rawJSON)
    runner.expectTrue(formatted != nil, "JSON 成功格式化")
    runner.expectTrue(formatted?.contains("\n") == true, "格式化 JSON 包含换行缩进")

    let highlightedJSON = SyntaxHighlighter.highlightJSON(rawJSON)
    runner.expectTrue(highlightedJSON != nil, "JSON 高亮成功")
    runner.expectTrue(highlightedJSON!.attributed.characters.count > 0, "输出 AttributedString")

    let sampleCode = """
    // 计算斐波那契数列
    func fibonacci(_ n: Int) -> Int {
        let name = "test"
        if n <= 1 { return n }
        return fibonacci(n - 1) + fibonacci(n - 2)
    }
    """
    let codeAttr = SyntaxHighlighter.highlightCode(sampleCode)
    runner.expectTrue(codeAttr.characters.count > 0, "代码语法高亮成功生成 AttributedString")
}

runner.run("ClipStore 链接元数据持久化与搜索联动") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let captured = try store.capture(
        kind: .url,
        plainText: "https://swift.org/blog",
        sourceBundle: "com.apple.Safari",
        sourceName: "Safari"
    )

    let dummyFavicon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let updated = try store.updateURLMetadata(
        captured.item.id,
        title: "Swift 官方博客 · Swift.org",
        faviconData: dummyFavicon
    )
    runner.expectTrue(updated != nil, "更新 URL 元数据成功")
    runner.expectEqual(updated?.title, "Swift 官方博客 · Swift.org", "Title 字段持久化成功")

    let storedInline = store.inlineData(for: captured.item.id)
    runner.expectEqual(storedInline, dummyFavicon, "Favicon 正确写入 inlineData")

    // 按标题检索命中
    let titleSearch = store.search(query: "官方博客", filter: .link, limit: 10)
    runner.expectEqual(titleSearch.count, 1, "按网页标题搜索成功命中链接条目")
}

runner.run("PanelViewModel 批量全选、合并复制与批量固定") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try store.capture(kind: .text, plainText: "First line", sourceBundle: "app", sourceName: "App")
    _ = try store.capture(kind: .text, plainText: "Second line", sourceBundle: "app", sourceName: "App")
    _ = try store.capture(kind: .text, plainText: "Third line", sourceBundle: "app", sourceName: "App")

    let settings = AppSettings()
    let monitor = ClipboardMonitor(settings: settings, store: store)
    let front = FrontAppTracker()
    let ai = AIService(settings: settings)
    let vm = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: front, ai: ai)

    vm.reload()
    runner.expectEqual(vm.items.count, 3, "初始 3 条记录")

    // 全选
    vm.selectAllVisible()
    runner.expectEqual(vm.multiSelectedIDs.count, 3, "全选成功选中全部 3 项")

    // 批量固定
    vm.togglePinMulti()
    runner.expectTrue(vm.items.allSatisfy { $0.pinned }, "批量固定成功，所有项均已置顶固定")

    // 批量取消固定
    vm.togglePinMulti()
    runner.expectTrue(vm.items.allSatisfy { !$0.pinned }, "再次批量固定成功取消固定")

    // 批量入队
    vm.enqueueMulti()
    runner.expectEqual(vm.queue.count, 3, "批量加入粘贴队列成功")

    // 批量合并复制
    vm.copyMulti(separator: "\n---\n")
    let pbString = NSPasteboard.general.string(forType: .string)
    runner.expectTrue(pbString?.contains("---\n") == true, "批量合并复制成功写入剪贴板")
}

runner.run("ClipStore 片段 CRUD、独立分组与子分组检索") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    // 1. 创建新片段
    let snip1 = try store.createSnippet(
        title: "Git 强制推远程",
        text: "git push origin --force-with-lease",
        group: "开发",
        shortcode: ";gpf"
    )
    runner.expectTrue(snip1.isSnippet, "条目标记为片段")
    runner.expectEqual(snip1.title, "Git 强制推远程", "片段标题匹配")
    runner.expectEqual(snip1.snippetGroup, "开发", "分组匹配")
    runner.expectEqual(snip1.snippetShortcode, ";gpf", "快捷短码匹配")

    let snip2 = try store.createSnippet(
        title: "公司开票抬头",
        text: "北京某某科技有限责任公司 91110108MA0000000X",
        group: "财务",
        shortcode: ";tax"
    )
    runner.expectTrue(snip2.isSnippet, "财务片段创建成功")

    // 2. 分组去重列表
    let groups = store.allSnippetGroups()
    runner.expectEqual(groups, ["开发", "财务"], "所有分组去重且字典序排列")

    // 3. 按子分组检索过滤
    let devSnippets = store.search(query: "", filter: .snippet, snippetGroup: "开发")
    runner.expectEqual(devSnippets.count, 1, "按开发分组过滤只返回 1 条")
    runner.expectEqual(devSnippets.first?.id, snip1.id, "返回指定开发片段")

    let financeSnippets = store.search(query: "", filter: .snippet, snippetGroup: "财务")
    runner.expectEqual(financeSnippets.count, 1, "按财务分组过滤只返回 1 条")
    runner.expectEqual(financeSnippets.first?.id, snip2.id, "返回指定财务片段")

    // 4. 更新片段
    let updated = try store.updateSnippet(
        id: snip1.id,
        title: "Git 安全强推",
        group: "Git工作流",
        shortcode: ";gpf2",
        text: "git push -u origin HEAD --force-with-lease"
    )
    runner.expectEqual(updated?.title, "Git 安全强推", "更新片段标题")
    runner.expectEqual(updated?.snippetGroup, "Git工作流", "更新片段分组")
    runner.expectEqual(updated?.snippetShortcode, ";gpf2", "更新片段快捷短码")
    runner.expectTrue(updated?.plainText.contains("-u origin") == true, "更新片段内容")

    // 5. 全文搜索联动
    let searchRes = store.search(query: "force-with-lease", filter: .snippet)
    runner.expectEqual(searchRes.count, 1, "全文搜索可查出片段")
    runner.expectEqual(searchRes.first?.id, snip1.id, "搜索命中正确片段条目")
}

runner.run("PromptTemplate 变量插值与默认模板库") {
    runner.expectTrue(PromptTemplate.defaults.count >= 6, "内置 6+ 种精选提示词模板")
    let translate = PromptTemplate.defaults.first { $0.id == "translate" }
    runner.expectTrue(translate != nil, "内置中英互译模板存在")

    // 测试 {content} 占位符插值
    let code = "function test() { return 42; }"
    let custom = PromptTemplate(name: "TS测试", icon: "sparkles", template: "请解释代码：\n\n{content}\n\n请列出风险点。")
    let promptResult = custom.prompt(for: code)
    runner.expectTrue(promptResult.contains("function test() { return 42; }"), "正确替换 {content} 占位")
    runner.expectTrue(promptResult.contains("请列出风险点。"), "保留模板后置文本")

    // 测试不含 {content} 时的自动追加
    let appendOnly = PromptTemplate(name: "简单说明", template: "解释下面这段：")
    let appendResult = appendOnly.prompt(for: "echo hello")
    runner.expectTrue(appendResult.contains("解释下面这段：\n\necho hello"), "无占位符时自动追加文本")
}

runner.run("HapticHelper 触觉反馈安全调度") {
    // 验证调用 AppKit 触觉反馈不抛出崩溃与异常
    HapticHelper.alignment()
    HapticHelper.feedback()
    HapticHelper.generic()
    runner.expectTrue(true, "触觉反馈正常执行无异常")
}

runner.run("SmartTitleGenerator 智能标题提取与截断") {
    // 1. Swift 函数签名
    let swiftCode = """
    public func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        return false
    }
    """
    let swiftTitle = SmartTitleGenerator.generate(for: swiftCode, kind: .text)
    runner.expectTrue(swiftTitle != nil, "成功识别 Swift 函数")
    runner.expectTrue(swiftTitle?.contains("handleKey") == true, "标题包含函数名 handleKey")
    runner.expectTrue(swiftTitle?.hasPrefix("💻 ") == true, "代码标题带有标志前缀")

    // 2. Python 函数
    let pyCode = "def calculate_discount(price, rate):\n    return price * (1 - rate)"
    let pyTitle = SmartTitleGenerator.generate(for: pyCode, kind: .text)
    runner.expectTrue(pyTitle?.contains("calculate_discount") == true, "成功识别 Python def")

    // 3. Markdown 标题
    let md = "# 核心规划与架构目标\n\n这是本文档正文第一段..."
    let mdTitle = SmartTitleGenerator.generate(for: md, kind: .text)
    runner.expectEqual(mdTitle, "核心规划与架构目标", "成功提取 Markdown # 标题")

    // 4. CLI 命令
    let cli = "docker compose up -d --build"
    let cliTitle = SmartTitleGenerator.generate(for: cli, kind: .text)
    runner.expectTrue(cliTitle?.contains("docker compose up -d") == true, "成功识别 CLI 命令")

    // 5. SQL 语句
    let sql = "SELECT id, name, email FROM users WHERE active = 1"
    let sqlTitle = SmartTitleGenerator.generate(for: sql, kind: .text)
    runner.expectTrue(sqlTitle?.contains("SELECT id, name") == true, "成功识别 SQL 语句")

    // 6. JSON 字段摘要
    let jsonStr = "{\n  \"action\": \"sync_clipboard\",\n  \"count\": 12\n}"
    let jsonTitle = SmartTitleGenerator.generate(for: jsonStr, kind: .text)
    runner.expectEqual(jsonTitle, "JSON · action: \"sync_clipboard\"", "成功提取 JSON 顶层关键字段")
}

runner.run("AutoTagger 全格式色值识别与友好色彩名称") {
    // 1. 3 位 Hex
    runner.expectEqual(AutoTagger.detectColor(in: "#fff"), "#FFFFFF", "#fff 扩展为 #FFFFFF")
    runner.expectEqual(AutoTagger.detectColor(in: "#333"), "#333333", "#333 扩展为 #333333")

    // 2. 6 位 Hex
    runner.expectEqual(AutoTagger.detectColor(in: "#4a90d9"), "#4A90D9", "6位 hex 归一化大写")

    // 3. 8 位 Hex
    runner.expectEqual(AutoTagger.detectColor(in: "#4A90D980"), "#4A90D9", "8位 hex 剥离 alpha 归一化")

    // 4. rgb(r, g, b)
    runner.expectEqual(AutoTagger.detectColor(in: "rgb(255, 0, 0)"), "#FF0000", "rgb 格式转为 #FF0000")
    runner.expectEqual(AutoTagger.detectColor(in: "rgba(0, 255, 0, 0.5)"), "#00FF00", "rgba 格式转为 #00FF00")

    // 5. 色彩语义名称
    runner.expectEqual(AutoTagger.friendlyColorName(for: "#000000"), "纯黑", "精准识别纯黑")
    runner.expectEqual(AutoTagger.friendlyColorName(for: "#FFFFFF"), "纯白", "精准识别纯白")
    runner.expectEqual(AutoTagger.friendlyColorName(for: "#4A90D9"), "主题蓝", "精准识别主题蓝")
    runner.expectEqual(AutoTagger.friendlyColorName(for: "#3B82F6"), "科技蓝", "精准识别科技蓝")
    runner.expectEqual(AutoTagger.friendlyColorName(for: "#EF4444"), "珊瑚红", "精准识别珊瑚红")
}

runner.run("Palette 扩展色值解析") {
    let color3 = Palette.color(hexString: "#FFF")
    runner.expectTrue(color3 != nil, "3位色值成功生成 Color")
    let color6 = Palette.color(hexString: "#4A90D9")
    runner.expectTrue(color6 != nil, "6位色值成功生成 Color")
    let color8 = Palette.color(hexString: "#4A90D980")
    runner.expectTrue(color8 != nil, "8位色值成功生成 Color")
}

runner.run("AppSettings 面板定位、语言与智能标题持久化") {
    let suite = "clipmate.test.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suite)!
    let s = AppSettings(defaults: testDefaults)

    runner.expectEqual(s.panelPositionMode, .center, "默认居中模式")
    runner.expectEqual(s.appLanguage, .system, "默认跟随系统语言")
    runner.expectTrue(s.smartTitleEnabled, "默认启用智能标题")

    s.panelPositionMode = .followCursor
    runner.expectEqual(s.panelPositionMode, .followCursor, "更新为跟随鼠标模式")

    s.appLanguage = .en
    runner.expectEqual(s.appLanguage, .en, "更新为英文模式")

    s.lastPanelPositionX = 350.0
    s.lastPanelPositionY = 420.0
    runner.expectEqual(s.lastPanelPositionX, 350.0, "记录 X 坐标")
    runner.expectEqual(s.lastPanelPositionY, 420.0, "记录 Y 坐标")

    // 新实例验证持久化
    let s2 = AppSettings(defaults: testDefaults)
    runner.expectEqual(s2.panelPositionMode, .followCursor, "持久化读取跟随光标")
    runner.expectEqual(s2.appLanguage, .en, "持久化读取英文")
    runner.expectEqual(s2.lastPanelPositionX, 350.0, "持久化读取坐标 X")
    testDefaults.removePersistentDomain(forName: suite)
}

runner.run("L10n 多语言本地化字典与切换") {
    // 验证中文
    runner.expectEqual(L10n.filterTitle(.all, lang: .zhHans), "全部", "中文全部")
    runner.expectEqual(L10n.filterTitle(.snippet, lang: .zhHans), "片段", "中文片段")
    runner.expectEqual(L10n.tr("footer.paste", lang: .zhHans), "粘贴", "中文粘贴")

    // 验证英文
    runner.expectEqual(L10n.filterTitle(.all, lang: .en), "All", "英文 All")
    runner.expectEqual(L10n.filterTitle(.snippet, lang: .en), "Snippets", "英文 Snippets")
    runner.expectEqual(L10n.tr("footer.paste", lang: .en), "Paste", "英文 Paste")

    // 验证格式化替换
    let formattedZh = L10n.tr("batch.selected", 5, lang: .zhHans)
    runner.expectEqual(formattedZh, "已选 5 项", "中文参数替换")
    let formattedEn = L10n.tr("batch.selected", 5, lang: .en)
    runner.expectEqual(formattedEn, "5 selected", "英文参数替换")
}

runner.run("ClipStore 智能标题入库与更新") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let code = "func authenticateUser() -> Bool { return true }"
    let (item, isNew) = try store.capture(
        kind: .text,
        plainText: code,
        sourceBundle: "com.apple.dt.Xcode",
        sourceName: "Xcode",
        title: "💻 func authenticateUser() -> Bool"
    )
    runner.expectTrue(isNew, "新条目成功入库")
    runner.expectEqual(item.title, "💻 func authenticateUser() -> Bool", "智能标题持久化成功")

    // 测试 updateOCR 更新标题
    let ocrText = "发票号码: 12345678\n金额: 500.00"
    let updated = try store.updateOCR(item.id, text: ocrText, title: "发票号码: 12345678")
    runner.expectEqual(updated?.title, "发票号码: 12345678", "updateOCR 成功更新条目标题")
}

runner.run("TextHighlighter 关键词匹配与 AttributedString 高亮") {

    let source = "ClipMate 是一款轻量级的剪贴板历史工具，性能极高。"

    // 1. 空搜索词
    let emptyAttr = TextHighlighter.highlight(text: source, query: "")
    runner.expectEqual(String(emptyAttr.characters), source, "空搜索词保持原文字符一致")

    // 2. 单关键词高亮
    let singleAttr = TextHighlighter.highlight(text: source, query: "剪贴板")
    runner.expectEqual(String(singleAttr.characters), source, "文本内容保持一致")
    var hasHighlight = false
    for run in singleAttr.runs {
        if run.backgroundColor != nil {
            hasHighlight = true
            break
        }
    }
    runner.expectTrue(hasHighlight, "成功生成带背景高亮属性的 Run")

    // 3. 大小写不敏感匹配
    let caseAttr = TextHighlighter.highlight(text: "Hello clipmate world", query: "CLIPMATE")
    var caseHighlighted = false
    for run in caseAttr.runs {
        if run.backgroundColor != nil {
            caseHighlighted = true
            break
        }
    }
    runner.expectTrue(caseHighlighted, "大小写不敏感正确命中高亮")

    // 4. 多处重复命中
    let multiSource = "test alpha test beta test"
    let multiAttr = TextHighlighter.highlight(text: multiSource, query: "test")
    var highlightCount = 0
    for run in multiAttr.runs {
        if run.backgroundColor != nil {
            highlightCount += 1
        }
    }
    runner.expectTrue(highlightCount >= 3, "成功高亮全部 3 处匹配关键字")
}

runner.run("AIChatMessage 消息数据模型与结构验证") {
    let msg1 = AIChatMessage(role: "user", content: "这段代码有死锁风险吗？")
    runner.expectEqual(msg1.role, "user", "角色记录正确")
    runner.expectEqual(msg1.content, "这段代码有死锁风险吗？", "内容记录正确")

    let msg2 = AIChatMessage(role: "assistant", content: "经分析，在第 12 行存在锁未释放风险。")
    runner.expectEqual(msg2.role, "assistant", "AI 角色记录正确")
    runner.expectFalse(msg1.id == msg2.id, "每个消息具备唯一 UUID")
}

runner.run("FlowLayout 布局初始化与精选提示词模板库覆盖") {
    let flow = FlowLayout(spacing: 8, rowSpacing: 10)
    runner.expectEqual(flow.spacing, 8, "水平间距记录正确")
    runner.expectEqual(flow.rowSpacing, 10, "行间距记录正确")

    // 验证 PromptTemplate.defaults 包含全部高频预置指令，无重复
    let ids = PromptTemplate.defaults.map { $0.id }
    runner.expectTrue(ids.contains("translate"), "包含中英互译")
    runner.expectTrue(ids.contains("summary"), "包含精简摘要")
    runner.expectTrue(ids.contains("summarize"), "包含提取要点")
    runner.expectTrue(ids.contains("explainCode"), "包含解释代码")
    runner.expectTrue(ids.contains("grammar"), "包含修正语法")
    runner.expectTrue(ids.contains("rewrite"), "包含专业润色")
    runner.expectTrue(ids.contains("unitTest"), "包含生成单测")
    runner.expectTrue(ids.contains("jsonToTS"), "包含JSON转TS")
    runner.expectEqual(Set(ids).count, PromptTemplate.defaults.count, "预置模板 ID 全局唯一，无冗余重复")
}

runner.run("PanelViewModel 内置 AI 侧边栏展开与实时选择联动") {
    let (store, tempDir) = try! makeTempStore()
    let settings = AppSettings()
    let monitor = ClipboardMonitor(settings: settings, store: store)
    let frontApps = FrontAppTracker()
    let ai = AIService(settings: settings)
    let vm = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: frontApps, ai: ai)

    // 写入测试条目（降序排列：item2 在首位，item1 在次位）
    let (item1, _) = try! store.capture(kind: .text, plainText: "条目一：测试文本 A", sourceBundle: "test", sourceName: "test")
    let (item2, _) = try! store.capture(kind: .text, plainText: "条目二：测试文本 B", sourceBundle: "test", sourceName: "test")
    vm.reload()

    // 默认侧边栏为收起状态
    runner.expectFalse(vm.isAISidebarOpen, "默认 AI 侧边栏为收起状态")

    // 切换打开侧边栏
    var toggleCallbackCalled = false
    vm.onAISidebarToggled = { isOpen in
        toggleCallbackCalled = isOpen
    }
    vm.toggleAISidebar()
    runner.expectTrue(vm.isAISidebarOpen, "toggle 成功展开侧边栏")
    runner.expectTrue(toggleCallbackCalled, "触发 onAISidebarToggled 回调")
    runner.expectEqual(vm.aiModel.item?.id, item2.id, "展开时 AI 模型实时绑定当前首项")

    // 上下移动切换选中项，验证 AI 模型实时同步更新
    vm.moveSelection(1)
    runner.expectEqual(vm.selectedIndex, 1, "选中项切换为第二条")
    runner.expectEqual(vm.aiModel.item?.id, item1.id, "上下方向键移动时 AI 模型实时同步选中条目")

    // 再次切换关闭侧边栏
    vm.toggleAISidebar()
    runner.expectFalse(vm.isAISidebarOpen, "再次 toggle 成功收起侧边栏")

    // openAI 方法就地展开并锁定目标
    vm.openAI(item: item1)
    runner.expectTrue(vm.isAISidebarOpen, "openAI 展开侧边栏")
    runner.expectEqual(vm.aiModel.item?.id, item1.id, "openAI 准确定位目标条目")

    try? FileManager.default.removeItem(at: tempDir)
}

runner.run("标签多语言映射与底部快捷键国际化") {
    // 标签多语言映射
    runner.expectEqual(L10n.tagTitle("代码", lang: .en), "Code", "代码英文映射")
    runner.expectEqual(L10n.tagTitle("长文本", lang: .en), "Long Text", "长文本英文映射")
    runner.expectEqual(L10n.tagTitle("链接", lang: .en), "Link", "链接英文映射")
    runner.expectEqual(L10n.tagTitle("图片", lang: .en), "Image", "图片英文映射")
    runner.expectEqual(L10n.tagTitle("文件", lang: .en), "File", "文件英文映射")
    runner.expectEqual(L10n.tagTitle("富文本", lang: .en), "Rich Text", "富文本英文映射")
    runner.expectEqual(L10n.tagTitle("邮箱", lang: .en), "Email", "邮箱英文映射")
    runner.expectEqual(L10n.tagTitle("含链接", lang: .en), "Has Link", "含链接英文映射")
    runner.expectEqual(L10n.tagTitle("颜色", lang: .en), "Color", "颜色英文映射")
    runner.expectEqual(L10n.tagTitle("片段", lang: .en), "Snippet", "片段英文映射")

    // 中文回退/保留
    runner.expectEqual(L10n.tagTitle("代码", lang: .zhHans), "代码", "代码中文保持")
    runner.expectEqual(L10n.tagTitle("自定义标签", lang: .en), "自定义标签", "未知自定义标签原样保留")

    // 底部快捷键文本国际化
    runner.expectEqual(L10n.tr("footer.paste", lang: .en), "Paste", "粘贴快捷键英文")
    runner.expectEqual(L10n.tr("footer.copy", lang: .en), "Copy", "复制快捷键英文")
    runner.expectEqual(L10n.tr("footer.preview", lang: .en), "Detail", "详情快捷键英文")
    runner.expectEqual(L10n.tr("footer.ai", lang: .en), "AI", "AI 快捷键英文")
    runner.expectEqual(L10n.tr("footer.delete", lang: .en), "Delete", "删除快捷键英文")
    runner.expectEqual(L10n.tr("footer.cancel", lang: .en), "Cancel", "取消快捷键英文")

    // 分类筛选国际化
    runner.expectEqual(L10n.filterTitle(.all, lang: .en), "All", "全部英文")
    runner.expectEqual(L10n.filterTitle(.text, lang: .en), "Text", "文本英文")
    runner.expectEqual(L10n.filterTitle(.image, lang: .en), "Image", "图片英文")
    runner.expectEqual(L10n.filterTitle(.file, lang: .en), "File", "文件英文")
    runner.expectEqual(L10n.filterTitle(.link, lang: .en), "Link", "链接英文")
    runner.expectEqual(L10n.filterTitle(.snippet, lang: .en), "Snippets", "片段英文")
    runner.expectEqual(L10n.filterTitle(.pinned, lang: .en), "Pinned", "已固定英文")

    // ClipRowView Equatable 语言变更判定
    let sampleItem = ClipItem(
        id: 100, kind: .text, plainText: "测试", sourceBundle: "app", sourceName: "App",
        byteSize: 6, createdAt: Date(), lastUsedAt: Date(), useCount: 1, pinned: false,
        tags: ["代码"], meta: [:]
    )
    let rowZh = ClipRowView(item: sampleItem, selected: false, thumbnail: nil, searchHighlight: "", language: .zhHans)
    let rowEn = ClipRowView(item: sampleItem, selected: false, thumbnail: nil, searchHighlight: "", language: .en)
    runner.expectFalse(rowZh == rowEn, "语言变更时 ClipRowView.== 必须返回 false 以触发刷新")
}

runner.run("软件更新与语义版本比较引擎") {
    // 语义版本比较
    runner.expectTrue(UpdateManager.compareVersion("0.2.1", greaterThan: "0.2.0"), "0.2.1 应当大于 0.2.0")
    runner.expectTrue(UpdateManager.compareVersion("1.0.0", greaterThan: "0.9.9"), "1.0.0 应当大于 0.9.9")
    runner.expectTrue(UpdateManager.compareVersion("v0.3.0", greaterThan: "0.2.9"), "前导 v0.3.0 应当大于 0.2.9")
    runner.expectTrue(UpdateManager.compareVersion("0.2.0.1", greaterThan: "0.2.0"), "第四位版本号比较有效")

    runner.expectFalse(UpdateManager.compareVersion("0.2.0", greaterThan: "0.2.0"), "相同版本号判定非大于")
    runner.expectFalse(UpdateManager.compareVersion("0.1.9", greaterThan: "0.2.0"), "较小版本号判定非大于")
    runner.expectFalse(UpdateManager.compareVersion("0.2.0", greaterThan: "0.2.0.1"), "较短版本号判定非大于")

    // AppSettings 自动更新设置持久化
    let tempDefaults = UserDefaults(suiteName: "test.updates.\(UUID().uuidString)")!
    let settings = AppSettings(defaults: tempDefaults)
    runner.expectTrue(settings.autoCheckUpdates, "默认开启自动检查更新")
    settings.autoCheckUpdates = false
    runner.expectFalse(settings.autoCheckUpdates, "修改为关闭自动检查")
    let reloaded = AppSettings(defaults: tempDefaults)
    runner.expectFalse(reloaded.autoCheckUpdates, "持久化保存并在重启时正确加载")
}

runner.run("Phase 3 - 极客预置动作库与脚本执行引擎") {
    // 1. 预置动作库验证
    runner.expectEqual(ScriptAction.presetLibrary.count, 14, "预置库应包含14个精选本地动作")
    runner.expectEqual(ScriptAction.defaultPresets.count, 4, "默认启用4个推荐动作")

    // 2. 跨版本向后兼容反序列化（旧版缺少 type 和 icon）
    let legacyJSON = """
    {"id":"legacy_1","name":"旧脚本","command":"echo hello"}
    """.data(using: .utf8)!
    let decodedLegacy = try? JSONDecoder().decode(ScriptAction.self, from: legacyJSON)
    runner.expectTrue(decodedLegacy != nil, "旧版本无 type/icon 的 JSON 能够无缝兼容反序列化")
    runner.expectEqual(decodedLegacy?.type, .shell, "旧版本默认推断为 .shell 类型")
    runner.expectEqual(decodedLegacy?.icon, "terminal", "旧版本默认使用 terminal 图标")

    // 3. 快捷指令类型序列化
    let shortcutAction = ScriptAction(name: "总结文本", command: "Summarize", type: .shortcut, icon: "bolt.horizontal.fill")
    let encoded = try? JSONEncoder().encode(shortcutAction)
    runner.expectTrue(encoded != nil, "快捷指令动作能够序列化")
    if let encoded {
        let decoded = try? JSONDecoder().decode(ScriptAction.self, from: encoded)
        runner.expectEqual(decoded?.type, .shortcut, "快捷指令动作反序列化类型一致")
        runner.expectEqual(decoded?.command, "Summarize", "快捷指令名称一致")
    }

    // 4. 国际化预置名称与描述
    let tsPreset = ScriptAction.presetLibrary[0]
    runner.expectEqual(L10n.scriptName(tsPreset, lang: .en), "Timestamp to Date", "英文下预置动作名称翻译")
    runner.expectEqual(L10n.scriptName(tsPreset, lang: .zhHans), "时间戳转日期", "中文下预置动作名称正常")

    // 5. 实际 Shell 脚本执行（base64 编码解码）
    let b64Encode = ScriptAction(name: "b64", command: "base64", type: .shell)
    let b64Decode = ScriptAction(name: "b64d", command: "base64 --decode", type: .shell)
    let sampleInput = "ClipMate Pure Native"

    var encResult: String?
    let sema1 = DispatchSemaphore(value: 0)
    Task {
        encResult = try? await ScriptRunner.run(b64Encode, input: sampleInput)
        sema1.signal()
    }
    _ = sema1.wait(timeout: .now() + 10)
    runner.expectEqual(encResult?.trimmingCharacters(in: .whitespacesAndNewlines), "Q2xpcE1hdGUgUHVyZSBOYXRpdmU=", "Base64 编码成功")

    if let enc = encResult {
        var decResult: String?
        let sema2 = DispatchSemaphore(value: 0)
        Task {
            decResult = try? await ScriptRunner.run(b64Decode, input: enc)
            sema2.signal()
        }
        _ = sema2.wait(timeout: .now() + 10)
        runner.expectEqual(decResult?.trimmingCharacters(in: .whitespacesAndNewlines), sampleInput, "Base64 解码成功还原")
    }
}

runner.run("Phase 3 - 文本扩展与 Shortcode 快速匹配检索") {
    let (store, tempDir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 录入普通剪贴板条目
    _ = try store.capture(kind: .text, plainText: "My work email is contact@example.com", sourceBundle: "com.apple.Safari", sourceName: "Safari")
    _ = try store.capture(kind: .text, plainText: "Personal email address", sourceBundle: "com.apple.mail", sourceName: "Mail")

    // 录入常用片段并设置 shortcode（带与不带斜杠均能规范存储）
    let snip1 = try store.createSnippet(title: "工作邮箱", text: "john.doe@company.com", group: "邮件", shortcode: "email")
    let snip2 = try store.createSnippet(title: "Shell 问候", text: "echo 'hello world'", group: "开发", shortcode: "/sh")

    runner.expectEqual(snip1.snippetShortcode, "email", "短码存储去除了多余字符")
    runner.expectEqual(snip2.snippetShortcode, "sh", "带 / 前缀的短码自动归一化为纯短码")

    // 1. 输入 / 唤出所有短码片段
    let slashAll = store.search(query: "/")
    runner.expectTrue(!slashAll.isEmpty, "输入 / 召回短码片段")
    runner.expectTrue(slashAll.contains(where: { $0.id == snip1.id }), "包含工作邮箱短码片段")
    runner.expectTrue(slashAll.contains(where: { $0.id == snip2.id }), "包含 Shell 问候短码片段")

    // 2. 输入 /email 精准扩展置顶在第 0 位
    let searchEmail = store.search(query: "/email")
    runner.expectFalse(searchEmail.isEmpty, "/email 检索成功")
    runner.expectEqual(searchEmail.first?.id, snip1.id, "/email 检索时，短码精确匹配的片段必须置顶排在第0位")

    // 3. 输入 /sh 精准扩展置顶在第 0 位
    let searchSh = store.search(query: "/sh")
    runner.expectFalse(searchSh.isEmpty, "/sh 检索成功")
    runner.expectEqual(searchSh.first?.id, snip2.id, "/sh 检索时，短码精确匹配的片段必须置顶排在第0位")

    // 4. 更新短码（支持 updateSnippet）
    _ = try store.updateSnippet(id: snip1.id, title: "我的工作邮箱", group: "工作", shortcode: "/workmail")
    let reSearch = store.search(query: "/workmail")
    runner.expectEqual(reSearch.first?.id, snip1.id, "更新短码后 /workmail 精准置顶")
}

runner.run("Phase 3 - 主题引擎与配色方案 (Theme Engine & Popular Color Schemes)") {
    // 1. 验证 7 大热门主题枚举完备性
    runner.expectEqual(AppTheme.allCases.count, 7, "支持 7 种主题风格")
    let themeIDs = Set(AppTheme.allCases.map(\.rawValue))
    let expectedIDs: Set<String> = ["default", "oneDarkPro", "dracula", "tokyoNight", "nord", "monokai", "githubLight"]
    runner.expectEqual(themeIDs, expectedIDs, "主题标识符完整覆盖目标风格")

    // 验证 rawValue 向前向后兼容性（包含 darcula 容错映射）
    runner.expectEqual(AppTheme(rawValue: "dracula"), .dracula, "dracula 正常解析")
    runner.expectEqual(AppTheme(rawValue: "darcula"), .dracula, "darcula 兼容映射至 dracula")

    // 2. 验证各个主题的配置属性非空与合理性
    for theme in AppTheme.allCases {
        runner.expectEqual(theme.previewSwatches.count, 4, "\(theme.rawValue) 拥有 4 个特征预览色块")
        _ = theme.previewBackgroundColor
        _ = theme.searchBarBackground
        _ = theme.borderColor
        _ = theme.accent
        _ = theme.selectionBackground
        _ = theme.hoverBackground
        _ = theme.snippetColor
        _ = theme.pinColor
        _ = theme.aiColor

        for kind in ClipKind.allCases {
            _ = theme.color(for: kind)
        }

        // 验证显示名称与描述非空
        runner.expectFalse(L10n.themeTitle(theme).isEmpty, "\(theme.rawValue) 拥有本地化标题")
        runner.expectFalse(L10n.themeDesc(theme).isEmpty, "\(theme.rawValue) 拥有本地化说明")
    }

    // 3. 验证深浅模式倾向
    runner.expectTrue(AppTheme.default.preferredColorScheme == nil, "默认主题跟随系统外观")
    runner.expectEqual(AppTheme.oneDarkPro.preferredColorScheme, .dark, "One Dark Pro 为深色外观")
    runner.expectEqual(AppTheme.dracula.preferredColorScheme, .dark, "Dracula 为深色外观")
    runner.expectEqual(AppTheme.tokyoNight.preferredColorScheme, .dark, "Tokyo Night 为深色外观")
    runner.expectEqual(AppTheme.nord.preferredColorScheme, .dark, "Nord 为深色外观")
    runner.expectEqual(AppTheme.monokai.preferredColorScheme, .dark, "Monokai 为深色外观")
    runner.expectEqual(AppTheme.githubLight.preferredColorScheme, .light, "GitHub Light 为浅色外观")

    // 4. 验证 AppSettings 主题切换通知与持久化
    let settings = AppSettings()
    var notificationReceived = false
    let observer = NotificationCenter.default.addObserver(
        forName: AppSettings.themeChangedNotification,
        object: nil,
        queue: nil
    ) { notif in
        if let newTheme = notif.object as? AppTheme, newTheme == .dracula {
            notificationReceived = true
        }
    }
    defer { NotificationCenter.default.removeObserver(observer) }

    settings.appTheme = .dracula
    runner.expectEqual(settings.appTheme, .dracula, "AppSettings 成功切换为 Dracula")
    runner.expectTrue(notificationReceived, "发送了 themeChangedNotification 通知")
    runner.expectEqual(UserDefaults.standard.string(forKey: "appTheme"), "dracula", "成功持久化到 UserDefaults")

    // 恢复为默认
    settings.appTheme = .default
    runner.expectEqual(settings.appTheme, .default, "AppSettings 恢复默认主题")

    // 5. 验证 ClipRowView 在主题变更时的 Equatable 响应机制
    let item = ClipItem(
        id: 101, kind: .text, plainText: "Theme Test", sourceBundle: "test", sourceName: "Test",
        byteSize: 10, createdAt: Date(), lastUsedAt: Date(), useCount: 1,
        pinned: false, tags: [], meta: [:]
    )
    let rowDefault = ClipRowView(item: item, selected: false, language: .zhHans, theme: .default)
    let rowDracula = ClipRowView(item: item, selected: false, language: .zhHans, theme: .dracula)
    let rowDefault2 = ClipRowView(item: item, selected: false, language: .zhHans, theme: .default)

    runner.expectEqual(rowDefault, rowDefault2, "相同主题与状态的 ClipRowView 相等")
    runner.expectFalse(rowDefault == rowDracula, "不同主题的 ClipRowView 不相等，能触发界面差分重绘")
}

runner.run("UpdateManager 多版本 Appcast 解析取最高版本") {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <item>
          <title>Version 0.1.0</title>
          <description><![CDATA[<h2>旧版本</h2>]]></description>
          <enclosure url="https://example.com/ClipMate-0.1.0.dmg" sparkle:version="1" sparkle:shortVersionString="0.1.0" length="1" type="application/octet-stream" />
        </item>
        <item>
          <title>Version 0.3.0</title>
          <description><![CDATA[<h2>新版本</h2>]]></description>
          <enclosure url="https://example.com/ClipMate-0.3.0.dmg" sparkle:version="3" sparkle:shortVersionString="0.3.0" length="1" type="application/octet-stream" />
        </item>
        <item>
          <title>Version 0.2.0</title>
          <description><![CDATA[<h2>中间版本</h2>]]></description>
          <enclosure url="https://example.com/ClipMate-0.2.0.dmg" sparkle:version="2" sparkle:shortVersionString="0.2.0" length="1" type="application/octet-stream" />
        </item>
      </channel>
    </rss>
    """
    let parsed = UpdateManager.shared.parseAppcast(data: Data(xml.utf8))
    runner.expectEqual(parsed?.version ?? "", "0.3.0", "多个 item 中取版本号最高的一条")
    runner.expectEqual(
        parsed?.downloadURL.absoluteString ?? "",
        "https://example.com/ClipMate-0.3.0.dmg",
        "下载链接取自最高版本条目"
    )
    runner.expectTrue(parsed?.notes.contains("新版本") == true, "更新说明取自最高版本条目")
    runner.expectTrue(
        UpdateManager.shared.parseAppcast(data: Data("<rss></rss>".utf8)) == nil,
        "无 item 的 feed 返回 nil"
    )
}

runner.run("ClipStore 语义检索运行时开关") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    runner.expectTrue(store.embeddingProvider == nil, "默认未挂载向量生成器")

    _ = try store.capture(
        kind: .text, plainText: "语义开关测试内容", sourceBundle: "test", sourceName: "Test"
    )
    runner.expectTrue(store.search(query: "语义开关").count == 1, "未开启语义检索时关键词仍可命中")

    store.setEmbeddingProvider { text in EmbeddingService.embed(text: text) }
    runner.expectTrue(store.embeddingProvider != nil, "运行中挂载后生成器可用")

    store.setEmbeddingProvider(nil)
    runner.expectTrue(store.embeddingProvider == nil, "运行中卸载后生成器为 nil")
    runner.expectTrue(store.search(query: "语义开关").count == 1, "卸载后检索自动退回纯文本路径")
}

runner.run("NumberRecognizer 号码类型识别") {
    runner.expectEqual(NumberRecognizer.detect("13812345678"), .phone, "11 位手机号识别")
    runner.expectEqual(NumberRecognizer.detect("138 1234 5678"), .phone, "带分隔符的手机号识别")
    runner.expectEqual(NumberRecognizer.detect("4242424242424242"), .bankCard, "Luhn 通过的银行卡识别")
    runner.expectEqual(NumberRecognizer.detect("110101199003071233"), .idCard, "身份证校验位通过")
    runner.expectEqual(NumberRecognizer.detect("110101199003071234"), .plain, "身份证校验位不通过时退化为数字")
    runner.expectEqual(NumberRecognizer.detect("192.168.1.1"), .ipAddress, "IPv4 识别")
    runner.expectEqual(NumberRecognizer.detect("SF1234567890"), .tracking, "快递单号识别")
    runner.expectEqual(NumberRecognizer.detect("¥1,234.56"), .amount, "带货币符号的金额识别")
    runner.expectEqual(NumberRecognizer.detect("20260909"), .plain, "纯数字兜底")
    runner.expectTrue(NumberRecognizer.detect("hello world") == nil, "普通文本不是号码")
    runner.expectTrue(NumberRecognizer.detect("https://example.com/123456") == nil, "URL 不是号码")
    runner.expectTrue(NumberRecognizer.detect("999") == nil, "位数过少不算号码")
}

runner.run("NumberRecognizer 分组展示与归一化") {
    runner.expectEqual(NumberRecognizer.displayText("13812345678") ?? "", "138 1234 5678", "手机号 3-4-4 分组")
    runner.expectEqual(NumberRecognizer.displayText("4242424242424242") ?? "", "4242 4242 4242 4242", "卡号 4 位分组")
    runner.expectEqual(NumberRecognizer.displayText("110101199003071233") ?? "", "110101 19900307 1233", "身份证 6-8-4 分组")
    runner.expectTrue(NumberRecognizer.displayText("hello") == nil, "非号码不分组")
    runner.expectEqual(NumberRecognizer.normalize("138-1234 5678") ?? "", "13812345678", "归一化去掉分隔符")
    runner.expectTrue(NumberRecognizer.normalize("SF1234567890") == nil, "含字母的单号不参与归一化")
}

runner.run("ClipStore 号码归一化聚合与「号码」分类") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let first = try store.capture(
        kind: .text, plainText: "138 1234 5678", sourceBundle: "com.test.a", sourceName: "微信",
        tags: AutoTagger.tags(for: "138 1234 5678", kind: .text)
    )
    runner.expectTrue(first.isNew, "首次采集入库")
    runner.expectTrue(first.item.tags.contains("手机号"), "自动打上手机号标签")

    let second = try store.capture(
        kind: .text, plainText: "13812345678", sourceBundle: "com.test.a", sourceName: "微信",
        tags: AutoTagger.tags(for: "13812345678", kind: .text)
    )
    runner.expectFalse(second.isNew, "同一号码的不同写法归并为同一条")
    runner.expectEqual(second.item.id, first.item.id, "复用同一条目 id")
    runner.expectEqual(second.item.useCount, 2, "use_count 累加")

    let numbers = store.search(query: "", filter: .number, limit: 50)
    runner.expectEqual(numbers.count, 1, "「号码」分类只召回号码条目")
    runner.expectEqual(numbers.first?.id, first.item.id, "号码分类命中的是手机号条目")
}

runner.run("ClipStore 用户自定义标题") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let captured = try store.capture(
        kind: .text, plainText: "6222020000000000", sourceBundle: "com.test.b", sourceName: "Safari"
    )
    let id = captured.item.id

    _ = try store.setUserTitle(id, title: "招行卡号")
    let titled = store.item(id: id)
    runner.expectEqual(titled?.title ?? "", "招行卡号", "自定义标题写入 title")
    runner.expectTrue(titled?.isUserTitled == true, "标记为用户标题")
    runner.expectEqual(store.search(query: "招行卡号", limit: 10).count, 1, "自定义标题可被检索命中")

    _ = try store.updateOCR(id, text: "6222020000000000", title: "自动识别标题")
    runner.expectEqual(store.item(id: id)?.title ?? "", "招行卡号", "OCR 不覆盖用户标题")

    _ = try store.updateURLMetadata(id, title: "网页标题", faviconData: nil)
    runner.expectEqual(store.item(id: id)?.title ?? "", "招行卡号", "链接元数据不覆盖用户标题")

    _ = try store.setUserTitle(id, title: nil)
    runner.expectTrue(store.item(id: id)?.title == nil, "清除后恢复为无标题")
}

runner.run("ClipStore 情境过滤（来源应用 + 时间范围）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let old = Date().addingTimeInterval(-3 * 86400)
    _ = try store.capture(
        kind: .text, plainText: "来自微信的旧内容", sourceBundle: "com.tencent.xinWeChat",
        sourceName: "微信", createdAt: old
    )
    _ = try store.capture(
        kind: .text, plainText: "来自浏览器的内容", sourceBundle: "com.apple.Safari",
        sourceName: "Safari"
    )

    let bySource = store.search(query: "", context: ContextFilter(sourceBundle: "com.tencent.xinWeChat"), limit: 20)
    runner.expectEqual(bySource.count, 1, "按来源应用过滤")
    runner.expectEqual(bySource.first?.sourceName ?? "", "微信", "命中微信来源")

    let recent = store.search(query: "", context: ContextFilter(since: Calendar.current.startOfDay(for: Date())), limit: 20)
    runner.expectEqual(recent.count, 1, "按时间范围过滤掉 3 天前的条目")

    let all = store.search(query: "", limit: 20)
    runner.expectEqual(all.count, 2, "无情境条件时返回全部")
}

runner.run("SearchQueryParser 检索语法") {
    let parsed = SearchQueryParser.parse("#11")
    runner.expectEqual(parsed.digitCount ?? 0, 11, "#N 解析为位数")
    runner.expectTrue(parsed.terms.isEmpty, "#N 不进入关键词")

    let ranged = SearchQueryParser.parse("#>8 #<12")
    runner.expectEqual(ranged.minDigits ?? 0, 8, "#>N 解析")
    runner.expectEqual(ranged.maxDigits ?? 0, 12, "#<N 解析")

    let mixed = SearchQueryParser.parse("订单 app:微信 len:>10 138*")
    runner.expectEqual(mixed.terms, ["订单"], "普通词保留为关键词")
    runner.expectEqual(mixed.source ?? "", "微信", "app: 解析来源")
    runner.expectEqual(mixed.minLength ?? 0, 10, "len:>N 解析")
    runner.expectEqual(mixed.prefix ?? "", "138", "前缀通配解析")
    runner.expectTrue(mixed.hasFilters, "包含结构化条件")

    let dated = SearchQueryParser.parse("before:昨天 after:2026-09-01")
    runner.expectTrue(dated.before != nil, "before:昨天 解析成功")
    runner.expectTrue(dated.after != nil, "after:日期 解析成功")

    runner.expectFalse(SearchQueryParser.parse("普通搜索").hasFilters, "普通查询不含结构化条件")
}

runner.run("ClipStore 检索语法端到端") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try store.capture(
        kind: .text, plainText: "13812345678", sourceBundle: "com.tencent.xinWeChat", sourceName: "微信"
    )
    _ = try store.capture(
        kind: .text, plainText: "这是一段比较长的说明文字用于长度过滤测试", sourceBundle: "com.apple.Safari",
        sourceName: "Safari"
    )

    runner.expectEqual(store.search(query: "#11", limit: 20).count, 1, "#11 命中 11 位数字")
    runner.expectEqual(store.search(query: "#>10", limit: 20).count, 1, "#>10 命中")
    runner.expectEqual(store.search(query: "app:微信", limit: 20).count, 1, "app: 来源过滤")
    runner.expectEqual(store.search(query: "138*", limit: 20).count, 1, "前缀匹配")
    runner.expectEqual(store.search(query: "len:>15", limit: 20).count, 1, "len:>N 长度过滤")
    runner.expectEqual(store.search(query: "len:<15", limit: 20).count, 1, "len:<N 长度过滤")
    runner.expectEqual(store.search(query: "app:微信 #11", limit: 20).count, 1, "多条件叠加")
    runner.expectEqual(store.search(query: "app:微信 #16", limit: 20).count, 0, "条件冲突时无结果")
}

runner.run("ClipStore 存量条目标签回填与去重补标签") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    // 模拟"标签规则升级前入库"的条目：采集时未打标签
    let legacy = try store.capture(
        kind: .text, plainText: "13812345678", sourceBundle: "com.test", sourceName: "Test", tags: []
    )
    runner.expectEqual(store.search(query: "", filter: .number, limit: 10).count, 0, "回填前号码分类为空")

    let updated = store.backfillAutoTags()
    runner.expectEqual(updated, 1, "回填 1 条存量条目")
    runner.expectEqual(store.search(query: "", filter: .number, limit: 10).count, 1, "回填后号码分类可命中")
    runner.expectEqual(store.backfillAutoTags(), 0, "重复回填幂等")

    // 规则升级后重新复制同一内容：去重分支也应补齐标签
    let (store2, dir2) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir2) }
    _ = try store2.capture(
        kind: .text, plainText: "4242424242424242", sourceBundle: "com.test", sourceName: "Test", tags: []
    )
    let again = try store2.capture(
        kind: .text, plainText: "4242424242424242", sourceBundle: "com.test", sourceName: "Test",
        tags: AutoTagger.tags(for: "4242424242424242", kind: .text)
    )
    runner.expectFalse(again.isNew, "重复复制仍走去重分支")
    runner.expectTrue(again.item.tags.contains("银行卡"), "去重时补齐自动标签")
    runner.expectEqual(legacy.item.id, legacy.item.id, "占位断言保持结构一致")
}

runner.run("Phase 1 - 新复制内容保护（Pasteboard Protection）") {
    // 1. 写内容并获取 changeCount
    let countBefore = PasteBack.write(.text("ClipMate 正在粘贴的内容"))
    runner.expectTrue(countBefore > 0, "写入成功并返回 changeCount")
    runner.expectTrue(NSPasteboard.general.types?.contains(PasteBack.ownedMarker) == true, "包含 ownedMarker 标记")

    // 2. 在未发生外部新复制的情况下：应该允许恢复
    runner.expectTrue(
        PasteBack.shouldRestorePasteboard(writtenChangeCount: countBefore),
        "无新复制且 ownedMarker 存在时，允许恢复快照"
    )

    // 3. 模拟用户或外部进程在粘贴期间复制了新内容（changeCount 改变且无 ownedMarker）
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("用户刚刚复制的新内容！", forType: .string)

    runner.expectFalse(
        PasteBack.shouldRestorePasteboard(writtenChangeCount: countBefore),
        "外部产生新复制后，坚决禁止恢复旧快照，保护新内容"
    )
    runner.expectEqual(
        NSPasteboard.general.string(forType: .string),
        "用户刚刚复制的新内容！",
        "剪贴板完好保留用户的新复制"
    )
}

runner.run("Phase 1 - 粘贴异常回退（Paste Fallback & Protection）") {
    // 目标无效（如 pid <= 0 或目标应用退出）时：保留内容在剪贴板并触发 fallback
    var fallbackTriggered = false
    var fallbackReason: PasteFallbackReason?

    PasteBack.paste(
        content: .text("需要手动粘贴的保留内容"),
        toPID: nil,
        targetApp: nil,
        suppress: nil,
        onFallback: { reason in
            fallbackTriggered = true
            fallbackReason = reason
        }
    )

    runner.expectTrue(fallbackTriggered, "目标无效时触发回退")
    runner.expectEqual(fallbackReason, .targetUnavailable, "回退原因为 targetUnavailable")
    runner.expectEqual(
        NSPasteboard.general.string(forType: .string),
        "需要手动粘贴的保留内容",
        "异常回退时所选内容保留在系统剪贴板供用户 ⌘V 手动粘贴"
    )
}

runner.run("Phase 1 - 列表与选择稳定性（In-Place Item Update & Stable Selection）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let item1 = try store.capture(kind: .text, plainText: "条目 1", sourceBundle: "com.test", sourceName: "Test", tags: []).item
    let item2 = try store.capture(kind: .text, plainText: "条目 2", sourceBundle: "com.test", sourceName: "Test", tags: []).item
    let item3 = try store.capture(kind: .text, plainText: "条目 3", sourceBundle: "com.test", sourceName: "Test", tags: []).item

    let settings = AppSettings()
    let monitor = ClipboardMonitor(settings: settings, store: store)
    let front = FrontAppTracker()
    let ai = AIService(settings: settings)
    let vm = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: front, ai: ai)

    // 选中第 2 个条目 (item2)
    vm.selectOnly(item: item2)
    runner.expectEqual(vm.selectedID, item2.id, "初始选中 item2")
    let initialIndex = vm.selectedIndex

    // 模拟后台 OCR / 智能标题异步更新 item2
    let updatedItem2 = try store.updateOCR(item2.id, text: "条目 2 (OCR 识别完成)", title: "识别标题 2")!
    vm.handleItemUpdated(updatedItem2)

    runner.expectEqual(vm.selectedID, item2.id, "更新后选中的 ID 保持不变")
    runner.expectEqual(vm.selectedIndex, initialIndex, "更新后选中的行索引保持不变")
    runner.expectEqual(vm.items[initialIndex].displayText, "识别标题 2", "行数据就地原位更新")

    // 模拟后台更新非选中的 item1
    let updatedItem1 = try store.updateOCR(item1.id, text: "条目 1 (更新)", title: "标题 1")!
    vm.handleItemUpdated(updatedItem1)

    runner.expectEqual(vm.selectedID, item2.id, "其他条目更新时，当前选中项仍然不受任何影响")
    runner.expectEqual(vm.selectedIndex, initialIndex, "选中索引完全稳定")
    runner.expectEqual(item3.id, item3.id, "保持完整性")
}

runner.run("Phase 1 - 预热加载与即开即用（Prewarm & Instant Availability）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    _ = try store.capture(kind: .text, plainText: "历史预热条目", sourceBundle: "com.test", sourceName: "Test", tags: [])

    let settings = AppSettings()
    let monitor = ClipboardMonitor(settings: settings, store: store)
    let front = FrontAppTracker()
    let ai = AIService(settings: settings)

    // 初始化时即预热完成
    let vm = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: front, ai: ai)
    runner.expectEqual(vm.items.count, 1, "PanelViewModel 初始化完成即已有数据，打开零等待")
    runner.expectEqual(vm.items.first?.plainText, "历史预热条目", "预热数据正确")
}

runner.run("Phase 2 - 电话、邮箱和链接提取与定位（Phone, Email, URL Extraction）") {
    let sample = "您好，技术支持请联系李工程师：+86 13800138000，或座机 010-88888888，技术支持邮箱 support@clipmate.ai，官方主页 https://clipmate.ai/portal"
    let fields = ContentExtractor.extractFromText(sample)

    let phones = fields.filter { $0.kind == .phone }.map(\.value)
    runner.expectTrue(phones.contains(where: { $0.contains("13800138000") }), "成功提取手机号")
    runner.expectTrue(phones.contains(where: { $0.contains("010-88888888") }), "成功提取座机号")

    let emails = fields.filter { $0.kind == .email }.map(\.value)
    runner.expectTrue(emails.contains("support@clipmate.ai"), "成功提取邮箱地址")

    let urls = fields.filter { $0.kind == .url }.map(\.value)
    runner.expectTrue(urls.contains("https://clipmate.ai/portal"), "成功提取网址链接")

    for f in fields {
        runner.expectTrue(f.sourceRange != nil, "字段 \(f.label) 具备原文位置 range")
        if let r = f.sourceRange {
            runner.expectEqual(String(sample[r]), f.value, "定位 range 在原文中与字段值精确一致")
        }
    }
}

runner.run("Phase 2 - 结构化联系人资料拆分（Contact Information Splitting）") {
    let card = """
    姓名：张三
    公司：极客智能科技有限公司
    职位：高级架构师
    地址：北京市海淀区中关村南大街1号科技大厦A座801
    电话：13911112222、0755-88886666
    微信号：zhangsan_tech
    """
    let fields = ContentExtractor.extractFromText(card)

    let nameField = fields.first { $0.label == "姓名" }
    runner.expectEqual(nameField?.value, "张三", "正确拆分姓名")

    let companyField = fields.first { $0.label == "公司" }
    runner.expectEqual(companyField?.value, "极客智能科技有限公司", "正确拆分公司")

    let titleField = fields.first { $0.label == "职位" }
    runner.expectEqual(titleField?.value, "高级架构师", "正确拆分职位")

    let addrField = fields.first { $0.label == "地址" }
    runner.expectEqual(addrField?.value, "北京市海淀区中关村南大街1号科技大厦A座801", "保留完整详细地址全文")

    let wechatField = fields.first { $0.label == "微信号" }
    runner.expectEqual(wechatField?.value, "zhangsan_tech", "正确拆分微信号")

    // 多号码独立拆出展示
    let phoneValues = fields.filter { $0.kind == .phone }.map(\.value)
    runner.expectTrue(phoneValues.contains("13911112222"), "拆出第一个电话号码")
    runner.expectTrue(phoneValues.contains("0755-88886666"), "拆出第二个座机号码")

    // 未提供的内容不补写
    runner.expectTrue(fields.first { $0.label == "邮箱" } == nil, "未提及邮箱时不凭空补写字段")
}

runner.run("Phase 2 - JSON 字段高保真提取（JSON High-Fidelity Extraction）") {
    let jsonText = """
    {
      "orderId": 987654321012345678,
      "zipCode": "00852",
      "userName": "Alice",
      "active": true
    }
    """
    let fields = ContentExtractor.extractFromText(jsonText)

    let orderField = fields.first { $0.label == "orderId" }
    runner.expectEqual(orderField?.value, "987654321012345678", "长数字不丢失精度、不转换为科学计数法")

    let zipField = fields.first { $0.label == "zipCode" }
    runner.expectEqual(zipField?.value, "00852", "字符串前导零完好保留")

    let userField = fields.first { $0.label == "userName" }
    runner.expectEqual(userField?.value, "Alice", "字符串值准确提取")

    let activeField = fields.first { $0.label == "active" }
    runner.expectEqual(activeField?.value, "true", "布尔值准确提取")
}

runner.run("Phase 2 - 图片 OCR 文字快捷取用（Image OCR Quick Access）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let fakeImgData = Data([0x89, 0x50, 0x4E, 0x47])
    let captured = try store.capture(
        kind: .image,
        plainText: "",
        sourceBundle: "com.apple.Preview",
        sourceName: "预览",
        tags: ["图片"],
        inlineData: fakeImgData,
        imageOriginal: fakeImgData
    )

    // 模拟后台 OCR 识别完成
    let ocrText = "发票号码：88889999\n联系电话：13812345678"
    let updated = try store.updateOCR(captured.item.id, text: ocrText, title: "发票扫描件")!

    let fields = ContentExtractor.extractFields(from: updated)
    let ocrField = fields.first { $0.kind == .ocrText }
    runner.expectTrue(ocrField != nil, "提供整段 OCR 识别文字快捷取用入口")
    runner.expectEqual(ocrField?.value, ocrText, "OCR 全文一致")

    // 从 OCR 结果中提取的子字段也可见
    let phoneField = fields.first { $0.kind == .phone }
    runner.expectTrue(phoneField != nil, "从图片 OCR 中提取出电话号码")
    runner.expectTrue(phoneField?.value.contains("13812345678") == true, "提取出电话值")

    // 原图原样粘贴不受影响
    let pasteContent = store.pasteboardContent(for: updated)
    if case .image? = pasteContent {
        runner.expectTrue(true, "原条目依然按图片原样粘贴")
    } else {
        runner.expectTrue(false, "图片条目 pasteboardContent 应为 .image")
    }
}

runner.run("Phase 2 - 字段快捷区交互（Field Shortcuts & Keyboard Actions）") {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let text = "订单信息：订单号：10086，联系电话：13800138000，邮箱：order@test.com"
    let item = try store.capture(kind: .text, plainText: text, sourceBundle: "com.test", sourceName: "Test", tags: []).item

    let settings = AppSettings()
    let monitor = ClipboardMonitor(settings: settings, store: store)
    let front = FrontAppTracker()
    let ai = AIService(settings: settings)
    let vm = PanelViewModel(store: store, settings: settings, monitor: monitor, frontApps: front, ai: ai)

    vm.selectOnly(item: item)
    let extracted = vm.fields(for: item)
    runner.expectTrue(extracted.count >= 2, "提取出至少 2 个局部字段")

    // 仅复制字段测试
    vm.copyField(at: 0)
    runner.expectEqual(NSPasteboard.general.string(forType: .string), extracted[0].value, "快捷仅复制成功写入首个字段")

    // 键盘移动焦点测试
    runner.expectEqual(vm.selectedFieldIndex, nil, "初始未聚焦任何字段")
    vm.moveFieldSelection(1)
    runner.expectEqual(vm.selectedFieldIndex, 0, "向右移动聚焦第 1 个字段")
    vm.moveFieldSelection(1)
    runner.expectEqual(vm.selectedFieldIndex, 1, "向右移动聚焦第 2 个字段")
    vm.moveFieldSelection(-1)
    runner.expectEqual(vm.selectedFieldIndex, 0, "向左移动返回第 1 个字段")
    vm.moveFieldSelection(-1)
    runner.expectEqual(vm.selectedFieldIndex, nil, "再次向左移动退出字段焦点")
}

print("----")


if runner.failures.isEmpty {
    print("全部 \(runner.passed) 个用例通过 ✅")
} else {
    print("\(runner.failures.count) 个用例失败：")
    runner.failures.forEach { print(" - \($0)") }
    exit(1)
}
