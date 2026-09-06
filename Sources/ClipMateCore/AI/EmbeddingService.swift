import Foundation
import NaturalLanguage

/// 本地语义向量：基于系统 NLEmbedding 句向量（零网络、零成本）。
/// 系统不支持当前语言或资源未就绪时返回 nil，检索自动退回纯文本路径。
public enum EmbeddingService {
    /// 系统是否具备可用的句向量能力。
    public static var isAvailable: Bool {
        sentenceEmbedding() != nil
    }

    /// 当前主语言是否受支持（供 UI 提示）。
    public static var supportedLanguagesDescription: String {
        "英语及部分系统支持语言（系统按内容语言自动选择模型）"
    }

    private static let cacheLock = NSLock()
    private static var embeddingCache: [NLLanguage: NLEmbedding] = [:]

    /// 生成文本向量（Float32 编码）；不可用返回 nil。
    public static func embed(text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let input = String(trimmed.prefix(2000))

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(input)
        let language = recognizer.dominantLanguage ?? .english

        guard let embedding = sentenceEmbedding(for: language) ?? sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: input), !vector.isEmpty else { return nil }
        return ClipStore.data(from: vector)
    }

    private static func sentenceEmbedding() -> NLEmbedding? {
        sentenceEmbedding(for: .english)
    }

    private static func sentenceEmbedding(for language: NLLanguage) -> NLEmbedding? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = embeddingCache[language] { return cached }
        let embedding = NLEmbedding.sentenceEmbedding(for: language)
        if let embedding {
            embeddingCache[language] = embedding
        }
        return embedding
    }
}

/// 后台向量补算：启动时对新条目批量补算，采集后单条补算。低优先级串行队列，不阻塞采集与 UI。
final class EmbeddingBackfill {
    private let store: ClipStore
    private let queue = DispatchQueue(label: "clipmate.embedding", qos: .utility)
    private var pending = false

    init(store: ClipStore) {
        self.store = store
    }

    /// 启动全量补算（最多 2000 条/轮），完成后停止。
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
