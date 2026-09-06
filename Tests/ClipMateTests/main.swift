import Foundation
import AppKit
import ClipMateCore

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

print("----")
if runner.failures.isEmpty {
    print("全部 \(runner.passed) 个用例通过 ✅")
} else {
    print("\(runner.failures.count) 个用例失败：")
    runner.failures.forEach { print(" - \($0)") }
    exit(1)
}
