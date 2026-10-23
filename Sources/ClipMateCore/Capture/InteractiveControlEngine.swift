import Foundation

/// 内容控件识别与联动引擎
/// 零网络依赖、纯本地高性能算法，负责识别文本中的变量与关系，并执行精准的依赖联动更新。
public enum InteractiveControlEngine {

    // MARK: - 主入口

    /// 尝试分析文本并构建 InteractiveSession。若无可靠的可调关系且不适于变焦则返回 nil。
    public static func analyze(text: String, itemID: Int64 = 0) -> InteractiveSession? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 输入保护：仅用于模式识别采样的安全预算（64KB）
        // 关键保证：session.originalText 永远为 100% 完整原文，绝不截断丢弃尾部
        let fullText = text
        let scanText = text.count > 65536 ? String(text.prefix(65536)) : text

        // 尝试提取各种独立关系
        let proportionalSession = tryParseProportional(scanText: scanText, fullText: fullText, itemID: itemID)
        let bomSession = tryParseBOM(scanText: scanText, fullText: fullText, itemID: itemID)
        let scheduleSession = tryParseSchedule(scanText: scanText, fullText: fullText, itemID: itemID)
        let itinerarySession = tryParseItinerary(scanText: scanText, fullText: fullText, itemID: itemID)

        // 收集所有有效会话
        let extractedSessions = [proportionalSession, bomSession, scheduleSession, itinerarySession].compactMap { $0 }

