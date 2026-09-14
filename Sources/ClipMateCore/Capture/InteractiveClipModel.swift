import Foundation

/// 控件变量类型
public enum VariableKind: Equatable, Sendable, Codable {
    case stepper(min: Double, max: Double, step: Double, unit: String, isInteger: Bool)
    case time(stepMinutes: Int)
    case duration(stepMinutes: Int, unit: String)
    case date(stepDays: Int)
}

/// 控件变量值
public enum VariableValue: Equatable, Sendable, Codable {
    case number(Double)
    case time(hour: Int, minute: Int)
    case durationMinutes(Int)
    case date(year: Int, month: Int, day: Int)

    public var displayText: String {
        switch self {
        case .number(let val):
            if floor(val) == val {
                return String(format: "%.0f", val)
            } else {
                return String(format: "%.1f", val).replacingOccurrences(of: ".0", with: "")
            }
        case .time(let h, let m):
            return String(format: "%02d:%02d", h, m)
        case .durationMinutes(let m):
            return "\(m)"
        case .date(let y, let m, let d):
            return String(format: "%04d-%02d-%02d", y, m, d)
        }
    }

    public var asNumber: Double {
        switch self {
        case .number(let n): return n
        case .durationMinutes(let m): return Double(m)
        case .time(let h, let m): return Double(h * 60 + m)
        case .date: return 0
        }
    }
}

/// 识别出的可交互变量
public struct InteractiveVariable: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var name: String
    public var kind: VariableKind
    public var baseValue: VariableValue
    public var currentValue: VariableValue
    public var isPrimary: Bool
    public var isLocked: Bool
    public var unit: String

    public init(id: String = UUID().uuidString, name: String, kind: VariableKind,
                baseValue: VariableValue, currentValue: VariableValue? = nil,
                isPrimary: Bool = true, isLocked: Bool = false, unit: String = "") {
        self.id = id
        self.name = name
        self.kind = kind
        self.baseValue = baseValue
        self.currentValue = currentValue ?? baseValue
        self.isPrimary = isPrimary
        self.isLocked = isLocked
        self.unit = unit
    }

    public var isModified: Bool {
        baseValue != currentValue
    }
}

/// 依赖联动计算规则
public enum BindingRule: Equatable, Sendable, Codable {
    /// 按比例缩放：目标值 = 基准值 * (当前主变量值 / 基准主变量值)
    case proportional(variableId: String, baseVariableValue: Double)
    /// 线性计算：总额 = 单价 * 数量 + 固定费
    case linearCalculation(unitPrice: Double, quantityVariableId: String, fixedCost: Double)
    /// 顺序时间偏移：起始时间 = 基准开始时间 + offsetMinutes, 结束 = 起始 + durationMinutes
    case timeOffset(offsetMinutes: Int, baseTimeVariableId: String, durationMinutes: Int)
    /// 相对日期偏移：目标日期 = 基准日期 + offsetDays
    case dateOffset(offsetDays: Int, baseDateVariableId: String)
}

/// 依赖于变量的相关项（如食材用量、环节时间、总额等）
public struct DependentBinding: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var name: String
    public var originalFragment: String
    public var baseNumber: Double
    public var currentNumber: Double
    public var lockedNumber: Double?
    public var originalLiteral: String
    public var currency: String?
    public var unit: String
    public var isFixed: Bool
    public var isFixedInText: Bool
    public var isLocked: Bool
    public var rule: BindingRule
    public var textLocations: [String] // 需替换的原文精准片段

    public init(id: String = UUID().uuidString, name: String, originalFragment: String,
                baseNumber: Double, currentNumber: Double? = nil, lockedNumber: Double? = nil,
                originalLiteral: String = "", currency: String? = nil, unit: String = "",
                isFixed: Bool = false, isFixedInText: Bool = false, isLocked: Bool = false,
                rule: BindingRule, textLocations: [String] = []) {
        self.id = id
        self.name = name
        self.originalFragment = originalFragment
        self.baseNumber = baseNumber
        self.currentNumber = currentNumber ?? baseNumber
        self.lockedNumber = lockedNumber
        self.originalLiteral = originalLiteral.isEmpty ? "\(baseNumber)" : originalLiteral
        self.currency = currency
        self.unit = unit
        self.isFixed = isFixed
        self.isFixedInText = isFixedInText
        self.isLocked = isLocked
        self.rule = rule
        self.textLocations = textLocations.isEmpty ? [originalFragment] : textLocations
    }
}

/// 约束与冲突级别
public enum ConflictSeverity: String, Equatable, Sendable, Codable {
    case info
    case warning
    case error
}

/// 约束冲突提示
public struct InteractiveConflict: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public var message: String
    public var severity: ConflictSeverity

    public init(id: String = UUID().uuidString, message: String, severity: ConflictSeverity = .warning) {
        self.id = id
        self.message = message
        self.severity = severity
    }
}

/// 缺失关键信息补齐提示
public struct MissingConstraintPrompt: Equatable, Sendable, Codable {
    public var prompt: String
    public var variableName: String
    public var suggestedValues: [Double]
    public var unit: String

    public init(prompt: String, variableName: String, suggestedValues: [Double] = [1, 2, 4], unit: String = "人") {
        self.prompt = prompt
        self.variableName = variableName
        self.suggestedValues = suggestedValues
        self.unit = unit
    }
}

