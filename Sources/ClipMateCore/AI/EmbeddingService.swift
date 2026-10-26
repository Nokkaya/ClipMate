import Foundation
import NaturalLanguage

/// 本地语义向量：基于系统 NLEmbedding 句向量（零网络、零成本）。
/// 系统不支持当前语言或资源未就绪时返回 nil，检索自动退回纯文本路径。
public enum EmbeddingService {
    /// 系统是否具备可用的句向量能力。
    public static var isAvailable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sentenceEmbedding(for: .english) != nil
    }

    /// 当前主语言是否受支持（供 UI 提示）。
    public static var supportedLanguagesDescription: String {
        "英语及部分系统支持语言（系统按内容语言自动选择模型）"
    }

    /// NLEmbedding 与底层的 CoreNLP 并非线程安全，并发调用 vector(for:) 会触发内部内存争抢与 malloc 崩溃。
    /// 必须使用互斥锁严格串行化推理调用与模型缓存。
    private static let lock = NSLock()
    private static var embeddingCache: [NLLanguage: NLEmbedding?] = [:]

    /// 生成文本向量（Float32 编码）；不可用返回 nil。
    public static func embed(text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let input = String(trimmed.prefix(2000))

        lock.lock()
        defer { lock.unlock() }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(input)
        let language = recognizer.dominantLanguage ?? .english

        guard let embedding = resolveEmbedding(for: language),
              let vector = embedding.vector(for: input), !vector.isEmpty else { return nil }
        return ClipStore.data(from: vector)
    }

    /// 解析指定语言对应的句向量模型（含缓存与安全回退逻辑）。
    /// 调用方必须持有 lock。
    private static func resolveEmbedding(for language: NLLanguage) -> NLEmbedding? {
        if let cached = embeddingCache[language] {
            return cached
        }
        var embedding = sentenceEmbedding(for: language)
        // 繁体中文回退尝试简体中文模型
        if embedding == nil && language == .traditionalChinese {
            embedding = sentenceEmbedding(for: .simplifiedChinese)
        }
        // 未决或判定为英语时使用英语模型
        if embedding == nil && (language == .undetermined || language == .english) {
            embedding = sentenceEmbedding(for: .english)
        }
        embeddingCache[language] = embedding
        return embedding
    }

    /// 底层加载句向量模型并缓存（含未就绪或不支持的 nil 结果）；必须在持有 lock 时调用。
    private static func sentenceEmbedding(for language: NLLanguage) -> NLEmbedding? {
        if let cached = embeddingCache[language] { return cached }
        let embedding = NLEmbedding.sentenceEmbedding(for: language)
        embeddingCache[language] = embedding
        return embedding
    }
}

/// 后台向量补算：启动时对新条目批量补算，采集后单条补算。低优先级串行队列，不阻塞采集与 UI。
/// 注意：store 必须使用独立数据库连接（WAL 多连接），
/// 否则补算写入会与主线程查询争抢同一连接，导致筛选/搜索卡顿。
final class EmbeddingBackfill {
    private let store: ClipStore
    private let queue = DispatchQueue(label: "clipmate.embedding", qos: .utility)
    private var pending = false
    private let onFinished: (() -> Void)?

    init(store: ClipStore, onFinished: (() -> Void)? = nil) {
        self.store = store
        self.onFinished = onFinished
    }

    /// 启动全量补算（最多 2000 条/轮），分批让渡，完成后回调刷新主实例缓存。
    func backfillAll() {
        queue.async { [weak self] in
            guard let self else { return }
            var budget = 2000
            while budget > 0 {
                let batch = self.store.itemsNeedingEmbedding(limit: 50)
                guard !batch.isEmpty else { break }
                for entry in batch {
                    if let data = EmbeddingService.embed(text: entry.text) {
                        self.store.setEmbedding(entry.id, data)
                    } else {
                        // 不可用/不支持：写空 blob 防止反复重试
                        self.store.setEmbedding(entry.id, Data([0]))
                    }
                    budget -= 1
                }
                Thread.sleep(forTimeInterval: 0.15)
            }
            if let onFinished = self.onFinished {
                DispatchQueue.main.async { onFinished() }
            }
        }
    }

    /// 采集后单条补算（合并短时间内的多次触发）。
    func embedIfNeeded(id: Int64, text: String) {
        queue.async { [weak self] in
            guard let self, !self.pending else { return }
            self.pending = true
            self.queue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                self.pending = false
                if let data = EmbeddingService.embed(text: text) {
                    self.store.setEmbedding(id, data)
                }
            }
        }
    }
}