        if extractedSessions.isEmpty {
            // 兜底：若无数值关系，但具备结构化文本特征（如会议记录、要点笔记），独立支持粘贴变焦
            return tryParseGeneralZoom(scanText: scanText, fullText: fullText, itemID: itemID)
        } else if extractedSessions.count == 1 {
            return extractedSessions[0]
        } else {
            // 多关系组合共存（例如同时包含物料数量和差旅行程日期）
            return combineSessions(extractedSessions, fullText: fullText, itemID: itemID)
        }
    }

    // MARK: - 组合多关系会话

    private static func combineSessions(_ sessions: [InteractiveSession], fullText: String, itemID: Int64) -> InteractiveSession {
        var combinedVariables: [InteractiveVariable] = []
        var combinedDependents: [DependentBinding] = []
        var combinedConflicts: [InteractiveConflict] = []
        var summaries: [String] = []

        for s in sessions {
            combinedVariables.append(contentsOf: s.variables)
            combinedDependents.append(contentsOf: s.dependents)
            combinedConflicts.append(contentsOf: s.conflicts)
            if !s.changeSummary.isEmpty {
                summaries.append(s.changeSummary)
            }
        }

        var combinedSession = InteractiveSession(
            itemID: itemID,
            originalText: fullText,
            patternType: .general,
            variables: combinedVariables,
            dependents: combinedDependents,
            missingConstraint: sessions.first?.missingConstraint,
            conflicts: combinedConflicts,
            adjustedText: fullText,
            changeSummary: summaries.joined(separator: "；")
        )

        recalculate(session: &combinedSession)
        return combinedSession
    }

    // MARK: - 1. 通用比例识别 (涵盖菜谱、配方、工艺制作与套数)

    private static func tryParseProportional(scanText: String, fullText: String, itemID: Int64) -> InteractiveSession? {
        // 匹配主份数/套数/人数：例如 "4人份", "制作 3 套展示架", "配方 2 份", "4 servings"
        var baseServings: Double? = nil
        var servingsUnit = "人"
        var servingsName = "人数"

        let servingsPatterns: [(String, String, String)] = [
            (#"(?i)([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]+)\s*(?:人份|人量|人|servings?)"#, "人", "人数"),
            (#"(?i)(?:适合|配方|分量|份量)\s*([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]+)\s*人"#, "人", "人数"),
            (#"(?i)(?:制作|分量|份量|适合|配方|总量|订购|采购)\s*([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]+)\s*(套|组|批|箱|包|件|个)(?![a-zA-Z0-9])"#, "套", "套数"),
            (#"(?i)([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]+)\s*套"#, "套", "套数"),
            (#"(?i)(?:适合|配方|分量|份量)?\s*([0-9]+(?:\.[0-9]+)?|[一二两三四五六七八九十]+)\s*份"#, "份", "份数")
        ]

        for (pat, defUnit, defName) in servingsPatterns {
            if let regex = try? NSRegularExpression(pattern: pat),
               let match = regex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
               let range = Range(match.range(at: 1), in: scanText) {
                let matchedStr = String(scanText[range])
                let extractedUnit: String
                let extractedName: String
                if match.numberOfRanges > 2, let uRange = Range(match.range(at: 2), in: scanText) {
                    let u = String(scanText[uRange])
                    extractedUnit = u.isEmpty ? defUnit : u
                    extractedName = (extractedUnit == "套") ? "套数" : ((extractedUnit == "人") ? "人数" : "\(extractedUnit)数")
                } else {
                    extractedUnit = defUnit
                    extractedName = defName
                }

                if let num = Double(matchedStr) {
                    baseServings = num
                    servingsUnit = extractedUnit
                    servingsName = extractedName
                    break
                } else if let num = parseChineseNumber(matchedStr) {
                    baseServings = num
                    servingsUnit = extractedUnit
                    servingsName = extractedName
                    break
                }
            }
        }

        // 识别物品用量：涵盖整数、小数（如 0.125）、分数（如 1/2）与范围区间（如 2-3）
        // 过滤不可缩放项：温度 (180°C)、固定时长 (20分钟)、调味模糊词 (适量、少许) 及明确排除行 (另备...不参与)
        let lines = scanText.components(separatedBy: .newlines)
        var dependents: [DependentBinding] = []
        var hasVagueItems = false

        // 通用物品正则："- 米 400 克", "水 200 毫升", "糖 1/2 杯", "盐 2-3 克", "酵母 0.125 克", "木条 6 米", "螺丝 12 枚"
        let itemPattern = #"^[\s\-\*•\d\.\、]*(?:每套需要|总用量为)?\s*([^\d\:\：\-\s\/\~至到，,;；]{1,12})[\s\:\：]+([0-9]+(?:\.[0-9]+)?|[0-9]+\/[0-9]+|[0-9]+(?:\.[0-9]+)?\s*[-~至到]\s*[0-9]+(?:\.[0-9]+)?)\s*(克|g|毫升|ml|个|只|勺|片|瓣|根|包|罐|碗|杯|两|斤|千克|kg|米|m|枚|台|套|件)(?![a-zA-Z0-9])"#
        let itemRegex = try? NSRegularExpression(pattern: itemPattern)

        // 句子内物品提取正则（例如 "每套需要 2 米木条和 4 枚螺丝；总用量为木条 6 米、螺丝 12 枚"）
        let inlineItemPattern = #"([^\d\:\：\-\s\/\~至到，,;；]{1,10})[\s\:\：]*([0-9]+(?:\.[0-9]+)?|[0-9]+\/[0-9]+|[0-9]+(?:\.[0-9]+)?\s*[-~至到]\s*[0-9]+(?:\.[0-9]+)?)\s*(克|g|毫升|ml|个|只|勺|片|瓣|根|包|罐|碗|杯|两|斤|千克|kg|米|m|枚|台|套|件)(?![a-zA-Z0-9])"#
        let inlineItemRegex = try? NSRegularExpression(pattern: inlineItemPattern)

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.contains("适量") || trimmedLine.contains("少许") || trimmedLine.contains("适度") {
                hasVagueItems = true
                continue
            }
            if trimmedLine.contains("°C") || trimmedLine.contains("度") || trimmedLine.contains("分钟") || trimmedLine.contains("小时") {
                continue
            }
            if trimmedLine.contains("不参与") {
                continue // 明确声明不参与缩放的行直接跳过
            }
            if trimmedLine.hasPrefix("步骤") || trimmedLine.hasPrefix("做法") || trimmedLine.contains("制作步骤") || trimmedLine.hasPrefix("1.") || trimmedLine.hasPrefix("2.") || trimmedLine.hasPrefix("3.") {
                continue // 步骤说明引用食材，不作为新的独立食材定义项
            }

            // 先按整行正则尝试
            var matchedInLine = false
            if let regex = itemRegex,
               let match = regex.firstMatch(in: trimmedLine, range: NSRange(trimmedLine.startIndex..., in: trimmedLine)),
               let nameRange = Range(match.range(at: 1), in: trimmedLine),
               let numRange = Range(match.range(at: 2), in: trimmedLine),
               let unitRange = Range(match.range(at: 3), in: trimmedLine) {

                let name = String(trimmedLine[nameRange]).trimmingCharacters(in: .whitespaces)
                let numStr = String(trimmedLine[numRange]).trimmingCharacters(in: .whitespaces)
                let unit = String(trimmedLine[unitRange]).trimmingCharacters(in: .whitespaces)

                if let (baseNum, literal) = parseNumericValue(numStr) {
                    if !name.contains("步骤") && !name.contains("注意") && !name.contains("准备") && !name.contains("制作") {
                        let dep = DependentBinding(
                            name: name,
                            originalFragment: "\(numStr) \(unit)",
                            baseNumber: baseNum,
                            originalLiteral: literal,
                            unit: unit,
                            isFixed: false,
                            isLocked: false,
                            rule: .proportional(variableId: "servings", baseVariableValue: baseServings ?? 1.0),
                            textLocations: ["\(numStr) \(unit)", "\(numStr)\(unit)"]
                        )
                        dependents.append(dep)
                        matchedInLine = true
                    }
                }
            }

            // 若整行未命中，尝试行内多项匹配（处理短语组合，如 "总用量为木条 6 米、螺丝 12 枚"）
            if !matchedInLine, let inlineReg = inlineItemRegex {
                let nsRange = NSRange(trimmedLine.startIndex..., in: trimmedLine)
                let matches = inlineReg.matches(in: trimmedLine, range: nsRange)
                for m in matches {
                    guard let nR = Range(m.range(at: 1), in: trimmedLine),
                          let vR = Range(m.range(at: 2), in: trimmedLine),
                          let uR = Range(m.range(at: 3), in: trimmedLine) else { continue }
                    let name = String(trimmedLine[nR]).trimmingCharacters(in: .whitespaces)
                    let numStr = String(trimmedLine[vR]).trimmingCharacters(in: .whitespaces)
                    let unit = String(trimmedLine[uR]).trimmingCharacters(in: .whitespaces)

                    guard !name.contains("每") && !name.contains("总") && !name.contains("需要") else { continue }

                    if let (baseNum, literal) = parseNumericValue(numStr) {
                        // 避免重复
                        if !dependents.contains(where: { $0.name == name }) {
                            let dep = DependentBinding(
                                name: name,
                                originalFragment: "\(numStr) \(unit)",
                                baseNumber: baseNum,
                                originalLiteral: literal,
                                unit: unit,
                                isFixed: false,
                                isLocked: false,
                                rule: .proportional(variableId: "servings", baseVariableValue: baseServings ?? 1.0),
                                textLocations: ["\(numStr) \(unit)", "\(numStr)\(unit)"]
                            )
                            dependents.append(dep)
                        }
                    }
                }
            }
        }

        // 至少包含 2 个可缩放项方可确认为有效比例结构
        guard dependents.count >= 2 else { return nil }

        // 缺失基准提示处理
        var missingPrompt: MissingConstraintPrompt? = nil
        let baseVal = baseServings ?? 4.0
        if baseServings == nil {
            missingPrompt = MissingConstraintPrompt(
                prompt: "检测到配方/物料清单，这份原配方基准为几\(servingsUnit)？",
                variableName: servingsName,
                suggestedValues: [1, 2, 4],
                unit: servingsUnit
            )
        }

        let servingsVar = InteractiveVariable(
            id: "servings",
            name: servingsName,
            kind: .stepper(min: 1, max: 1000, step: 1, unit: servingsUnit, isInteger: true),
            baseValue: .number(baseVal),
            currentValue: .number(baseVal),
            isPrimary: true,
            unit: servingsUnit
        )

        let patternType: DetectedPatternType = (servingsUnit == "人" || servingsUnit == "份") ? .recipe : .general

        var session = InteractiveSession(
            itemID: itemID,
            originalText: fullText,
            patternType: patternType,
            variables: [servingsVar],
            dependents: dependents,
            missingConstraint: missingPrompt,
            conflicts: [],
            adjustedText: fullText,
            changeSummary: "\(dependents.count) 项清单联动缩放\(hasVagueItems ? "，适量等项保持原样" : "")"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 2. 物料与清单线性计算 (BOM, 单价 × 数量 + 固定费 - 优惠)

    private static func tryParseBOM(scanText: String, fullText: String, itemID: Int64) -> InteractiveSession? {
        let currencyPat = #"(USD|EUR|GBP|CNY|HKD|JPY|元|块|\$|¥|€|£)"#
        let unitPricePat = #"(?i)(?:单价|单价为|每件)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*"# + currencyPat + "?"
        let quantityPat = #"(?i)(?:数量|件数|订购)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*(件|个|套|台|箱|包|只)"#
        let fixedFeePat = #"(?i)(?:运费|固定费用|服务费|基础费)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*"# + currencyPat + "?"
        let discountPat = #"(?i)(?:优惠|折扣|立减|减免)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*"# + currencyPat + "?"
        let totalPat = #"(?i)(?:总计|总额|合计|共计)\s*[:：]?\s*([0-9]+(?:\.[0-9]+)?)\s*"# + currencyPat + "?"

        guard let upRegex = try? NSRegularExpression(pattern: unitPricePat),
              let upMatch = upRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
              let upRange = Range(upMatch.range(at: 1), in: scanText),
              let unitPrice = Double(scanText[upRange]) else { return nil }

        guard let qRegex = try? NSRegularExpression(pattern: quantityPat),
              let qMatch = qRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
              let qRange = Range(qMatch.range(at: 1), in: scanText),
              let qUnitRange = Range(qMatch.range(at: 2), in: scanText),
              let quantity = Double(scanText[qRange]) else { return nil }

        let qUnit = String(scanText[qUnitRange])

        // 检测币种
        var detectedCurrency = "元"
        let allCurMatches = [upMatch]
        for m in allCurMatches {
            if m.range(at: 2).location != NSNotFound, let cR = Range(m.range(at: 2), in: scanText) {
                let cStr = String(scanText[cR])
                if !cStr.isEmpty {
                    detectedCurrency = cStr
                    break
                }
            }
        }

        var fixedFee: Double = 0
        if let feeRegex = try? NSRegularExpression(pattern: fixedFeePat),
           let feeMatch = feeRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
           let feeRange = Range(feeMatch.range(at: 1), in: scanText) {
            fixedFee = Double(scanText[feeRange]) ?? 0
            if feeMatch.range(at: 2).location != NSNotFound, let cR = Range(feeMatch.range(at: 2), in: scanText) {
                let cStr = String(scanText[cR])
                if !cStr.isEmpty && detectedCurrency == "元" { detectedCurrency = cStr }
            }
        }

        var discount: Double = 0
        var hasExplicitDiscount = false
        if let discRegex = try? NSRegularExpression(pattern: discountPat),
           let discMatch = discRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
           let discRange = Range(discMatch.range(at: 1), in: scanText) {
            discount = Double(scanText[discRange]) ?? 0
            hasExplicitDiscount = true
        }

        var statedTotal: Double? = nil
        var totalFragment = ""
        if let totRegex = try? NSRegularExpression(pattern: totalPat),
           let totMatch = totRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
           let totRange = Range(totMatch.range(at: 1), in: scanText) {
            statedTotal = Double(scanText[totRange])
            if let fullTot = Range(totMatch.range, in: scanText) {
                totalFragment = String(scanText[fullTot])
            }
            if totMatch.range(at: 2).location != NSNotFound, let cR = Range(totMatch.range(at: 2), in: scanText) {
                let cStr = String(scanText[cR])
                if !cStr.isEmpty && detectedCurrency == "元" { detectedCurrency = cStr }
            }
        }

        let computedBaseTotal = unitPrice * quantity + fixedFee - discount
        let baseTotal = statedTotal ?? computedBaseTotal

        var conflicts: [InteractiveConflict] = []
        // 若原文显式写有优惠且计算存在差额，产生提醒，未调整时严禁静默覆盖
        if hasExplicitDiscount || (statedTotal != nil && statedTotal != (unitPrice * quantity + fixedFee)) {
            if statedTotal != computedBaseTotal {
                conflicts.append(InteractiveConflict(
                    id: "discount_discrepancy",
                    message: "原文总额包含特殊优惠或差额，未调整前保留原文",
                    severity: .info
                ))
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
            originalFragment: totalFragment.isEmpty ? "\(formatNumber(baseTotal)) \(detectedCurrency)" : totalFragment,
            baseNumber: baseTotal,
            originalLiteral: "\(formatNumber(baseTotal))",
            currency: detectedCurrency,
            unit: detectedCurrency,
            isFixed: false,
            isLocked: false,
            rule: .linearCalculation(unitPrice: unitPrice, quantityVariableId: "quantity", fixedCost: fixedFee - discount),
            textLocations: [totalFragment, "\(formatNumber(baseTotal)) \(detectedCurrency)", "\(formatNumber(baseTotal))\(detectedCurrency)"].filter { !$0.isEmpty }
        )

        var session = InteractiveSession(
            itemID: itemID,
            originalText: fullText,
            patternType: .bomCalculation,
            variables: [quantityVar],
            dependents: [totalDep],
            conflicts: conflicts,
            adjustedText: fullText,
            changeSummary: "根据单价与固定费重算总额"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 3. 会议与活动日程时间顺延

    private static func tryParseSchedule(scanText: String, fullText: String, itemID: Int64) -> InteractiveSession? {
        let timeRangeRegex = try? NSRegularExpression(
            pattern: #"(?m)([0-2]?\d:[0-5]\d)(\s*[–\-~至到]\s*)([0-2]?\d:[0-5]\d)\s*([^（\(\n\r]+?)(?:\s*[（\(](\d+)\s*分钟[）\)])?\s*(?=$|[\n\r])"#
        )
        guard let regex = timeRangeRegex else { return nil }

        let nsRange = NSRange(scanText.startIndex..., in: scanText)
        let matches = regex.matches(in: scanText, range: nsRange)
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
            let separatorStr: String
            let originalEndStr: String
            let isFixed: Bool
        }

        var segments: [ScheduleSegment] = []

        for match in matches {
            guard let sRange = Range(match.range(at: 1), in: scanText),
                  let sepRange = Range(match.range(at: 2), in: scanText),
                  let eRange = Range(match.range(at: 3), in: scanText),
                  let nRange = Range(match.range(at: 4), in: scanText) else { continue }

            let sStr = String(scanText[sRange])
            let sepStr = String(scanText[sepRange])
            let eStr = String(scanText[eRange])
            let name = String(scanText[nRange]).trimmingCharacters(in: .whitespaces)

            guard let sMins = parseTimeMinutes(sStr),
                  let eMins = parseTimeMinutes(eStr) else { continue }

            var dur = eMins - sMins
            if dur <= 0 { dur += 24 * 60 } // 跨午夜

            if match.range(at: 5).location != NSNotFound,
               let dRange = Range(match.range(at: 5), in: scanText),
               let parsedDur = Int(scanText[dRange]) {
                dur = parsedDur
            }

            if sMins < earliestTotalMinutes {
                earliestTotalMinutes = sMins
                earliestStartHour = sMins / 60
                earliestStartMinute = sMins % 60
            }

            let isFixed = name.contains("固定") || name.contains("不可改") || name.contains("已定") || name.contains("预约")

            segments.append(ScheduleSegment(
                startMinutes: sMins,
                endMinutes: eMins,
                name: name,
                duration: dur,
                originalStartStr: sStr,
                separatorStr: sepStr,
                originalEndStr: eStr,
                isFixed: isFixed
            ))
        }

        guard !segments.isEmpty else { return nil }

        for seg in segments {
            let offset = seg.startMinutes - earliestTotalMinutes
            let sep = seg.separatorStr
            let exactFrag = "\(seg.originalStartStr)\(sep)\(seg.originalEndStr)"
            let dep = DependentBinding(
                name: seg.name,
                originalFragment: exactFrag,
                baseNumber: Double(seg.startMinutes),
                originalLiteral: exactFrag,
                unit: "",
                isFixed: seg.isFixed,
                isFixedInText: seg.isFixed,
                isLocked: false,
                rule: .timeOffset(offsetMinutes: offset, baseTimeVariableId: "start_time", durationMinutes: seg.duration),
                textLocations: [
                    exactFrag,
                    "\(seg.originalStartStr)–\(seg.originalEndStr)",
                    "\(seg.originalStartStr)-\(seg.originalEndStr)",
                    "\(seg.originalStartStr) - \(seg.originalEndStr)"
                ]
            )
            dependents.append(dep)
        }

        let startVar = InteractiveVariable(
            id: "start_time",
            name: "开始时间",
            kind: .time(stepMinutes: 15),
            baseValue: .time(hour: earliestStartHour, minute: earliestStartMinute),
            currentValue: .time(hour: earliestStartHour, minute: earliestStartMinute),
            isPrimary: true
        )

        var variables = [startVar]
        // 检测休息时长变量
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
            originalText: fullText,
            patternType: .schedule,
            variables: variables,
            dependents: dependents,
            conflicts: [],
            adjustedText: fullText,
            changeSummary: "整体顺延 \(segments.count) 个环节，保持各环节时长"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 4. 差旅行程与日期推算

    private static func tryParseItinerary(scanText: String, fullText: String, itemID: Int64) -> InteractiveSession? {
        let baseDatePat = #"(?i)(?:出发日期|开始日期|出发时间|出行日期)\s*[:：]?\s*(\d{4})([-/年])(\d{1,2})([-/月])(\d{1,2})日?"#
        guard let bRegex = try? NSRegularExpression(pattern: baseDatePat),
              let bMatch = bRegex.firstMatch(in: scanText, range: NSRange(scanText.startIndex..., in: scanText)),
              let yRange = Range(bMatch.range(at: 1), in: scanText),
              let sep1Range = Range(bMatch.range(at: 2), in: scanText),
              let mRange = Range(bMatch.range(at: 3), in: scanText),
              let sep2Range = Range(bMatch.range(at: 4), in: scanText),
              let dRange = Range(bMatch.range(at: 5), in: scanText),
              let year = Int(scanText[yRange]),
              let month = Int(scanText[mRange]),
              let day = Int(scanText[dRange]) else { return nil }

        let sep1 = String(scanText[sep1Range])
        let sep2 = String(scanText[sep2Range])
        let dateDelimiter = (sep1 == "/" || sep2 == "/") ? "/" : (sep1 == "-" ? "-" : "年")

        let dayRegex = try? NSRegularExpression(
            pattern: #"(?i)(?:第\s*(\d+)\s*天|D(\d+))\s*([（\(].*?[）\)])?\s*[:：]?\s*([^\n\r]+)"#
        )
        guard let dRegex = dayRegex else { return nil }

        let matches = dRegex.matches(in: scanText, range: NSRange(scanText.startIndex..., in: scanText))
        guard matches.count >= 2 else { return nil }

        var dependents: [DependentBinding] = []

        for match in matches {
            let dayNumStr = Range(match.range(at: 1), in: scanText).map { String(scanText[$0]) }
                ?? Range(match.range(at: 2), in: scanText).map { String(scanText[$0]) } ?? "1"
            guard let dayOffset = Int(dayNumStr) else { continue }

            let titleRange = Range(match.range(at: 4), in: scanText)
            let title = titleRange.map { String(scanText[$0]) } ?? "日程"

            let isFixed = title.contains("固定") || title.contains("不可改")

            var locations: [String] = []
            if let fullRange = Range(match.range, in: scanText) {
                locations.append(String(scanText[fullRange]))
            }

            let dep = DependentBinding(
                name: "D\(dayOffset) \(title.prefix(8))",
                originalFragment: "D\(dayOffset)",
                baseNumber: Double(dayOffset - 1),
                originalLiteral: dateDelimiter, // 借用保存日期原始分隔符
                unit: "天",
                isFixed: isFixed,
                isFixedInText: isFixed,
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
            originalText: fullText,
            patternType: .itinerary,
            variables: [dateVar],
            dependents: dependents,
            conflicts: [],
            adjustedText: fullText,
            changeSummary: "顺延可移动日程，自动重算日期与星期"
        )

        recalculate(session: &session)
        return session
    }

    // MARK: - 5. 普通会议纪要与文本独立变焦 (无需数值控件)

    private static func tryParseGeneralZoom(scanText: String, fullText: String, itemID: Int64) -> InteractiveSession? {
        let lines = scanText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count >= 2, scanText.count >= 15 else { return nil }

        // 识别典型的纪要、便签、备忘特征
        let keywords = ["会议", "讨论", "记录", "建议", "决定", "反馈", "调研", "开发", "小王", "团队", "客户", "TODO", "todo", "项目", "安排"]
        let hasStructure = lines.contains { line in
            keywords.contains { line.contains($0) } || line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("1.")
        }

        guard hasStructure else { return nil }

        var session = InteractiveSession(
            itemID: itemID,
            originalText: fullText,
            patternType: .general,
            variables: [],
            dependents: [],
            conflicts: [],
            adjustedText: fullText,
            changeSummary: "文本已就绪，支持 4 档粘贴变焦"
        )

        session.zoomLevels = generateZoomLevels(text: fullText, session: session)
        return session
    }

    // MARK: - 6. 核心联动重算 (Recalculate & Replace)

    /// 当用户调整变量值或切换单项锁定时，重算所有依赖项并生成新文本
    public static func recalculate(session: inout InteractiveSession) {
        // 关键保障：若存在未解决的缺失基准约束，严禁执行推测性计算，保持原文
        if session.missingConstraint != nil {
            session.adjustedText = session.originalText
            session.zoomLevels = generateZoomLevels(text: session.originalText, session: session)
            return
        }

        // 若会话未经任何修改，调整后文本严格等于完整原文
        if !session.isModified {
            session.adjustedText = session.originalText
            session.zoomLevels = generateZoomLevels(text: session.originalText, session: session)
            return
        }

        var updatedText = session.originalText
        var conflicts = session.conflicts.filter { $0.id == "discount_discrepancy" } // 保留解析期优惠提示
        var updatedCount = 0

        // 1. 执行比例缩放重算
        if let servingsVar = session.variables.first(where: { $0.id == "servings" }) {
            let baseServings = servingsVar.baseValue.asNumber
            let currentServings = servingsVar.currentValue.asNumber
            if baseServings > 0 {
                let ratio = currentServings / baseServings
                var recipeLines = updatedText.components(separatedBy: .newlines)

                for i in 0..<session.dependents.count {
                    let dep = session.dependents[i]
                    let targetNum: Double

                    if dep.isLocked {
                        // 锁定值保护：若首次锁定，冻结当前解算值；后续重算严格以锁定值为准
                        let locked = dep.lockedNumber ?? dep.currentNumber
                        session.dependents[i].lockedNumber = locked
                        session.dependents[i].currentNumber = locked
                        targetNum = locked
                    } else {
                        targetNum = dep.baseNumber * ratio
                        session.dependents[i].currentNumber = targetNum
                    }

                    if floor(targetNum) != targetNum && ["个", "只", "枚", "罐", "包", "瓶"].contains(dep.unit) {
                        let rounded = ceil(targetNum)
                        conflicts.append(InteractiveConflict(
                            id: "rounding_\(dep.id)",
                            message: "\(dep.name) 计算为 \(formatNumber(targetNum)) \(dep.unit)，实际操作建议按整件取整为 \(Int(rounded)) \(dep.unit)",
                            severity: .info
                        ))
                    }

                    let unit = dep.unit
                    let originalLiteral = dep.originalLiteral
                    let newLiteral = formatCalculatedNumber(targetNum, originalLiteral: originalLiteral, ratio: ratio)

                    if originalLiteral != newLiteral {
                        updatedCount += 1
                    }

                    // 精确定向替换：带数字边界 (?<![0-9])，排除同名子串 (如 40克 误伤 140克)；
                    // 同行多项引用时，通过结合食材名 (如 "糖 100 克") 精准定位，不误改同行的锁定项
                    for lineIdx in 0..<recipeLines.count {
                        let line = recipeLines[lineIdx]
                        if line.contains("不参与") { continue }

                        if line.contains(dep.name) {
                            var modifiedLine = line
                            let escapedName = NSRegularExpression.escapedPattern(for: dep.name)
                            let escapedLit = NSRegularExpression.escapedPattern(for: originalLiteral)
                            let escapedBase = NSRegularExpression.escapedPattern(for: formatNumber(dep.baseNumber))
                            let escapedUnit = NSRegularExpression.escapedPattern(for: unit)

                            // 1. 食材名在前：糖 100 克 / 糖: 100克
                            let pat1 = "(\(escapedName)[\\s:：]*)(?<![0-9])(\(escapedLit)|\(escapedBase))(\\s*\(escapedUnit))"
                            if let regex1 = try? NSRegularExpression(pattern: pat1) {
                                let range = NSRange(modifiedLine.startIndex..., in: modifiedLine)
                                modifiedLine = regex1.stringByReplacingMatches(in: modifiedLine, range: range, withTemplate: "$1\(newLiteral)$3")
                            }

                            // 2. 食材名在后：200 毫升牛奶 / 2 个鸡蛋 / 打散的 2 个鸡蛋
                            if modifiedLine == line {
                                let pat2 = "(?<![0-9])(\(escapedLit)|\(escapedBase))(\\s*\(escapedUnit)[\\s:：]*(?:的|之)?[^，。；\\n]{0,4}\(escapedName))"
                                if let regex2 = try? NSRegularExpression(pattern: pat2) {
                                    let range = NSRange(modifiedLine.startIndex..., in: modifiedLine)
                                    modifiedLine = regex2.stringByReplacingMatches(in: modifiedLine, range: range, withTemplate: "\(newLiteral)$2")
                                }
                            }

                            // 3. 兜底一般独立行
                            if modifiedLine == line {
                                let fallbackPat = "(?<![0-9])(\(escapedLit)|\(escapedBase))(\\s*\(escapedUnit))"
                                if let fbRegex = try? NSRegularExpression(pattern: fallbackPat) {
                                    let range = NSRange(modifiedLine.startIndex..., in: modifiedLine)
                                    modifiedLine = fbRegex.stringByReplacingMatches(in: modifiedLine, range: range, withTemplate: "\(newLiteral)$2")
                                }
                            }
                            recipeLines[lineIdx] = modifiedLine
                        }
                    }
                }
                updatedText = recipeLines.joined(separator: "\n")

                // 更新标题/正文主份数
                let baseInt = Int(baseServings)
                let currInt = Int(currentServings)
                let unit = servingsVar.unit
                let baseServingsPatterns = [
                    "\(baseInt)\(unit)份", "\(baseInt) \(unit)份",
                    "\(baseInt)\(unit)", "\(baseInt) \(unit)",
                    "\(numberToChinese(baseInt))\(unit)份",
                    "\(numberToChinese(baseInt))\(unit)"
                ]
                for pat in baseServingsPatterns {
                    let patWithBoundary = "(?<![0-9])" + NSRegularExpression.escapedPattern(for: pat)
                    if let regex = try? NSRegularExpression(pattern: patWithBoundary) {
                        let range = NSRange(updatedText.startIndex..., in: updatedText)
                        let repl = "\(currInt)\(unit)" + (pat.contains("份") && !unit.contains("份") ? "份" : "")
                        let newText = regex.stringByReplacingMatches(in: updatedText, range: range, withTemplate: repl)
                        if newText != updatedText {
                            updatedText = newText
                            break
                        }
                    }
                }
                session.changeSummary = "已更新用量，锁定项与非缩放项保持原值"
            }
        }

        // 2. 执行物料与清单线性计算重算
        if let qVar = session.variables.first(where: { $0.id == "quantity" }) {
            let baseQ = qVar.baseValue.asNumber
            let currQ = qVar.currentValue.asNumber

            var bomLines = updatedText.components(separatedBy: .newlines)
            for i in 0..<session.dependents.count {
                if case .linearCalculation(let unitPrice, _, let fixedCost) = session.dependents[i].rule {
                    let newTot = unitPrice * currQ + fixedCost
                    session.dependents[i].currentNumber = newTot

                    let cur = session.dependents[i].currency ?? "元"
                    let baseTotStr = formatNumber(session.dependents[i].baseNumber)
                    let newTotStr = formatNumber(newTot)

                    // 关键保护：仅在包含「总计|总额|合计|共计」的相关行内定向替换总额，绝对不误伤无关备注行
                    for lineIdx in 0..<bomLines.count {
                        let line = bomLines[lineIdx]
                        if line.contains("总") || line.contains("合计") || line.contains("共计") {
                            var uLine = line
                            let pat = "(?<![0-9])" + NSRegularExpression.escapedPattern(for: baseTotStr) + "(\\s*" + NSRegularExpression.escapedPattern(for: cur) + ")?"
                            if let regex = try? NSRegularExpression(pattern: pat) {
                                let range = NSRange(uLine.startIndex..., in: uLine)
                                uLine = regex.stringByReplacingMatches(in: uLine, range: range, withTemplate: "\(newTotStr)$1")
                            }
                            bomLines[lineIdx] = uLine
                        }
                    }
                }
            }

            // 更新数量字面量
            let baseQStr = formatNumber(baseQ)
            let currQStr = formatNumber(currQ)
            let qUnit = qVar.unit
            for lineIdx in 0..<bomLines.count {
                let line = bomLines[lineIdx]
                if line.contains("数量") || line.contains("件数") || line.contains("订购") {
                    let pat = "(?<![0-9])" + NSRegularExpression.escapedPattern(for: baseQStr) + "(\\s*" + NSRegularExpression.escapedPattern(for: qUnit) + ")"
                    if let regex = try? NSRegularExpression(pattern: pat) {
                        let range = NSRange(line.startIndex..., in: line)
                        bomLines[lineIdx] = regex.stringByReplacingMatches(in: line, range: range, withTemplate: "\(currQStr)$1")
                    }
                }
            }
            updatedText = bomLines.joined(separator: "\n")
        }

        // 3. 执行会议排期时间顺延重算
        if let startVar = session.variables.first(where: { $0.id == "start_time" }),
           case .time(let newH, let newM) = startVar.currentValue,
           case .time(let baseH, let baseM) = startVar.baseValue {

            let baseStartMins = baseH * 60 + baseM
            let newStartMins = newH * 60 + newM

            let breakDeltaMinutes: Int
            if let breakVar = session.variables.last(where: { $0.id == "break_duration" }),
               case .durationMinutes(let currB) = breakVar.currentValue,
               case .durationMinutes(let baseB) = breakVar.baseValue {
                breakDeltaMinutes = currB - baseB
            } else {
                breakDeltaMinutes = 0
            }

            var latestEndMinutes = 0
            var schedLines = updatedText.components(separatedBy: .newlines)
            var hasPassedBreak = false
            var fixedSegments: [(name: String, startMins: Int, endMins: Int)] = []
            var movedSegments: [(name: String, startMins: Int, endMins: Int)] = []

            for i in 0..<session.dependents.count {
                guard case .timeOffset(let offset, _, let duration) = session.dependents[i].rule else { continue }

                let isFixed = session.dependents[i].isFixed || session.dependents[i].isFixedInText
                let depName = session.dependents[i].name
                let isBreak = depName.contains("休息") || depName.contains("茶歇")

                let effectiveDuration = isBreak ? (duration + breakDeltaMinutes) : duration
                let additionalBreakOffset = (hasPassedBreak && !isBreak) ? breakDeltaMinutes : 0
                if isBreak { hasPassedBreak = true }

                let itemStartMins: Int
                let itemEndMins: Int

                if isFixed {
                    // 固定日程严格保持原时间不变
                    itemStartMins = (baseStartMins + offset) % (24 * 60)
                    itemEndMins = (itemStartMins + duration) % (24 * 60)
                    fixedSegments.append((depName, itemStartMins, itemEndMins))
                } else {
                    itemStartMins = (newStartMins + offset + additionalBreakOffset) % (24 * 60)
                    itemEndMins = (itemStartMins + effectiveDuration) % (24 * 60)
                    movedSegments.append((depName, itemStartMins, itemEndMins))
                }

                let oldStartMins = (baseStartMins + offset) % (24 * 60)
                let oldEndMins = (oldStartMins + duration) % (24 * 60)

                let newStartStr = String(format: "%02d:%02d", itemStartMins / 60, itemStartMins % 60)
                let newEndStr = String(format: "%02d:%02d", itemEndMins / 60, itemEndMins % 60)

                // 跨午夜次日标记
                let isCrossMidnight = (newStartMins + offset + additionalBreakOffset + effectiveDuration) >= 24 * 60 && itemEndMins < itemStartMins
                let nextDayTag = isCrossMidnight ? " (次日)" : ""

                let oldStart2 = String(format: "%02d:%02d", oldStartMins / 60, oldStartMins % 60)
                let oldEnd2 = String(format: "%02d:%02d", oldEndMins / 60, oldEndMins % 60)
                let oldStart1 = String(format: "%d:%02d", oldStartMins / 60, oldStartMins % 60)
                let oldEnd1 = String(format: "%d:%02d", oldEndMins / 60, oldEndMins % 60)

                // 行内替换
                if !isFixed {
                    for lineIdx in 0..<schedLines.count {
                        let line = schedLines[lineIdx]
                        if line.contains(depName) {
                            let pat = #"([0-2]?\d:[0-5]\d)(\s*[–\-~至到]\s*)([0-2]?\d:[0-5]\d)"#
                            if let reg = try? NSRegularExpression(pattern: pat),
                               let match = reg.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                               let r1 = Range(match.range(at: 1), in: line),
                               let rSep = Range(match.range(at: 2), in: line),
                               let r2 = Range(match.range(at: 3), in: line) {
                                let matchS = String(line[r1])
                                let matchSep = String(line[rSep])
                                let matchE = String(line[r2])

                                if (matchS == oldStart2 || matchS == oldStart1) && (matchE == oldEnd2 || matchE == oldEnd1) {
                                    let oldFrag = matchS + matchSep + matchE
                                    let newFrag = newStartStr + matchSep + newEndStr + nextDayTag
                                    schedLines[lineIdx] = line.replacingOccurrences(of: oldFrag, with: newFrag)
                                    updatedCount += 1
                                    break
                                }
                            }
                        }
                    }
                }

                if itemEndMins > latestEndMinutes {
                    latestEndMinutes = itemEndMins
                }
            }
            updatedText = schedLines.joined(separator: "\n")

            // 固定日程与移动日程的重叠冲突检查
            for fixed in fixedSegments {
                for moved in movedSegments {
                    if max(fixed.startMins, moved.startMins) < min(fixed.endMins, moved.endMins) {
                        let overlapMins = min(fixed.endMins, moved.endMins) - max(fixed.startMins, moved.startMins)
                        conflicts.append(InteractiveConflict(
                            id: "fixed_schedule_overlap",
                            message: "调整后日程（\(moved.name)）与固定事项（\(fixed.name)）重叠 \(overlapMins) 分钟",
                            severity: .warning
                        ))
                    }
                }
            }

            // 固定截止时间冲突检测
            let deadlinePatterns = [
                #"(?i)(?:必须在|最晚|需在|截止时间|截止|ddl|deadline)\s*[:：]?\s*([0-2]?\d:[0-5]\d)"#,
                #"(?i)([0-2]?\d:[0-5]\d)\s*(?:前结束|结束|清场|前离场|前完成)"#
            ]
            for pat in deadlinePatterns {
                if let dRegex = try? NSRegularExpression(pattern: pat),
                   let match = dRegex.firstMatch(in: session.originalText, range: NSRange(session.originalText.startIndex..., in: session.originalText)),
                   match.numberOfRanges > 1,
                   match.range(at: 1).location != NSNotFound,
                   let r = Range(match.range(at: 1), in: session.originalText),
                   let deadMins = parseTimeMinutes(String(session.originalText[r])) {
                    if latestEndMinutes > deadMins {
                        let overtime = latestEndMinutes - deadMins
                        conflicts.append(InteractiveConflict(
                            id: "schedule_overtime",
                            message: "截止时间为 \(String(session.originalText[r]))，调整后日程已超时 \(overtime) 分钟",
                            severity: .warning
                        ))
                    }
                    break
                }
            }
        }

        // 4. 执行差旅行程日期偏移重算
        if let dateVar = session.variables.first(where: { $0.id == "start_date" }),
           case .date(let newY, let newM, let newD) = dateVar.currentValue,
           case .date(let baseY, let baseM, let baseD) = dateVar.baseValue {

            let calendar = Calendar.current
            let baseComps = DateComponents(year: baseY, month: baseM, day: baseD)
            let newComps = DateComponents(year: newY, month: newM, day: newD)
            if let baseDate = calendar.date(from: baseComps),
               let newDate = calendar.date(from: newComps) {

                var itinLines = updatedText.components(separatedBy: .newlines)

                // 替换基准出发日期（保持原格式，支持 2026/10/01、2026-10-01、2026年10月1日）
                let oldSlash = String(format: "%04d/%02d/%02d", baseY, baseM, baseD)
                let newSlash = String(format: "%04d/%02d/%02d", newY, newM, newD)
                let oldDash = String(format: "%04d-%02d-%02d", baseY, baseM, baseD)
                let newDash = String(format: "%04d-%02d-%02d", newY, newM, newD)
                let oldCn = String(format: "%d月%d日", baseM, baseD)
                let newCn = String(format: "%d月%d日", newM, newD)

                for lineIdx in 0..<itinLines.count {
                    let line = itinLines[lineIdx]
                    if line.contains("出发") || line.contains("开始") || line.contains("出行") {
                        var uLine = line
                        if uLine.contains(oldSlash) { uLine = uLine.replacingOccurrences(of: oldSlash, with: newSlash) }
                        if uLine.contains(oldDash) { uLine = uLine.replacingOccurrences(of: oldDash, with: newDash) }
                        if uLine.contains(oldCn) { uLine = uLine.replacingOccurrences(of: oldCn, with: newCn) }
                        itinLines[lineIdx] = uLine
                    }
                }

                // 顺延并推导各天日程
                for i in 0..<session.dependents.count {
                    let dep = session.dependents[i]
                    guard case .dateOffset(let offsetDays, _) = dep.rule else { continue }
                    let isFixed = dep.isFixed || dep.isFixedInText

                    if let oldItemDate = calendar.date(byAdding: .day, value: offsetDays, to: baseDate),
                       let newItemDate = calendar.date(byAdding: .day, value: offsetDays, to: newDate) {

                        let oldM = calendar.component(.month, from: oldItemDate)
                        let oldD = calendar.component(.day, from: oldItemDate)
                        let oldW = weekdayName(calendar.component(.weekday, from: oldItemDate))

                        let newM = calendar.component(.month, from: newItemDate)
                        let newD = calendar.component(.day, from: newItemDate)
                        let newW = weekdayName(calendar.component(.weekday, from: newItemDate))

                        let dayKey1 = "第 \(offsetDays + 1) 天"
                        let dayKey2 = "第\(offsetDays + 1)天"
                        let dayKey3 = "D\(offsetDays + 1)"

                        for lineIdx in 0..<itinLines.count {
                            let line = itinLines[lineIdx]
                            if line.contains(dayKey1) || line.contains(dayKey2) || line.contains(dayKey3) {
                                if isFixed {
                                    // 固定门票/事项：日期不顺延，但检查是否脱离出发日
                                    if oldItemDate < newDate {
                                        conflicts.append(InteractiveConflict(
                                            id: "fixed_date_before_start",
                                            message: "固定事项（\(oldM)月\(oldD)日）早于出发日期（\(newM)月\(newD)日），存在行程倒置冲突",
                                            severity: .warning
                                        ))
                                    }
                                } else {
                                    var uLine = line
                                    let oldPart1 = "\(oldM)月\(oldD)日 \(oldW)"
                                    let oldPart2 = "\(oldM)月\(oldD)日\(oldW)"
                                    let oldPart3 = "\(oldM)月\(oldD)日"
                                    let newPart = "\(newM)月\(newD)日 \(newW)"

                                    if uLine.contains(oldPart1) {
                                        uLine = uLine.replacingOccurrences(of: oldPart1, with: newPart)
                                    } else if uLine.contains(oldPart2) {
                                        uLine = uLine.replacingOccurrences(of: oldPart2, with: newPart)
                                    } else if uLine.contains(oldPart3) {
                                        uLine = uLine.replacingOccurrences(of: oldPart3, with: "\(newM)月\(newD)日")
                                    } else {
                                        // 纯相对日序（原文无日期）：生成具体推导日期与星期
                                        let pat = "(第\\s*" + "\(offsetDays + 1)" + "\\s*天|D" + "\(offsetDays + 1)" + ")(?![0-9])"
                                        if let reg = try? NSRegularExpression(pattern: pat) {
                                            let range = NSRange(uLine.startIndex..., in: uLine)
                                            uLine = reg.stringByReplacingMatches(in: uLine, range: range, withTemplate: "$1 (\(newPart))")
                                        }
                                    }
                                    itinLines[lineIdx] = uLine
                                }
                            }
                        }
                    }
                }
                updatedText = itinLines.joined(separator: "\n")
            }
        }

        session.conflicts = conflicts
        session.adjustedText = updatedText
        session.zoomLevels = generateZoomLevels(text: updatedText, session: session)
    }

    // MARK: - 7. 粘贴变焦多层级生成 (Paste Zoom)

    public static func generateZoomLevels(text: String, session: InteractiveSession) -> [ZoomLevel: String] {
        var levels: [ZoomLevel: String] = [:]
        levels[.full] = text

        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // 未解决警告摘要（关键保证：简短输出绝不隐匿未决冲突）
        let conflictTag: String
        if let topWarning = session.conflicts.first(where: { $0.severity == .warning }) {
            conflictTag = " [⚠️ \(topWarning.message)]"
        } else {
            conflictTag = ""
        }

        switch session.patternType {
        case .recipe:
            let ingredients = session.dependents.map { dep -> String in
                let val = dep.isLocked ? (dep.lockedNumber ?? dep.currentNumber) : dep.currentNumber
                return "• \(dep.name)：\(formatNumber(val)) \(dep.unit)"
            }
            levels[.keyPoints] = ingredients.joined(separator: "\n")

            let steps = lines.filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t.contains("步骤") || t.contains("1.") || t.contains("2.") || t.contains("3.") || t.contains("制作")
            }
            levels[.actionItems] = steps.isEmpty ? ingredients.joined(separator: "\n") : steps.joined(separator: "\n")

            if let servingsVar = session.primaryVariable {
                let serv = servingsVar.currentValue.displayText
                let topIngs = session.dependents.prefix(3).map {
                    let val = $0.isLocked ? ($0.lockedNumber ?? $0.currentNumber) : $0.currentNumber
                    return "\($0.name)\(formatNumber(val))\($0.unit)"
                }.joined(separator: "、")
                let unitPrefix = (servingsVar.unit == "人" || servingsVar.unit == "份") ? "\(serv)人份" : "\(serv)\(servingsVar.unit)"
                levels[.oneLine] = "\(unitPrefix)配方：\(topIngs)\(conflictTag)"
            } else {
                levels[.oneLine] = (lines.first ?? text) + conflictTag
            }

        case .schedule:
            levels[.keyPoints] = lines.filter { $0.contains(":") || $0.contains("–") || $0.contains("-") }.joined(separator: "\n")
            levels[.actionItems] = session.dependents.map { "• \($0.name)" }.joined(separator: "\n")

            if let startVar = session.primaryVariable {
                levels[.oneLine] = "日程安排：\(startVar.currentValue.displayText) 开始，共 \(session.dependents.count) 个环节\(conflictTag)"
            } else {
                levels[.oneLine] = (lines.first ?? text) + conflictTag
            }

        case .itinerary:
            levels[.keyPoints] = lines.filter { $0.contains("第") || $0.contains("D") }.joined(separator: "\n")
            levels[.actionItems] = levels[.keyPoints]

            if let dateVar = session.primaryVariable {
                levels[.oneLine] = "行程安排：\(dateVar.currentValue.displayText) 出发，全程 \(session.dependents.count) 天\(conflictTag)"
            } else {
                levels[.oneLine] = (lines.first ?? text) + conflictTag
            }

        case .bomCalculation:
            levels[.keyPoints] = lines.prefix(4).joined(separator: "\n")
            levels[.actionItems] = lines.filter { $0.contains("总") || $0.contains("合计") }.joined(separator: "\n")
            levels[.oneLine] = (lines.first ?? text) + conflictTag

        case .general:
            // 适用于普通会议记录、技术讨论、备忘录
            // 核心要点：保留关键建议、决议与否定条件
            let keyLines = lines.filter { line in
                line.contains("希望") || line.contains("建议") || line.contains("决定") || line.contains("调研") || line.contains("计划") || line.contains("反馈") || line.contains("•") || line.contains("-")
            }
            levels[.keyPoints] = keyLines.isEmpty ? lines.prefix(3).joined(separator: "\n") : keyLines.joined(separator: "\n")

            // 结论清单：提取行动项（TODO、专人分工、下步任务）
            let actionLines = lines.filter { line in
                line.contains("整理") || line.contains("负责") || line.contains("周") || line.contains("完成") || line.contains("提交") || line.contains("TODO")
            }
            levels[.actionItems] = actionLines.isEmpty ? (keyLines.isEmpty ? lines.joined(separator: "\n") : keyLines.joined(separator: "\n")) : actionLines.joined(separator: "\n")

            levels[.oneLine] = (lines.first ?? text) + conflictTag
        }

        return levels
    }

    // MARK: - 辅助计算函数

    public static func formatNumber(_ num: Double) -> String {
        if floor(num) == num {
            return String(format: "%.0f", num)
        } else {
            // 采用最多 4 位有效小数的高精度输出，杜绝 0.125 被截断为 0.13
            let str = String(format: "%.4f", num)
            var trimmed = str
            while trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            if trimmed.hasSuffix(".") {
                trimmed.removeLast()
            }
            return trimmed
        }
    }

    private static func formatCalculatedNumber(_ targetNum: Double, originalLiteral: String, ratio: Double) -> String {
        // 分数换算（如 1/2 杯 翻倍为 1 杯）
        if originalLiteral.contains("/") {
            let parts = originalLiteral.components(separatedBy: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d > 0 {
                let scaledVal = (n / d) * ratio
                if floor(scaledVal) == scaledVal {
                    return "\(Int(scaledVal))"
                } else if abs(scaledVal - 0.5) < 0.001 {
                    return "1/2"
                } else if abs(scaledVal - 0.75) < 0.001 {
                    return "3/4"
                } else if abs(scaledVal - 0.25) < 0.001 {
                    return "1/4"
                }
            }
        }

        // 区间换算（如 2-3 克 翻倍为 4-6 克）
        for delim in ["-", "~", "至", "到"] {
            if originalLiteral.contains(delim) {
                let parts = originalLiteral.components(separatedBy: delim)
                if parts.count == 2, let minVal = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                   let maxVal = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    let newMin = minVal * ratio
                    let newMax = maxVal * ratio
                    return "\(formatNumber(newMin))\(delim)\(formatNumber(newMax))"
                }
            }
        }

        return formatNumber(targetNum)
    }

    private static func parseNumericValue(_ str: String) -> (Double, String)? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)

        // 分数
        if trimmed.contains("/") {
            let parts = trimmed.components(separatedBy: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d > 0 {
                return (n / d, trimmed)
            }
        }

        // 区间
        for delim in ["-", "~", "至", "到"] {
            if trimmed.contains(delim) {
                let parts = trimmed.components(separatedBy: delim)
                if parts.count == 2, let minVal = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                   let maxVal = Double(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return ((minVal + maxVal) / 2.0, trimmed)
                }
            }
        }

        // 浮点数/整数
        if let d = Double(trimmed) {
            return (d, trimmed)
        }

        return nil
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