/// 粘贴变焦信息层级（第六阶段）
public enum ZoomLevel: String, CaseIterable, Equatable, Sendable, Codable {
    case full = "full"             // 完整内容
    case keyPoints = "keyPoints"   // 核心要点
    case actionItems = "actions"   // 结论清单
    case oneLine = "oneLine"       // 一句话

    public var title: String {
        switch self {
        case .full: return "完整内容"
        case .keyPoints: return "核心要点"
        case .actionItems: return "结论清单"
        case .oneLine: return "一句话概括"
        }
    }

    public var icon: String {
        switch self {
        case .full: return "doc.plaintext"
        case .keyPoints: return "list.bullet"
        case .actionItems: return "checkmark.circle"
        case .oneLine: return "text.quote"
        }
    }
}

/// 识别出的通用模式类别
public enum DetectedPatternType: String, Equatable, Sendable, Codable {
    case recipe = "recipe"             // 菜谱与配方份数
    case schedule = "schedule"         // 会议与活动时间
    case itinerary = "itinerary"       // 差旅与日程日期
    case bomCalculation = "bom"        // 物料与报价清单
    case general = "general"           // 通用参数调节

    public var icon: String {
        switch self {
        case .recipe: return "fork.knife"
        case .schedule: return "clock"
        case .itinerary: return "calendar"
        case .bomCalculation: return "equal.square"
        case .general: return "slider.horizontal.3"
        }
    }

    public var title: String {
        switch self {
        case .recipe: return "份数比例"
        case .schedule: return "时间排期"
        case .itinerary: return "行程日程"
        case .bomCalculation: return "数量计算"
        case .general: return "内容参数"
        }
    }
}

/// 会话单步快照，用于撤销恢复
public struct InteractiveSessionSnapshot: Equatable, Sendable, Codable {
    public let variables: [InteractiveVariable]
    public let dependents: [DependentBinding]
    public let adjustedText: String
    public let currentZoom: ZoomLevel

    public init(variables: [InteractiveVariable], dependents: [DependentBinding], adjustedText: String, currentZoom: ZoomLevel) {
        self.variables = variables
        self.dependents = dependents
        self.adjustedText = adjustedText
        self.currentZoom = currentZoom
    }
}

/// 一条剪贴板内容的交互控件会话状态
public struct InteractiveSession: Equatable, Sendable, Codable {
    public let itemID: Int64
    public var originalText: String
    public var patternType: DetectedPatternType
    public var variables: [InteractiveVariable]
    public var dependents: [DependentBinding]
    public var missingConstraint: MissingConstraintPrompt?
    public var conflicts: [InteractiveConflict]
    public var adjustedText: String
    public var zoomLevels: [ZoomLevel: String]
    public var currentZoom: ZoomLevel
    public var showDiff: Bool
    public var isExpanded: Bool
    public var changeSummary: String
    public var contentHash: Int
    public var undoStack: [InteractiveSessionSnapshot]

    public init(itemID: Int64, originalText: String, patternType: DetectedPatternType,
                variables: [InteractiveVariable], dependents: [DependentBinding],
                missingConstraint: MissingConstraintPrompt? = nil,
                conflicts: [InteractiveConflict] = [],
                adjustedText: String? = nil,
                zoomLevels: [ZoomLevel: String] = [:],
                currentZoom: ZoomLevel = .full,
                showDiff: Bool = false,
                isExpanded: Bool = false,
                changeSummary: String = "",
                contentHash: Int? = nil,
                undoStack: [InteractiveSessionSnapshot] = []) {
        self.itemID = itemID
        self.originalText = originalText
        self.patternType = patternType
        self.variables = variables
        self.dependents = dependents
        self.missingConstraint = missingConstraint
        self.conflicts = conflicts
        self.adjustedText = adjustedText ?? originalText
        self.zoomLevels = zoomLevels
        self.currentZoom = currentZoom
        self.showDiff = showDiff
        self.isExpanded = isExpanded
        self.changeSummary = changeSummary
        self.contentHash = contentHash ?? originalText.hashValue
        self.undoStack = undoStack
    }

    public var primaryVariable: InteractiveVariable? {
        variables.first { $0.isPrimary } ?? variables.first
    }

    public var secondaryVariable: InteractiveVariable? {
        let primaries = variables.filter { $0.isPrimary }
        if primaries.count > 1 { return primaries[1] }
        let nonPrimaries = variables.filter { !$0.isPrimary }
        return nonPrimaries.first
    }

    public var isModified: Bool {
        variables.contains { $0.isModified } || dependents.contains { $0.isLocked }
    }

    /// 获取当前变焦层级对应的最终文本
    public var effectiveText: String {
        if currentZoom == .full {
            return adjustedText
        }
        return zoomLevels[currentZoom] ?? adjustedText
    }

    public mutating func pushSnapshot() {
        let snapshot = InteractiveSessionSnapshot(
            variables: variables,
            dependents: dependents,
            adjustedText: adjustedText,
            currentZoom: currentZoom
        )
        undoStack.append(snapshot)
        if undoStack.count > 20 {
            undoStack.removeFirst()
        }
    }

    public mutating func undo() -> Bool {
        guard let prev = undoStack.popLast() else { return false }
        self.variables = prev.variables
        self.dependents = prev.dependents
        self.adjustedText = prev.adjustedText
        self.currentZoom = prev.currentZoom
        return true
    }
}
