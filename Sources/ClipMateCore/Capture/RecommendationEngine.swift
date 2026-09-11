import Foundation
import AppKit

/// 推荐原因类型
public enum RecommendationReason: String, Codable, Equatable, Sendable {
    case appFrequent = "app_frequent"
    case sameMaterial = "same_material"
    case sequenceContinuation = "sequence"

    public var systemImage: String {
        switch self {
        case .appFrequent: return "app.badge"
        case .sameMaterial: return "doc.on.doc"
        case .sequenceContinuation: return "arrow.right.circle"
        }
    }
}

/// 推荐条目模型
public struct RecommendedItem: Identifiable, Equatable, Sendable {
    public var id: Int64 { item.id }
    public let item: ClipItem
    public let reason: RecommendationReason
    public let reasonText: String
    public let unusedFields: [ExtractedField]

    public init(item: ClipItem, reason: RecommendationReason, reasonText: String, unusedFields: [ExtractedField] = []) {
        self.item = item
        self.reason = reason
        self.reasonText = reasonText
        self.unusedFields = unusedFields
    }
}

/// 用户使用历史打点记录
public struct UsageRecord: Codable, Equatable, Sendable {
    public let itemID: Int64
    public let appBundle: String?
    public let fieldKind: String?
    public let fieldID: String?
    public let timestamp: Date

    public init(itemID: Int64, appBundle: String?, fieldKind: String? = nil, fieldID: String? = nil, timestamp: Date = Date()) {
        self.itemID = itemID
        self.appBundle = appBundle
        self.fieldKind = fieldKind
        self.fieldID = fieldID
        self.timestamp = timestamp
    }
}

/// 连续使用转移概率与频次记录
public struct SequenceTransition: Codable, Equatable, Sendable {
    public let fromItemID: Int64
    public let toItemID: Int64
    public var count: Int
    public var lastTimestamp: Date

    public init(fromItemID: Int64, toItemID: Int64, count: Int = 1, lastTimestamp: Date = Date()) {
        self.fromItemID = fromItemID
        self.toItemID = toItemID
        self.count = count
        self.lastTimestamp = lastTimestamp
    }
}

/// 推荐学习本地轻量数据存储（100% 离线、不上传任何数据）
public struct RecommendationLearningStore: Codable, Equatable, Sendable {
    public var usageRecords: [UsageRecord] = []
    public var sequenceTransitions: [SequenceTransition] = []
    public var ignoredItemIDs: Set<Int64> = []
    public var actionUsageCounts: [String: Int] = [:]
    public var mutedActionKinds: Set<String> = []
    public var lastUsedItemID: Int64? = nil
    public var lastUsedTimestamp: Date? = nil

    public init() {}

    /// 记录一次条目或局部字段的使用
    public mutating func recordUsage(itemID: Int64, appBundle: String?, field: ExtractedField? = nil, action: ContentActionKind? = nil) {
        let now = Date()

        // 连续使用关联：若 3 分钟（180秒）内依次使用了两个不同条目，建立转移关联
        if let lastID = lastUsedItemID, lastID != itemID, let lastTime = lastUsedTimestamp {
            if now.timeIntervalSince(lastTime) < 180 {
                if let idx = sequenceTransitions.firstIndex(where: { $0.fromItemID == lastID && $0.toItemID == itemID }) {
                    sequenceTransitions[idx].count += 1
                    sequenceTransitions[idx].lastTimestamp = now
                } else {
                    sequenceTransitions.append(SequenceTransition(fromItemID: lastID, toItemID: itemID, count: 1, lastTimestamp: now))
                }
            }
        }

        let record = UsageRecord(
            itemID: itemID,
            appBundle: appBundle,
            fieldKind: field?.kind.rawValue,
            fieldID: field?.id,
            timestamp: now
        )
        usageRecords.append(record)

        // 仅保留最近 600 条记录，保证极速与紧凑存储
        if usageRecords.count > 600 {
            usageRecords.removeFirst(usageRecords.count - 600)
        }

        if let action {
            actionUsageCounts[action.rawValue, default: 0] += 1
        }

        lastUsedItemID = itemID
        lastUsedTimestamp = now
    }

    /// 忽略某条推荐
    public mutating func ignoreItem(id: Int64) {
        ignoredItemIDs.insert(id)
    }

    /// 减少/屏蔽某类动作推荐
    public mutating func muteAction(_ kind: ContentActionKind) {
        mutedActionKinds.insert(kind.rawValue)
    }

    /// 恢复某类动作推荐
    public mutating func unmuteAction(_ kind: ContentActionKind) {
        mutedActionKinds.remove(kind.rawValue)
    }

