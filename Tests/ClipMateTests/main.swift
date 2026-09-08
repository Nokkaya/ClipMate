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
    runner.expectEqual(L10n.tr("footer.paste", lang: .zhHans), "⏎ 粘贴", "中文粘贴")

    // 验证英文
    runner.expectEqual(L10n.filterTitle(.all, lang: .en), "All", "英文 All")
    runner.expectEqual(L10n.filterTitle(.snippet, lang: .en), "Snippets", "英文 Snippets")
    runner.expectEqual(L10n.tr("footer.paste", lang: .en), "⏎ Paste", "英文 Paste")

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

print("----")


if runner.failures.isEmpty {
    print("全部 \(runner.passed) 个用例通过 ✅")
} else {
    print("\(runner.failures.count) 个用例失败：")
    runner.failures.forEach { print(" - \($0)") }
    exit(1)
}
