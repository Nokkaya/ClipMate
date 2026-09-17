import Foundation
import CommonCrypto

/// 草稿预期用途
public enum DraftPurpose: Codable, Equatable, Sendable {
    case reply              // 给客户/同事的回复
    case summary            // 会议/资料纪要
    case proposal           // 方案与说明
    case todo               // 待办与执行清单
    case general            // 中性整理草稿
    case custom(String)     // 用户自定义用途

    public var title: String {
        switch self {
        case .reply: return "回复"
        case .summary: return "纪要"
        case .proposal: return "方案"
        case .todo: return "待办"
        case .general: return "整理"
        case .custom(let name): return name
        }
    }

    public var icon: String {
        switch self {
        case .reply: return "bubble.left.and.bubble.right"
        case .summary: return "doc.text"
        case .proposal: return "lightbulb"
        case .todo: return "checklist"
        case .general: return "square.and.pencil"
        case .custom: return "tag"
        }
    }
}

/// 草稿生命周期状态
public enum DraftStatus: String, Codable, Equatable, Sendable {
    case candidate = "candidate"        // 初始候选草稿（未编辑、未确认采用，可随新材料刷新）
    case confirmed = "confirmed"        // 已采用稳定版本（受保护，新材料只形成待采用修改）
    case editing = "editing"            // 用户正在手动编辑
    case paused = "paused"              // 暂停跟随复制
    case completed = "completed"        // 事项已结束/归档
}

/// 材料在草稿中的归属状态
public enum DraftSourceStatus: String, Codable, Equatable, Sendable {
    case included = "included"          // 已纳入草稿
    case excluded = "excluded"          // 用户已移出或已删除
    case suggested = "suggested"        // 系统推测关联（待确认）
}

/// 新材料与草稿的关系判定
public enum DraftAttributionRelation: String, Codable, Equatable, Sendable {
    case addition = "addition"          // 补充新事实或要求
    case revision = "revision"          // 明确修订/替换既有要求
    case conflict = "conflict"          // 存在事实或条件冲突
    case irrelevant = "irrelevant"      // 无关材料
}

/// 草稿引用的来源条目快照
public struct DraftSource: Identifiable, Codable, Equatable, Sendable {
    public let id: Int64                // ClipItem.id
    public var versionHash: String      // 跨进程稳定的 SHA-256 内容指纹 (LLM-C05)
    public var sourceName: String       // 来源应用名称或文件名称
    public var sourceBundle: String     // 来源应用 bundleIdentifier
    public var content: String          // 完整原文内容
    public var timestamp: Date          // 复制或引入时间
    public var status: DraftSourceStatus // 归属状态

    public init(id: Int64, versionHash: String = "", sourceName: String = "",
                sourceBundle: String = "", content: String, timestamp: Date = Date(),
                status: DraftSourceStatus = .included) {
        self.id = id
        self.versionHash = versionHash.isEmpty ? Self.computeStableHash(content) : versionHash
        self.sourceName = sourceName
        self.sourceBundle = sourceBundle
        self.content = content
        self.timestamp = timestamp
        self.status = status
    }

    /// 计算跨进程跨生命周期确定性的稳定 SHA-256 指纹
    public static func computeStableHash(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "\(text.count)" }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// 修改操作类型
public enum DraftChangeAction: String, Codable, Equatable, Sendable {
    case replace = "replace"
    case insert = "insert"
    case delete = "delete"
}

/// 局部文本修改项
public struct DraftTextChange: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var originalSnippet: String  // 需替换的旧文本片段（为空表示新增/插入）
    public var proposedSnippet: String  // 建议的新文本片段（为空表示删除）
    public var reason: String           // 修改原因
    public var isAdopted: Bool          // 是否已局部采用
    public var action: DraftChangeAction // 显式操作动作 (LLM-R01)
    public var contextHint: String      // 上下文消歧提示（周围句子或段落，防止误伤重名片段 LLM-R03）

    public init(id: String = UUID().uuidString,
                originalSnippet: String,
                proposedSnippet: String,
                reason: String = "",
                isAdopted: Bool = false,
                action: DraftChangeAction? = nil,
                contextHint: String = "") {
        self.id = id
        self.originalSnippet = originalSnippet
        self.proposedSnippet = proposedSnippet
        self.reason = reason
        self.isAdopted = isAdopted
        if let act = action {
            self.action = act
        } else if originalSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.action = .insert
        } else if proposedSnippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.action = .delete
        } else {
            self.action = .replace
        }
        self.contextHint = contextHint
    }
}

