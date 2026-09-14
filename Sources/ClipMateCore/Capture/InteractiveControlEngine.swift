import Foundation

/// 内容控件识别与联动引擎
/// 零网络依赖、纯本地高性能算法，负责识别文本中的变量与关系，并执行精准的依赖联动更新。
public enum InteractiveControlEngine {

    // MARK: - 主入口

    /// 尝试分析文本并构建 InteractiveSession。若无可靠的可调关系则返回 nil。
    public static func analyze(text: String, itemID: Int64 = 0) -> InteractiveSession? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 输入保护：超出 64KB 的极大文本不进行深度语法树解析
        let scanText = trimmed.count > 65536 ? String(trimmed.prefix(65536)) : trimmed

        // 1. 尝试识别菜谱与配方（比例缩放）
        if let session = tryParseRecipe(text: scanText, itemID: itemID) {
            return session
        }

        // 2. 尝试识别物料与线性计算（单价 * 数量 + 运费）
        if let session = tryParseBOM(text: scanText, itemID: itemID) {
            return session
        }

        // 3. 尝试识别活动与会议日程（时间顺序顺延）
        if let session = tryParseSchedule(text: scanText, itemID: itemID) {
            return session
        }

        // 4. 尝试识别差旅行程与日期偏移
        if let session = tryParseItinerary(text: scanText, itemID: itemID) {
            return session
        }