    /// 清空所有学习记录与偏好
    public mutating func clear() {
        usageRecords.removeAll()
        sequenceTransitions.removeAll()
        ignoredItemIDs.removeAll()
        actionUsageCounts.removeAll()
        mutedActionKinds.removeAll()
        lastUsedItemID = nil
        lastUsedTimestamp = nil
    }
}

/// 智能情境推荐引擎
public enum RecommendationEngine {

    /// 计算推荐候选（最多返回 limit 条，默认 3 条）
    public static func computeRecommendations(
        items: [ClipItem],
        currentAppBundle: String?,
        learningStore: RecommendationLearningStore,
        limit: Int = 3,
        appLanguage: AppLanguage = .system
    ) -> [RecommendedItem] {
        guard limit > 0, !items.isEmpty else { return [] }

        // 构建条目映射与可推荐条目池（排除已忽略条目）
        let availableItems = items.filter { !learningStore.ignoredItemIDs.contains($0.id) }
        guard !availableItems.isEmpty else { return [] }
        let itemMap = Dictionary(uniqueKeysWithValues: availableItems.map { ($0.id, $0) })

        var candidates: [RecommendedItem] = []
        var seenIDs = Set<Int64>()
        let now = Date()

        let isZh = (appLanguage == .zhHans || (appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true))

        // 策略 1：同份资料继续取用（用户在 15 分钟内取用了某个资料的部分字段，优先推荐剩余未取用字段）
        let fifteenMinsAgo = now.addingTimeInterval(-900)
        let recentFieldRecords = learningStore.usageRecords.filter {
            $0.timestamp >= fifteenMinsAgo && ($0.fieldID != nil || $0.fieldKind != nil)
        }

        if let lastFieldRecord = recentFieldRecords.last,
           let baseItem = itemMap[lastFieldRecord.itemID] {
            let allFields = ContentExtractor.extractFields(from: baseItem)
            let usedFieldIDs = Set(recentFieldRecords.filter { $0.itemID == baseItem.id }.compactMap(\.fieldID))
            let unused: [ExtractedField] = {
                if !usedFieldIDs.isEmpty {
                    return allFields.filter { !usedFieldIDs.contains($0.id) }
                } else {
                    let usedKinds = Set(recentFieldRecords.filter { $0.itemID == baseItem.id }.compactMap(\.fieldKind))
                    return allFields.filter { !usedKinds.contains($0.kind.rawValue) }
                }
            }()

            if !unused.isEmpty {
                let reasonText = isZh ? "同份资料" : "Same Source"
                candidates.append(RecommendedItem(
                    item: baseItem,
                    reason: .sameMaterial,
                    reasonText: reasonText,
                    unusedFields: unused
                ))
                seenIDs.insert(baseItem.id)
            }
        }

        // 策略 2：连续使用推荐（用户刚使用了 A，且历史上多次紧接着使用 B）
        if let lastID = learningStore.lastUsedItemID,
           let lastTime = learningStore.lastUsedTimestamp,
           now.timeIntervalSince(lastTime) < 180 {
            let matchingTransitions = learningStore.sequenceTransitions
                .filter { $0.fromItemID == lastID && $0.count >= 2 }
                .sorted { $0.count > $1.count }

            for trans in matchingTransitions {
                if candidates.count >= limit { break }
                if !seenIDs.contains(trans.toItemID), let nextItem = itemMap[trans.toItemID] {
                    let reasonText = isZh ? "连续使用" : "Frequently Used Next"
                    candidates.append(RecommendedItem(
                        item: nextItem,
                        reason: .sequenceContinuation,
                        reasonText: reasonText
                    ))
                    seenIDs.insert(nextItem.id)
                }
            }
        }

        // 策略 3：此应用常用推荐（根据当前前台应用 Bundle ID 匹配历史偏好）
        if let app = currentAppBundle, !app.isEmpty, candidates.count < limit {
            // 统计该应用下的使用加权频次（近期使用权重更高）
            var appScores: [Int64: Double] = [:]
            for record in learningStore.usageRecords where record.appBundle == app {
                let ageHours = max(0, now.timeIntervalSince(record.timestamp) / 3600.0)
                let weight = 1.0 / (1.0 + ageHours * 0.1) // 渐进时间衰减
                appScores[record.itemID, default: 0] += weight
            }

            let sortedByApp = appScores.sorted { $0.value > $1.value }
            for (id, score) in sortedByApp where score >= 1.2 {
                if candidates.count >= limit { break }
                if !seenIDs.contains(id), let appItem = itemMap[id] {
                    let reasonText = isZh ? "此应用常用" : "Common in this App"
                    candidates.append(RecommendedItem(
                        item: appItem,
                        reason: .appFrequent,
                        reasonText: reasonText
                    ))
                    seenIDs.insert(appItem.id)
                }
            }
        }

        return Array(candidates.prefix(limit))
    }
}
