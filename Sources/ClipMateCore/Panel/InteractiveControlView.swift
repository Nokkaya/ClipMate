import SwiftUI
import AppKit

/// 紧凑内容控件卡片（嵌入在列表选中行或预览浮层中）
public struct InteractiveControlCard: View {
    @Binding public var session: InteractiveSession
    public let theme: AppTheme
    public let language: AppLanguage
    public var onPaste: () -> Void
    public var onCopy: () -> Void
    public var onReset: () -> Void
    public var onToggleLock: (String) -> Void
    public var onResolveMissing: (Double) -> Void

    @State private var copiedFeedback = false
    @State private var customMissingInput: String = ""
    @State private var editingVariableId: String? = nil
    @State private var editingVariableText: String = ""

    public init(session: Binding<InteractiveSession>,
                theme: AppTheme = .default,
                language: AppLanguage = .system,
                onPaste: @escaping () -> Void,
                onCopy: @escaping () -> Void,
                onReset: @escaping () -> Void,
                onToggleLock: @escaping (String) -> Void,
                onResolveMissing: @escaping (Double) -> Void) {
        self._session = session
        self.theme = theme
        self.language = language
        self.onPaste = onPaste
        self.onCopy = onCopy
        self.onReset = onReset
        self.onToggleLock = onToggleLock
        self.onResolveMissing = onResolveMissing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部：模式类别徽标 + 摘要说明 + 操作按钮
            headerView

            // 缺失信息补充条（例如缺初始份数）
            if let missing = session.missingConstraint {
                missingConstraintView(missing)
            } else {
                // 主控件区域：步进器 / 时间调节
                controlsArea

                // 约束冲突与警告
                if !session.conflicts.isEmpty {
                    conflictsView
                }

                // 差异预览（可切换展开）
                if session.showDiff {
                    diffPreviewView
                }

                // 展开单项锁定与明细列表
                if session.isExpanded {
                    dependentsListView
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.accent.opacity(0.24), lineWidth: 1)
        )
    }

    // MARK: - 头部栏