/// 关联修改建议（成组展示与原子采用）
public struct DraftRevisionProposal: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var groupId: String          // 关联修改组 ID（关联修改整体作为一个单元）
    public var title: String            // 简短说明（例如“取消上线时间保证，同步正文与结尾”）
    public var reason: String           // 修改依据
    public var targetVersion: Int       // 针对的草稿基准版本 (LLM-R02)
    public var changes: [DraftTextChange] // 包含的受影响片段修改列表
    public var relatedSourceIDs: [Int64]// 关联的来源材料 ID
    public var isAdopted: Bool          // 是否已整体采用
    public var isRejected: Bool         // 是否已整体拒绝

    public init(id: String = UUID().uuidString,
                groupId: String = UUID().uuidString,
                title: String,
                reason: String = "",
                targetVersion: Int,
                changes: [DraftTextChange],
                relatedSourceIDs: [Int64] = [],
                isAdopted: Bool = false,
                isRejected: Bool = false) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.reason = reason
        self.targetVersion = targetVersion
        self.changes = changes
        self.relatedSourceIDs = relatedSourceIDs
        self.isAdopted = isAdopted
        self.isRejected = isRejected
    }
}

/// 意图与目标控件类型
public enum DraftControlType: Codable, Equatable, Sendable {
    case stepper(min: Double, max: Double, step: Double, unit: String, isInteger: Bool)
    case date(stepDays: Int)
    case time(stepMinutes: Int)
    case options(choices: [String])
    case constraintToggle(description: String)
    case preferenceSlider(leftLabel: String, rightLabel: String)
}

/// 草稿目标与约束控件
public struct DraftGoalControl: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String             // 控件名称，例如“交付偏好”、“人数”、“离线支持”
    public var type: DraftControlType   // 控件交互形态
    public var currentValue: String     // 当前值（格式化字符串）
    public var isHardConstraint: Bool   // 是否为硬约束（硬约束不可被模型静默放宽 LLM-R05）
    public var isLocked: Bool           // 是否被用户锁定
    public var unit: String             // 计量单位
    public var relatedTextLocations: [String] // 关联的草稿文本片段

    public init(id: String = UUID().uuidString,
                name: String,
                type: DraftControlType,
                currentValue: String,
                isHardConstraint: Bool = false,
                isLocked: Bool = false,
                unit: String = "",
                relatedTextLocations: [String] = []) {
        self.id = id
        self.name = name
        self.type = type
        self.currentValue = currentValue
        self.isHardConstraint = isHardConstraint
        self.isLocked = isLocked
        self.unit = unit
        self.relatedTextLocations = relatedTextLocations
    }
}

/// 缺失关键信息或未决问题
public struct DraftUnresolvedItem: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var question: String         // 提问内容（最少打扰原则：关键缺口优先问一个问题）
    public var suggestedValues: [String]// 可选的候选回复
    public var isCritical: Bool         // 是否严重影响可用性
    public var resolvedValue: String?   // 用户回答或解决的值

    public init(id: String = UUID().uuidString,
                question: String,
                suggestedValues: [String] = [],
                isCritical: Bool = true,
                resolvedValue: String? = nil) {
        self.id = id
        self.question = question
        self.suggestedValues = suggestedValues
        self.isCritical = isCritical
        self.resolvedValue = resolvedValue
    }
}

/// 草稿历史快照（用于撤销与恢复完整状态 LLM-R10）
public struct DraftSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let confirmedText: String
    public let candidateText: String?
    public let userEditedText: String?
    public let changeSummary: String
    public let controls: [DraftGoalControl]
    public let pendingProposals: [DraftRevisionProposal]
    public let zoomLevels: [ZoomLevel: String]
    public let status: DraftStatus
    public let timestamp: Date

    public init(version: Int,
                confirmedText: String,
                candidateText: String?,
                userEditedText: String?,
                changeSummary: String,
                controls: [DraftGoalControl],
                pendingProposals: [DraftRevisionProposal],
                zoomLevels: [ZoomLevel: String],
                status: DraftStatus,
                timestamp: Date = Date()) {
        self.version = version
        self.confirmedText = confirmedText
        self.candidateText = candidateText
        self.userEditedText = userEditedText
        self.changeSummary = changeSummary
        self.controls = controls
        self.pendingProposals = pendingProposals
        self.zoomLevels = zoomLevels
        self.status = status
        self.timestamp = timestamp
    }
}