        return nil
    }

    // MARK: - 1. 菜谱与配方比例识别

    private static func tryParseRecipe(text: String, itemID: Int64) -> InteractiveSession? {
        // 匹配主份数/人数：例如 "4人份", "四人份", "适合4人", "4 servings", "2-3人份"
        var baseServings: Double? = nil

        let servingsPatterns = [
            #"(?i)(?:适合|配方|分量|份量)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:人份|份|servings?|人量|人)"#,
            #"(?i)([一二两三四五六七八九十]+)\s*(?:人份|份|人量|人)"#
        ]

        for pat in servingsPatterns {
            if let regex = try? NSRegularExpression(pattern: pat),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let matchedStr = String(text[range])
                if let num = Double(matchedStr) {
                    baseServings = num
                    break
                } else if let num = parseChineseNumber(matchedStr) {
                    baseServings = num
                    break
                }
            }
        }

        // 识别食材行：匹配 "[食材名] [数值] [单位]"
        // 过滤不可缩放项：温度 (180°C)、时间 (20分钟)、调味模糊词 (适量、少许)
        let lines = text.components(separatedBy: .newlines)
        var dependents: [DependentBinding] = []
        var hasVagueItems = false

        // 食材正则："- 米 400 克", "牛奶: 200 毫升", "鸡蛋 2 个"
        let ingredientRegex = try? NSRegularExpression(
            pattern: #"^[\s\-\*•\d\.\、]*([^\d\:\：\-\s]{1,10})[\s\:\：]+([0-9]+(?:\.[0-9]+)?)\s*(克|g|毫升|ml|个|只|勺|片|瓣|根|包|罐|碗|杯|两|斤|千克|kg)\b"#
        )

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.contains("适量") || trimmedLine.contains("少许") || trimmedLine.contains("适度") {
                hasVagueItems = true
                continue
            }
            if trimmedLine.contains("°C") || trimmedLine.contains("度") || trimmedLine.contains("分钟") || trimmedLine.contains("小时") {
                continue // 温度与时长固定
            }

            if let regex = ingredientRegex,
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
               let nameRange = Range(match.range(at: 1), in: trimmedLine),
               let numRange = Range(match.range(at: 2), in: trimmedLine),
               let unitRange = Range(match.range(at: 3), in: trimmedLine) {

                let name = String(trimmedLine[nameRange])
                let numStr = String(trimmedLine[numRange])
                let unit = String(trimmedLine[unitRange])

                guard let baseNum = Double(numStr), baseNum > 0 else { continue }

                // 排除常见的非食材关键词
                if name.contains("步骤") || name.contains("注意") || name.contains("准备") || name.contains("适合") {
                    continue
                }

                // 搜索该食材在全文中的所有用量出现（例如步骤中 "加入 200 毫升牛奶"）
                var occurrences: [String] = []
                // 1. 原行中的字面用量片段
                occurrences.append("\(numStr) \(unit)")
                occurrences.append("\(numStr)\(unit)")

                let dep = DependentBinding(
                    name: name,
                    originalFragment: "\(numStr) \(unit)",
                    baseNumber: baseNum,
                    unit: unit,
                    isFixed: false,
                    isLocked: false,
                    rule: .proportional(variableId: "servings", baseVariableValue: baseServings ?? 1.0),
                    textLocations: occurrences
                )
                dependents.append(dep)
            }
        }

        // 判断是否符合菜谱条件：至少 2 种食材用量
        guard dependents.count >= 2 else { return nil }

        // 若缺少基准份数，生成缺失提示，让用户补齐
        var missingPrompt: MissingConstraintPrompt? = nil
        let baseVal = baseServings ?? 4.0
        if baseServings == nil {
            missingPrompt = MissingConstraintPrompt(
                prompt: "检测到配方食材，这份原配方适合几人？",
                variableName: "份数",
                suggestedValues: [1, 2, 4],
                unit: "人"
            )
        }

        let servingsVar = InteractiveVariable(
            id: "servings",
            name: "人数",
            kind: .stepper(min: 1, max: 100, step: 1, unit: "人", isInteger: true),
            baseValue: .number(baseVal),
            currentValue: .number(baseVal),
            isPrimary: true,
            unit: "人"
        )

        var session = InteractiveSession(
            itemID: itemID,
            originalText: text,
            patternType: .recipe,
            variables: [servingsVar],
            dependents: dependents,
            missingConstraint: missingPrompt,
            conflicts: [],
            adjustedText: text,
            changeSummary: "\(dependents.count) 项食材联动缩放\(hasVagueItems ? "，适量等调料保持原样" : "")"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 2. 物料与清单线性计算

    private static func tryParseBOM(text: String, itemID: Int64) -> InteractiveSession? {
        // 匹配 "单价 20 元，数量 3 件，运费 10 元，总额 70 元" 模式
        let unitPricePat = #"(?i)(?:单价|单价为|每件)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:元|块|USD|\$)"#
        let quantityPat = #"(?i)(?:数量|件数|订购)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(件|个|套|台|箱)"#
        let fixedFeePat = #"(?i)(?:运费|固定费用|服务费|基础费)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:元|块|USD|\$)"#
        let totalPat = #"(?i)(?:总计|总额|合计|共计)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:元|块|USD|\$)"#

        guard let upRegex = try? NSRegularExpression(pattern: unitPricePat),
              let upMatch = upRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let upRange = Range(upMatch.range(at: 1), in: text),
              let unitPrice = Double(text[upRange]) else { return nil }

        guard let qRegex = try? NSRegularExpression(pattern: quantityPat),
              let qMatch = qRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let qRange = Range(qMatch.range(at: 1), in: text),
              let qUnitRange = Range(qMatch.range(at: 2), in: text),
              let quantity = Double(text[qRange]) else { return nil }

        let qUnit = String(text[qUnitRange])

        var fixedFee: Double = 0
        if let feeRegex = try? NSRegularExpression(pattern: fixedFeePat),
           let feeMatch = feeRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let feeRange = Range(feeMatch.range(at: 1), in: text) {
            fixedFee = Double(text[feeRange]) ?? 0
        }

        var baseTotal = unitPrice * quantity + fixedFee
        var totalFragment = ""
        if let totRegex = try? NSRegularExpression(pattern: totalPat),
           let totMatch = totRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let totRange = Range(totMatch.range(at: 1), in: text) {
            baseTotal = Double(text[totRange]) ?? baseTotal
            if let fullTot = Range(totMatch.range, in: text) {
                totalFragment = String(text[fullTot])
            }
        }

        let quantityVar = InteractiveVariable(
            id: "quantity",
            name: "数量",
            kind: .stepper(min: 1, max: 10000, step: 1, unit: qUnit, isInteger: true),
            baseValue: .number(quantity),
            currentValue: .number(quantity),
            isPrimary: true,
            unit: qUnit
        )

        let totalDep = DependentBinding(
            name: "总额",
            originalFragment: totalFragment.isEmpty ? "\(formatNumber(baseTotal)) 元" : totalFragment,
            baseNumber: baseTotal,
            unit: "元",
            isFixed: false,
            isLocked: false,
            rule: .linearCalculation(unitPrice: unitPrice, quantityVariableId: "quantity", fixedCost: fixedFee),
            textLocations: [totalFragment, "\(formatNumber(baseTotal))元", "\(formatNumber(baseTotal)) 元"].filter { !$0.isEmpty }
        )

        var session = InteractiveSession(
            itemID: itemID,
            originalText: text,
            patternType: .bomCalculation,
            variables: [quantityVar],
            dependents: [totalDep],
            conflicts: [],
            adjustedText: text,
            changeSummary: "根据单价与固定费重算总额"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 3. 会议与活动日程时间顺延

    private static func tryParseSchedule(text: String, itemID: Int64) -> InteractiveSession? {
        // 匹配 "14:00–14:45 分享 (45分钟)" 或 "14:00-14:45 分享"
        let timeRangeRegex = try? NSRegularExpression(
            pattern: #"([0-2]?\d:[0-5]\d)\s*[–\-~至到]\s*([0-2]?\d:[0-5]\d)\s*([^（\(\n\r]+?)(?:\s*[（\(](\d+)\s*分钟[）\)])?"#
        )
        guard let regex = timeRangeRegex else { return nil }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard matches.count >= 2 else { return nil }

        var dependents: [DependentBinding] = []
        var earliestStartHour = 24
        var earliestStartMinute = 60
        var earliestTotalMinutes = 24 * 60

        struct ScheduleSegment {
            let startMinutes: Int
            let endMinutes: Int
            let name: String
            let duration: Int
            let originalStartStr: String
            let originalEndStr: String
            let originalRangeStr: String
        }

        var segments: [ScheduleSegment] = []

        for match in matches {
            guard let sRange = Range(match.range(at: 1), in: text),
                  let eRange = Range(match.range(at: 2), in: text),
                  let nRange = Range(match.range(at: 3), in: text) else { continue }

            let sStr = String(text[sRange])
            let eStr = String(text[eRange])
            let name = String(text[nRange]).trimmingCharacters(in: .whitespaces)

            guard let sMins = parseTimeMinutes(sStr),
                  let eMins = parseTimeMinutes(eStr) else { continue }

            var dur = eMins - sMins
            if dur <= 0 { dur += 24 * 60 } // 跨午夜处理

            if let dRange = Range(match.range(at: 4), in: text), let parsedDur = Int(text[dRange]) {
                dur = parsedDur
            }

            if sMins < earliestTotalMinutes {
                earliestTotalMinutes = sMins
                earliestStartHour = sMins / 60
                earliestStartMinute = sMins % 60
            }

            if let fullRange = Range(match.range, in: text) {
                segments.append(ScheduleSegment(
                    startMinutes: sMins,
                    endMinutes: eMins,
                    name: name,
                    duration: dur,
                    originalStartStr: sStr,
                    originalEndStr: eStr,
                    originalRangeStr: String(text[fullRange])
                ))
            }
        }

        guard !segments.isEmpty else { return nil }

        // 构建各环节的依赖项
        for seg in segments {
            let offset = seg.startMinutes - earliestTotalMinutes
            let dep = DependentBinding(
                name: seg.name,
                originalFragment: "\(seg.originalStartStr)–\(seg.originalEndStr)",
                baseNumber: Double(seg.startMinutes),
                unit: "",
                isFixed: false,
                isLocked: false,
                rule: .timeOffset(offsetMinutes: offset, baseTimeVariableId: "start_time", durationMinutes: seg.duration),
                textLocations: [
                    "\(seg.originalStartStr)–\(seg.originalEndStr)",
                    "\(seg.originalStartStr)-\(seg.originalEndStr)",
                    "\(seg.originalStartStr) - \(seg.originalEndStr)"
                ]
            )
            dependents.append(dep)
        }

        // 主变量：开始时间（步进 15 分钟）
        let startVar = InteractiveVariable(
            id: "start_time",
            name: "开始时间",
            kind: .time(stepMinutes: 15),
            baseValue: .time(hour: earliestStartHour, minute: earliestStartMinute),
            currentValue: .time(hour: earliestStartHour, minute: earliestStartMinute),
            isPrimary: true
        )

        // 次变量：若有休息环节，提供休息时长调节
        var variables = [startVar]
        if let restSeg = segments.first(where: { $0.name.contains("休息") || $0.name.contains("茶歇") }) {
            let restVar = InteractiveVariable(
                id: "break_duration",
                name: "休息时长",
                kind: .duration(stepMinutes: 5, unit: "分钟"),
                baseValue: .durationMinutes(restSeg.duration),
                currentValue: .durationMinutes(restSeg.duration),
                isPrimary: false,
                unit: "分钟"
            )
            variables.append(restVar)
        }

        var session = InteractiveSession(
            itemID: itemID,
            originalText: text,
            patternType: .schedule,
            variables: variables,
            dependents: dependents,
            conflicts: [],
            adjustedText: text,
            changeSummary: "整体顺延 \(segments.count) 个环节，保持各环节时长"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 4. 差旅行程与日期偏移

    private static func tryParseItinerary(text: String, itemID: Int64) -> InteractiveSession? {
        // 匹配 "出发日期：2026-10-01" 或 "2026年10月1日出发"
        let baseDatePat = #"(?i)(?:出发日期|开始日期|出发时间|出行日期)\s*[:：]?\s*(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})日?"#
        guard let bRegex = try? NSRegularExpression(pattern: baseDatePat),
              let bMatch = bRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let yRange = Range(bMatch.range(at: 1), in: text),
              let mRange = Range(bMatch.range(at: 2), in: text),
              let dRange = Range(bMatch.range(at: 3), in: text),
              let year = Int(text[yRange]),
              let month = Int(text[mRange]),
              let day = Int(text[dRange]) else { return nil }

        // 匹配 "第 1 天", "第 2 天", "D1", "D2"
        let dayRegex = try? NSRegularExpression(
            pattern: #"(?i)(?:第\s*(\d+)\s*天|D(\d+))\s*([（\(].*?[）\)])?\s*[:：]?\s*([^\n\r]+)"#
        )
        guard let dRegex = dayRegex else { return nil }

        let matches = dRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count >= 2 else { return nil }

        var dependents: [DependentBinding] = []

        for match in matches {
            let dayNumStr = Range(match.range(at: 1), in: text).map { String(text[$0]) }
                ?? Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? "1"
            guard let dayOffset = Int(dayNumStr) else { continue }

            let titleRange = Range(match.range(at: 4), in: text)
            let title = titleRange.map { String(text[$0]) } ?? "日程"

            let isFixed = title.contains("固定") || title.contains("不可改")

            // 提取该日程行中的日期或括号描述
            var locations: [String] = []
            if let fullRange = Range(match.range, in: text) {
                let fullStr = String(text[fullRange])
                locations.append(fullStr)
            }

            let dep = DependentBinding(
                name: "D\(dayOffset) \(title.prefix(8))",
                originalFragment: "D\(dayOffset)",
                baseNumber: Double(dayOffset - 1),
                unit: "天",
                isFixed: isFixed,
                isLocked: false,
                rule: .dateOffset(offsetDays: dayOffset - 1, baseDateVariableId: "start_date"),
                textLocations: locations
            )
            dependents.append(dep)
        }

        let dateVar = InteractiveVariable(
            id: "start_date",
            name: "出发日期",
            kind: .date(stepDays: 1),
            baseValue: .date(year: year, month: month, day: day),
            currentValue: .date(year: year, month: month, day: day),
            isPrimary: true
        )

        var session = InteractiveSession(
            itemID: itemID,
            originalText: text,
            patternType: .itinerary,
            variables: [dateVar],
            dependents: dependents,
            conflicts: [],
            adjustedText: text,
            changeSummary: "顺延可移动日程，自动重算日期与星期"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 5. 核心联动重算 (Recalculate & Replace)

    /// 当用户调整变量值或切换单项锁定时，重算所有依赖项并生成新文本
    public static func recalculate(session: inout InteractiveSession) {
        var updatedText = session.originalText
        var conflicts: [InteractiveConflict] = []
        var updatedCount = 0

        switch session.patternType {
        case .recipe:
            guard let servingsVar = session.variables.first(where: { $0.id == "servings" }) else { break }
            let baseServings = servingsVar.baseValue.asNumber
            let currentServings = servingsVar.currentValue.asNumber
            guard baseServings > 0 else { break }
            let ratio = currentServings / baseServings

            // 更新食材依赖项（按含义与对应关系在相关行内精确替换，杜绝同名数值误伤）
            var recipeLines = updatedText.components(separatedBy: .newlines)
            for i in 0..<session.dependents.count {
                let dep = session.dependents[i]
                if dep.isLocked {
                    continue // 单项锁定，跳过
                }
                let baseNum = dep.baseNumber
                let newNum = baseNum * ratio
                session.dependents[i].currentNumber = newNum

                let baseStr = formatNumber(baseNum)
                let newStr = formatNumber(newNum)
                let unit = dep.unit

                if baseStr != newStr {
                    updatedCount += 1
                }

                let targets = [
                    "\(baseStr) \(unit)",
                    "\(baseStr)\(unit)"
                ]
                let replacement = "\(newStr) \(unit)"

                for lineIdx in 0..<recipeLines.count {
                    let line = recipeLines[lineIdx]
                    // 仅在包含该食材名称的行中替换该用量
                    if line.contains(dep.name) {
                        var updatedLine = line
                        for target in targets {
                            if updatedLine.contains(target) {
                                updatedLine = updatedLine.replacingOccurrences(of: target, with: replacement)
                            }
                        }
                        recipeLines[lineIdx] = updatedLine
                    }
                }

                // 检查不可分割物品的整数建议（如鸡蛋为 3.5 个）
                if (unit == "个" || unit == "只" || unit == "根" || unit == "包") && floor(newNum) != newNum {
                    let floorVal = Int(floor(newNum))
                    let ceilVal = Int(ceil(newNum))
                    conflicts.append(InteractiveConflict(
                        id: "fractional_\(dep.name)",
                        message: "\(dep.name)比例计算为 \(newStr) \(unit)，建议按需选用 \(floorVal) 或 \(ceilVal) 个整件",
                        severity: .info
                    ))
                }
            }
            updatedText = recipeLines.joined(separator: "\n")

            // 更新标题/正文中的主份数（如 "4人份" -> "7人份"）
            let baseServingsInt = Int(baseServings)
            let currServingsInt = Int(currentServings)
            let baseServingsPatterns = [
                "\(baseServingsInt)人份", "\(baseServingsInt) 人份",
                "\(baseServingsInt)人量", "\(baseServingsInt) 人量",
                "\(baseServingsInt)份", "\(baseServingsInt) 份",
                "\(numberToChinese(baseServingsInt))人份"
            ]
            for pat in baseServingsPatterns {
                if updatedText.contains(pat) {
                    let repl = "\(currServingsInt)人份"
                    updatedText = updatedText.replacingOccurrences(of: pat, with: repl)
                    break
                }
            }

            session.changeSummary = "已更新 \(updatedCount) 项用量，温度与时长保持原值"

        case .bomCalculation:
            guard let qVar = session.variables.first(where: { $0.id == "quantity" }) else { break }
            let baseQ = qVar.baseValue.asNumber
            let currQ = qVar.currentValue.asNumber

            for i in 0..<session.dependents.count {
                if session.dependents[i].isLocked { continue }
                if case .linearCalculation(let unitPrice, _, let fixedCost) = session.dependents[i].rule {
                    let baseTot = session.dependents[i].baseNumber
                    let newTot = unitPrice * currQ + fixedCost
                    session.dependents[i].currentNumber = newTot

                    let baseTotStr = formatNumber(baseTot)
                    let newTotStr = formatNumber(newTot)

                    let targets = [
                        "\(baseTotStr) 元", "\(baseTotStr)元", "\(baseTotStr)"
                    ]
                    for t in targets {
                        if updatedText.contains(t) {
                            updatedText = updatedText.replacingOccurrences(of: t, with: "\(newTotStr) 元")
                            break
                        }
                    }
                }
            }

            // 更新数量字面量
            let baseQStr = formatNumber(baseQ)
            let currQStr = formatNumber(currQ)
            let qUnit = qVar.unit
            let qTargets = ["\(baseQStr) \(qUnit)", "\(baseQStr)\(qUnit)"]
            for qt in qTargets {
                if updatedText.contains(qt) {
                    updatedText = updatedText.replacingOccurrences(of: qt, with: "\(currQStr) \(qUnit)")
                    break
                }
            }
            session.changeSummary = "数量已调为 \(currQStr) \(qUnit)，总额自动重算"

        case .schedule:
            guard let startVar = session.variables.first(where: { $0.id == "start_time" }) else { break }
            guard case .time(let newH, let newM) = startVar.currentValue,
                  case .time(let baseH, let baseM) = startVar.baseValue else { break }

            let baseStartMins = baseH * 60 + baseM
            let newStartMins = newH * 60 + newM

            var latestEndMinutes = 0

            for i in 0..<session.dependents.count {
                if session.dependents[i].isLocked { continue }
                if case .timeOffset(let offset, _, let duration) = session.dependents[i].rule {
                    let itemStartMins = (newStartMins + offset) % (24 * 60)
                    let itemEndMins = (itemStartMins + duration) % (24 * 60)

                    let oldStartMins = (baseStartMins + offset) % (24 * 60)
                    let oldEndMins = (oldStartMins + duration) % (24 * 60)

                    let oldTimeStr = String(format: "%02d:%02d–%02d:%02d", oldStartMins / 60, oldStartMins % 60, oldEndMins / 60, oldEndMins % 60)
                    let newTimeStr = String(format: "%02d:%02d–%02d:%02d", itemStartMins / 60, itemStartMins % 60, itemEndMins / 60, itemEndMins % 60)

                    let oldDashStr = String(format: "%02d:%02d-%02d:%02d", oldStartMins / 60, oldStartMins % 60, oldEndMins / 60, oldEndMins % 60)

                    if updatedText.contains(oldTimeStr) {
                        updatedText = updatedText.replacingOccurrences(of: oldTimeStr, with: newTimeStr)
                        updatedCount += 1
                    } else if updatedText.contains(oldDashStr) {
                        updatedText = updatedText.replacingOccurrences(of: oldDashStr, with: newTimeStr)
                        updatedCount += 1
                    }

                    let endM = itemStartMins + duration
                    if endM > latestEndMinutes {
                        latestEndMinutes = endM
                    }
                }
            }

            // 检查固定截止时间冲突：例如 "必须在 16:45 结束"
            let deadlinePat = #"(?:必须在|最晚|需在|前结束)?\s*([0-2]?\d:[0-5]\d)\s*(?:前结束|结束|清场)"#
            if let dRegex = try? NSRegularExpression(pattern: deadlinePat),
               let match = dRegex.firstMatch(in: session.originalText, range: NSRange(session.originalText.startIndex..., in: session.originalText)),
               let r = Range(match.range(at: 1), in: session.originalText),
               let deadMins = parseTimeMinutes(String(session.originalText[r])) {
                if latestEndMinutes > deadMins {
                    let overtime = latestEndMinutes - deadMins
                    conflicts.append(InteractiveConflict(
                        id: "schedule_overtime",
                        message: "必须在 \(String(session.originalText[r])) 结束，调整后已超时 \(overtime) 分钟",
                        severity: .warning
                    ))
                }
            }

            session.changeSummary = "已顺延 \(updatedCount) 个环节，环节时长保持不变"

        case .itinerary:
            guard let dateVar = session.variables.first(where: { $0.id == "start_date" }),
                  case .date(let newY, let newM, let newD) = dateVar.currentValue,
                  case .date(let baseY, let baseM, let baseD) = dateVar.baseValue else { break }

            let calendar = Calendar.current
            let baseComps = DateComponents(year: baseY, month: baseM, day: baseD)
            let newComps = DateComponents(year: newY, month: newM, day: newD)
            guard let baseDate = calendar.date(from: baseComps),
                  let newDate = calendar.date(from: newComps) else { break }

            var itinLines = updatedText.components(separatedBy: .newlines)

            // 1. 仅在出发日期所在行替换出发日期
            let baseDateStr1 = String(format: "%04d-%02d-%02d", baseY, baseM, baseD)
            let newDateStr1 = String(format: "%04d-%02d-%02d", newY, newM, newD)
            let baseDateStr2 = String(format: "%d月%d日", baseM, baseD)
            let newDateStr2 = String(format: "%d月%d日", newM, newD)

            for lineIdx in 0..<itinLines.count {
                let line = itinLines[lineIdx]
                if line.contains("出发") || line.contains("开始") || line.contains("出行") {
                    var uLine = line
                    if uLine.contains(baseDateStr1) {
                        uLine = uLine.replacingOccurrences(of: baseDateStr1, with: newDateStr1)
                    }
                    if uLine.contains(baseDateStr2) {
                        uLine = uLine.replacingOccurrences(of: baseDateStr2, with: newDateStr2)
                    }
                    itinLines[lineIdx] = uLine
                }
            }

            // 2. 顺延各可移动日程行
            for i in 0..<session.dependents.count {
                let dep = session.dependents[i]
                if dep.isLocked || dep.isFixed { continue }
                if case .dateOffset(let offsetDays, _) = dep.rule {
                    if let oldItemDate = calendar.date(byAdding: .day, value: offsetDays, to: baseDate),
                       let newItemDate = calendar.date(byAdding: .day, value: offsetDays, to: newDate) {

                        let oldM = calendar.component(.month, from: oldItemDate)
                        let oldD = calendar.component(.day, from: oldItemDate)
                        let oldW = weekdayName(calendar.component(.weekday, from: oldItemDate))

                        let newM = calendar.component(.month, from: newItemDate)
                        let newD = calendar.component(.day, from: newItemDate)
                        let newW = weekdayName(calendar.component(.weekday, from: newItemDate))

                        let oldPart1 = "\(oldM)月\(oldD)日 \(oldW)"
                        let oldPart2 = "\(oldM)月\(oldD)日\(oldW)"
                        let oldPart3 = "\(oldM)月\(oldD)日"

                        let newPart = "\(newM)月\(newD)日 \(newW)"

                        let dayKey1 = "第 \(offsetDays + 1) 天"
                        let dayKey2 = "第\(offsetDays + 1)天"
                        let dayKey3 = "D\(offsetDays + 1)"

                        for lineIdx in 0..<itinLines.count {
                            let line = itinLines[lineIdx]
                            if !line.contains("固定") && (line.contains(dayKey1) || line.contains(dayKey2) || line.contains(dayKey3)) {
                                var uLine = line
                                if uLine.contains(oldPart1) {
                                    uLine = uLine.replacingOccurrences(of: oldPart1, with: newPart)
                                    updatedCount += 1
                                } else if uLine.contains(oldPart2) {
                                    uLine = uLine.replacingOccurrences(of: oldPart2, with: newPart)
                                    updatedCount += 1
                                } else if uLine.contains(oldPart3) {
                                    uLine = uLine.replacingOccurrences(of: oldPart3, with: "\(newM)月\(newD)日")
                                    updatedCount += 1
                                }
                                itinLines[lineIdx] = uLine
                            }
                        }
                    }
                }
            }

            updatedText = itinLines.joined(separator: "\n")
            session.changeSummary = "已顺延可移动日程，保留固定行程"

        case .general:
            break
        }

        session.conflicts = conflicts
        session.adjustedText = updatedText

        // 生成当前变焦层级文本
        session.zoomLevels = generateZoomLevels(text: updatedText, session: session)
    }

    // MARK: - 6. 粘贴变焦多层级生成 (Paste Zoom)

    public static func generateZoomLevels(text: String, session: InteractiveSession) -> [ZoomLevel: String] {
        var levels: [ZoomLevel: String] = [:]
        levels[.full] = text

        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        switch session.patternType {
        case .recipe:
            // 核心要点：食材清单
            let ingredients = session.dependents.map { "• \($0.name)：\(formatNumber($0.currentNumber)) \($0.unit)" }
            levels[.keyPoints] = ingredients.joined(separator: "\n")

            // 结论清单：步骤要点
            let steps = lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.contains("步骤") || t.contains("1.") || t.contains("2.") || t.contains("3.") || t.contains("制作")
            }
            levels[.actionItems] = steps.isEmpty ? ingredients.joined(separator: "\n") : steps.joined(separator: "\n")

            // 一句话概括
            if let servingsVar = session.primaryVariable {
                let serv = servingsVar.currentValue.displayText
                let topIngs = session.dependents.prefix(3).map { "\($0.name)\(formatNumber($0.currentNumber))\($0.unit)" }.joined(separator: "、")
                levels[.oneLine] = "\(serv)人份配方：\(topIngs)"
            } else {
                levels[.oneLine] = lines.first ?? text
            }

        case .schedule:
            // 核心要点：环节与时间清单
            let timeItems = session.dependents.map { "• \($0.name)" }
            levels[.keyPoints] = lines.filter { $0.contains(":") || $0.contains("–") || $0.contains("-") }.joined(separator: "\n")

            // 结论清单：各环节清单
            levels[.actionItems] = timeItems.joined(separator: "\n")

            // 一句话概括
            if let startVar = session.primaryVariable {
                levels[.oneLine] = "日程安排：\(startVar.currentValue.displayText) 开始，共 \(session.dependents.count) 个环节"
            } else {
                levels[.oneLine] = lines.first ?? text
            }

        case .itinerary:
            // 核心要点：日程要点
            levels[.keyPoints] = lines.filter { $0.contains("第") || $0.contains("D") }.joined(separator: "\n")
            levels[.actionItems] = levels[.keyPoints]

            if let dateVar = session.primaryVariable {
                levels[.oneLine] = "行程安排：\(dateVar.currentValue.displayText) 出发，全程 \(session.dependents.count) 天"
            } else {
                levels[.oneLine] = lines.first ?? text
            }

        case .bomCalculation, .general:
            levels[.keyPoints] = lines.prefix(4).joined(separator: "\n")
            levels[.actionItems] = lines.filter { $0.contains("总") || $0.contains("合计") }.joined(separator: "\n")
            levels[.oneLine] = lines.first ?? text
        }

        return levels
    }

    // MARK: - 辅助计算函数

    private static func formatNumber(_ num: Double) -> String {
        if floor(num) == num {
            return String(format: "%.0f", num)
        } else {
            let str = String(format: "%.2f", num)
            if str.hasSuffix("0") {
                return String(format: "%.1f", num)
            }
            return str
        }
    }

    private static func parseTimeMinutes(_ timeStr: String) -> Int? {
        let parts = timeStr.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private static func parseChineseNumber(_ str: String) -> Double? {
        let map: [String: Double] = [
            "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5,
            "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        return map[str]
    }

    private static func numberToChinese(_ num: Int) -> String {
        let map = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        if num >= 1 && num <= 10 {
            return map[num]
        }
        return "\(num)"
    }

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "周日"
        case 2: return "周一"
        case 3: return "周二"
        case 4: return "周三"
        case 5: return "周四"
        case 6: return "周五"
        case 7: return "周六"
        default: return ""
        }
    }
}
