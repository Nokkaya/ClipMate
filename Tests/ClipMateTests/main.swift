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

print("----")
if runner.failures.isEmpty {
    print("全部 \(runner.passed) 个用例通过 ✅")
} else {
    print("\(runner.failures.count) 个用例失败：")
    runner.failures.forEach { print(" - \($0)") }
    exit(1)
}