/// 工作草稿实体
public struct WorkingDraft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String                    // 草稿标题（可自动生成与人工修改）
    public var purpose: DraftPurpose            // 输出用途
    public var status: DraftStatus              // 状态
    public var followCopy: Bool                 // 跟随复制更新开关（默认由用户明确开启 LLM-R13）
    public var sources: [DraftSource]           // 来源材料列表
    public var confirmedText: String            // 用户已采用/已确认草稿
    public var candidateText: String?           // 初次生成或正在生成的候选草稿
    public var userEditedText: String?          // 用户手动编辑覆盖的草稿
    public var changeSummary: String            // 最新变化摘要（例如“新增 1 条限制，影响 2 段内容”）
    public var pendingProposals: [DraftRevisionProposal] // 待采用关联修改建议
    public var unresolvedItems: [DraftUnresolvedItem]     // 未决事项与必要问题
    public var controls: [DraftGoalControl]     // 目标与约束控件
    public var zoomLevels: [ZoomLevel: String]  // 信息层级输出
    public var currentZoom: ZoomLevel           // 当前选中的信息层级
    public var version: Int                     // 草稿自增版本号
    public var undoStack: [DraftSnapshot]       // 撤销栈
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(),
                title: String = "未命名草稿",
                purpose: DraftPurpose = .general,
                status: DraftStatus = .candidate,
                followCopy: Bool = false,        // LLM-R13: 新建草稿默认不跟随复制，需用户明确开启
                sources: [DraftSource] = [],
                confirmedText: String = "",
                candidateText: String? = nil,
                userEditedText: String? = nil,
                changeSummary: String = "",
                pendingProposals: [DraftRevisionProposal] = [],
                unresolvedItems: [DraftUnresolvedItem] = [],
                controls: [DraftGoalControl] = [],
                zoomLevels: [ZoomLevel: String] = [:],
                currentZoom: ZoomLevel = .full,
                version: Int = 1,
                undoStack: [DraftSnapshot] = [],
                createdAt: Date = Date(),
                updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.purpose = purpose
        self.status = status
        self.followCopy = followCopy
        self.sources = sources
        self.confirmedText = confirmedText
        self.candidateText = candidateText
        self.userEditedText = userEditedText
        self.changeSummary = changeSummary
        self.pendingProposals = pendingProposals
        self.unresolvedItems = unresolvedItems
        self.controls = controls
        self.zoomLevels = zoomLevels
        self.currentZoom = currentZoom
        self.version = version
        self.undoStack = undoStack
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 完整全量正文（不受变焦影响，作为一切编辑、修改建议和快照的基准 LLM-R08）
    public var fullDraftText: String {
        if let edited = userEditedText, !edited.isEmpty {
            return edited
        }
        if !confirmedText.isEmpty {
            return confirmedText
        }
        return candidateText ?? ""
    }

    /// 当前有效生效文本（优先级：变焦层级 > 用户编辑 > 已确认草稿 > 候选草稿）
    public var effectiveText: String {
        if currentZoom != .full, let zoomed = zoomLevels[currentZoom], !zoomed.isEmpty {
            return zoomed
        }
        return fullDraftText
    }

    /// 是否仍为未被用户锁定或编辑的初始候选草稿
    public var isCandidate: Bool {
        status == .candidate && userEditedText == nil && confirmedText.isEmpty
    }

    /// 活跃有效纳入的材料数量
    public var activeSourcesCount: Int {
        sources.filter { $0.status == .included }.count
    }

    /// 是否有未处理的修改建议
    public var hasPendingProposals: Bool {
        !pendingProposals.filter { !$0.isAdopted && !$0.isRejected }.isEmpty
    }

    /// 确认采用候选草稿
    public mutating func confirmAdoption() {
        pushSnapshot()
        if confirmedText.isEmpty {
            confirmedText = userEditedText ?? (candidateText ?? "")
        }
        candidateText = nil
        status = .confirmed
        changeSummary = "已确认采用草稿"
        version += 1
        updatedAt = Date()
    }

    /// 压入撤销快照（保存全部关联状态 LLM-R10）
    public mutating func pushSnapshot() {
        let snapshot = DraftSnapshot(
            version: version,
            confirmedText: confirmedText,
            candidateText: candidateText,
            userEditedText: userEditedText,
            changeSummary: changeSummary,
            controls: controls,
            pendingProposals: pendingProposals,
            zoomLevels: zoomLevels,
            status: status,
            timestamp: Date()
        )
        undoStack.append(snapshot)
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }

    /// 撤销上一步（完整恢复文字、建议状态、控件约束与层级 LLM-R10）
    public mutating func undo() -> Bool {
        guard let prev = undoStack.popLast() else { return false }
        self.confirmedText = prev.confirmedText
        self.candidateText = prev.candidateText
        self.userEditedText = prev.userEditedText
        self.changeSummary = "已撤销至版本 v\(prev.version)"
        self.controls = prev.controls
        self.pendingProposals = prev.pendingProposals
        self.zoomLevels = prev.zoomLevels
        self.status = prev.status
        self.version = prev.version
        self.updatedAt = Date()
        return true
    }
}