    private var headerView: some View {
        HStack(spacing: 6) {
            // 模式分类标签
            HStack(spacing: 4) {
                Image(systemName: session.patternType.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(session.patternType.title)
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(theme.accent.opacity(0.18)))
            .foregroundStyle(theme.accent)

            // 变更摘要
            if !session.changeSummary.isEmpty {
                Text(session.changeSummary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // 撤销上一调节 (⌘Z)
            if !session.undoStack.isEmpty {
                Button(action: {
                    if session.undo() {
                        InteractiveControlEngine.recalculate(session: &session)
                    }
                }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("撤销上一调节 (⌘Z)")
            }

            // 重置复原按钮（仅当有修改时展示）
            if session.isModified {
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("恢复基准初始值")
            }

            // 展开/收起明细与锁定
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    session.isExpanded.toggle()
                }
            }) {
                Image(systemName: session.isExpanded ? "chevron.up" : "slider.horizontal.2")
                    .font(.system(size: 9.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(session.isExpanded ? "收起明细" : "展开单项锁定")
        }
    }

    // MARK: - 控件主区域

    private var controlsArea: some View {
        HStack(spacing: 8) {
            // 主变量调节器
            if let primaryVar = session.primaryVariable {
                variableStepper(primaryVar)
            }

            // 次变量调节器（如有）
            if let secondaryVar = session.secondaryVariable {
                variableStepper(secondaryVar)
            }

            Spacer(minLength: 4)

            // 差异对比开关按钮
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    session.showDiff.toggle()
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: session.showDiff ? "eye.slash" : "eye")
                        .font(.system(size: 9))
                    Text(session.showDiff ? "隐藏对比" : "对比")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)

            // 仅复制按钮
            Button(action: {
                onCopy()
                copiedFeedback = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    copiedFeedback = false
                }
            }) {
                HStack(spacing: 3) {
                    Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                    Text(copiedFeedback ? "已复制" : "复制")
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))
                .foregroundStyle(copiedFeedback ? Color.green : Color.primary)
            }
            .buttonStyle(.plain)

            // 粘贴结果按钮（主动作）
            Button(action: onPaste) {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.right.doc.on.clipboard")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("粘贴 ↵")
                        .font(.system(size: 10.5, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.accent))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 单个变量步进器

    @ViewBuilder
    private func variableStepper(_ v: InteractiveVariable) -> some View {
        HStack(spacing: 3) {
            Text(v.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                // 减按钮
                Button(action: { decrementVariable(v.id) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canDecrement(v))

                // 当前值展示（支持直接点击输入）
                if editingVariableId == v.id {
                    TextField("", text: $editingVariableText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .frame(width: 36)
                        .onSubmit {
                            updateVariableDirectly(v.id, text: editingVariableText)
                            editingVariableId = nil
                        }
                } else {
                    Text(v.currentValue.displayText)
                        .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                        .frame(minWidth: 28)
                        .foregroundStyle(v.isModified ? theme.accent : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if case .stepper = v.kind {
                                editingVariableId = v.id
                                editingVariableText = "\(Int(v.currentValue.asNumber))"
                            }
                        }
                        .help("点击可直接手动输入数值")
                }

                // 加按钮
                Button(action: { incrementVariable(v.id) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 8.5, weight: .bold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)))

            if !v.unit.isEmpty {
                Text(v.unit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 缺失信息提示条

    private func missingConstraintView(_ missing: MissingConstraintPrompt) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                Text(missing.prompt)
                    .font(.system(size: 11, weight: .medium))
            }

            HStack(spacing: 6) {
                ForEach(missing.suggestedValues, id: \.self) { val in
                    Button(action: { onResolveMissing(val) }) {
                        Text("\(Int(val)) \(missing.unit)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(theme.accent.opacity(0.15)))
                            .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                }

                // 自定义数值补齐 (IC-22)
                HStack(spacing: 2) {
                    TextField("自定", text: $customMissingInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(width: 36)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                        .onSubmit {
                            if let val = Double(customMissingInput), val > 0 {
                                onResolveMissing(val)
                            }
                        }
                    if let val = Double(customMissingInput), val > 0 {
                        Button(action: { onResolveMissing(val) }) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .padding(3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accent)
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    // MARK: - 冲突提示列表

    private var conflictsView: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(session.conflicts) { c in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: c.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(c.severity == .warning ? Color.orange : Color.blue)
                        .padding(.top, 1)
                    Text(c.message)
                        .font(.system(size: 10))
                        .foregroundStyle(c.severity == .warning ? Color.orange : Color.primary)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 差异预览 (IC-23)

    private var diffPreviewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("改动对比：")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(session.changeSummary)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 3) {
                    let origLines = session.originalText.components(separatedBy: .newlines)
                    let newLines = session.effectiveText.components(separatedBy: .newlines)
                    ForEach(0..<max(origLines.count, newLines.count), id: \.self) { idx in
                        let oLine = idx < origLines.count ? origLines[idx] : nil
                        let nLine = idx < newLines.count ? newLines[idx] : nil
                        if let o = oLine, let n = nLine, o != n {
                            VStack(alignment: .leading, spacing: 1.5) {
                                HStack(alignment: .top, spacing: 4) {
                                    Text("-")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Color.red.opacity(0.55))
                                    Text(o)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .strikethrough(true, color: Color.red.opacity(0.35))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.red.opacity(0.06)))

                                HStack(alignment: .top, spacing: 4) {
                                    Text("+")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(theme.accent)
                                    Text(n)
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                        .foregroundStyle(theme.accent)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 4).fill(theme.accent.opacity(0.08)))
                            }
                            .padding(.vertical, 1)
                        } else if let n = nLine {
                            HStack(alignment: .top, spacing: 4) {
                                Text(" ")
                                    .font(.system(size: 10, design: .monospaced))
                                Text(n)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 0.5)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 140)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - 明细列表与单项锁定

    private var dependentsListView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(Color.primary.opacity(0.08))
            HStack {
                Text("受控项清单（点击 🔒 锁定单个数值不随主参数变化）：")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ForEach(session.dependents) { dep in
                HStack(spacing: 6) {
                    Text(dep.name)
                        .font(.system(size: 10.5))
                        .frame(minWidth: 60, alignment: .leading)

                    Text("\(formatNumber(dep.currentNumber)) \(dep.unit)")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(dep.isLocked ? Color.secondary : theme.accent)

                    if dep.currentNumber != dep.baseNumber {
                        Text("(原 \(formatNumber(dep.baseNumber)) \(dep.unit))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // 单项锁定按钮
                    Button(action: { onToggleLock(dep.id) }) {
                        Image(systemName: dep.isLocked ? "lock.fill" : "lock.open")
                            .font(.system(size: 9.5))
                            .foregroundStyle(dep.isLocked ? Color.orange : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help(dep.isLocked ? "已锁定：调节人数时此项保持原值" : "点击锁定此项数值")
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 步进动作与辅助

    private func canDecrement(_ v: InteractiveVariable) -> Bool {
        switch v.kind {
        case .stepper(let min, _, _, _, _):
            return v.currentValue.asNumber > min
        case .time:
            return true
        case .duration(let min, _):
            return v.currentValue.asNumber > Double(min)
        case .date:
            return true
        }
    }

    private func incrementVariable(_ id: String) {
        guard let idx = session.variables.firstIndex(where: { $0.id == id }) else { return }
        session.pushSnapshot()
        var v = session.variables[idx]
        switch v.kind {
        case .stepper(_, let max, let step, _, _):
            let next = min(max, v.currentValue.asNumber + step)
            v.currentValue = .number(next)
        case .time(let stepMins):
            if case .time(let h, let m) = v.currentValue {
                let total = (h * 60 + m + stepMins) % (24 * 60)
                v.currentValue = .time(hour: total / 60, minute: total % 60)
            }
        case .duration(let stepMins, _):
            if case .durationMinutes(let m) = v.currentValue {
                v.currentValue = .durationMinutes(m + stepMins)
            }
        case .date(let stepDays):
            if case .date(let y, let m, let d) = v.currentValue {
                let cal = Calendar.current
                let comps = DateComponents(year: y, month: m, day: d)
                if let dt = cal.date(from: comps),
                   let nextDt = cal.date(byAdding: .day, value: stepDays, to: dt) {
                    v.currentValue = .date(
                        year: cal.component(.year, from: nextDt),
                        month: cal.component(.month, from: nextDt),
                        day: cal.component(.day, from: nextDt)
                    )
                }
            }
        }
        session.variables[idx] = v
        InteractiveControlEngine.recalculate(session: &session)
    }

    private func decrementVariable(_ id: String) {
        guard let idx = session.variables.firstIndex(where: { $0.id == id }) else { return }
        session.pushSnapshot()
        var v = session.variables[idx]
        switch v.kind {
        case .stepper(let min, _, let step, _, _):
            let next = Swift.max(min, v.currentValue.asNumber - step)
            v.currentValue = .number(next)
        case .time(let stepMins):
            if case .time(let h, let m) = v.currentValue {
                var total = (h * 60 + m - stepMins) % (24 * 60)
                if total < 0 { total += 24 * 60 }
                v.currentValue = .time(hour: total / 60, minute: total % 60)
            }
        case .duration(let stepMins, _):
            if case .durationMinutes(let m) = v.currentValue {
                v.currentValue = .durationMinutes(Swift.max(5, m - stepMins))
            }
        case .date(let stepDays):
            if case .date(let y, let m, let d) = v.currentValue {
                let cal = Calendar.current
                let comps = DateComponents(year: y, month: m, day: d)
                if let dt = cal.date(from: comps),
                   let prevDt = cal.date(byAdding: .day, value: -stepDays, to: dt) {
                    v.currentValue = .date(
                        year: cal.component(.year, from: prevDt),
                        month: cal.component(.month, from: prevDt),
                        day: cal.component(.day, from: prevDt)
                    )
                }
            }
        }
        session.variables[idx] = v
        InteractiveControlEngine.recalculate(session: &session)
    }

    private func updateVariableDirectly(_ id: String, text: String) {
        guard let idx = session.variables.firstIndex(where: { $0.id == id }) else { return }
        if let num = Double(text) {
            session.pushSnapshot()
            session.variables[idx].currentValue = .number(num)
            InteractiveControlEngine.recalculate(session: &session)
        }
    }

    private func formatNumber(_ num: Double) -> String {
        if floor(num) == num {
            return String(format: "%.0f", num)
        } else {
            return String(format: "%.1f", num).replacingOccurrences(of: ".0", with: "")
        }
    }
}

/// 粘贴变焦选择栏（第六阶段）
public struct PasteZoomBar: View {
    @Binding public var currentZoom: ZoomLevel
    public let theme: AppTheme
    public var onLevelChanged: (ZoomLevel) -> Void

    public init(currentZoom: Binding<ZoomLevel>, theme: AppTheme = .default, onLevelChanged: @escaping (ZoomLevel) -> Void) {
        self._currentZoom = currentZoom
        self.theme = theme
        self.onLevelChanged = onLevelChanged
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text("粘贴变焦：")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            ForEach(ZoomLevel.allCases, id: \.self) { level in
                Button(action: {
                    currentZoom = level
                    onLevelChanged(level)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: level.icon)
                            .font(.system(size: 8.5))
                        Text(level.title)
                            .font(.system(size: 10, weight: currentZoom == level ? .semibold : .regular))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(currentZoom == level ? theme.accent.opacity(0.2) : Color.primary.opacity(0.05))
                    )
                    .foregroundStyle(currentZoom == level ? theme.accent : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }
}
