import SwiftUI
import AppKit
import Combine

/// 就地动作处理结果模型（不覆盖原始条目，独立展示与操作）
public struct InlineActionResult: Equatable {
    public let itemID: Int64
    public let actionKind: ContentActionKind
    public var text: String
    public var originalText: String
    public var badge: String?
    public var errorMessage: String?
    public var isStreaming: Bool
    public var showOriginal: Bool
    public var targetLanguage: String?

    public init(itemID: Int64, actionKind: ContentActionKind, text: String, originalText: String,
                badge: String? = nil, errorMessage: String? = nil, isStreaming: Bool = false,
                showOriginal: Bool = false, targetLanguage: String? = nil) {
        self.itemID = itemID
        self.actionKind = actionKind
        self.text = text
        self.originalText = originalText
        self.badge = badge
        self.errorMessage = errorMessage
        self.isStreaming = isStreaming
        self.showOriginal = showOriginal
        self.targetLanguage = targetLanguage
    }
}

/// 主面板状态与动作。所有公开方法约定在主线程调用（SwiftUI/键盘监听/采集回调均在主线程）。
public final class PanelViewModel: ObservableObject {
    @Published public var query = ""
    @Published public var filter: FilterKind = .all
    @Published public var items: [ClipItem] = []
    @Published public var selectedIndex = 0 {
        didSet {
            if items.indices.contains(selectedIndex) {
                selectedID = items[selectedIndex].id
            }
            selectedFieldIndex = nil
            if let act = activeActionResult, act.itemID != selectedID {
                cancelAction()
                activeActionResult = nil
            }
            syncAITargetIfNeeded()
        }
    }
    /// 选中锚点：以条目 id 记录，列表重排（新采集置顶等）后选中不漂移。
    @Published public var selectedID: Int64?
    /// 选中的局部字段索引（键盘焦点）
    @Published public var selectedFieldIndex: Int? = nil
    /// 展开全部字段的条目 ID 集合
    @Published public var expandedFieldItemIDs: Set<Int64> = []
    private var fieldsCache: [Int64: [ExtractedField]] = [:]

    /// 就地动作处理结果（不覆盖原文，支持对比、复制、粘贴）
    @Published public var activeActionResult: InlineActionResult? = nil
    private var actionCache: [Int64: RecommendedAction?] = [:]
    private var actionTask: Task<Void, Never>?

    @Published public var showEditOverlay = false
    @Published public var editText = ""
    @Published public var showConfirmClear = false

    /// 是否展开内置 AI 问答侧边栏
    @Published public var isAISidebarOpen = false
    /// 内置 AI 侧边栏专属状态模型
    public let aiModel: AIWorkspaceModel
    /// 侧边栏展开/收起回调（驱动窗口平滑改变宽度）
    public var onAISidebarToggled: ((Bool) -> Void)?

    // 情境过滤：来源应用 + 时间范围
    @Published public var timeFilter: TimeFilter = .all
    @Published public var sourceFilter: String?
    @Published public var availableSources: [ClipSource] = []

    // 手动重命名（用户自定义标题）
    @Published public var showRenameOverlay = false
    @Published public var renameTargetID: Int64?
    @Published public var renameDraft = ""

    // 片段专用管理状态
    @Published public var showSnippetOverlay = false
    @Published public var snippetTargetID: Int64? = nil
    @Published public var snippetDraftTitle = ""
    @Published public var snippetDraftGroup = ""
    @Published public var snippetDraftShortcode = ""
    @Published public var snippetDraftContent = ""
    @Published public var snippetGroup: String? = nil
    @Published public var availableSnippetGroups: [String] = []

    /// 粘贴队列（会话内有效，按序批量粘贴）。
    @Published public var queue: [ClipItem] = []
    /// 详情预览浮层当前条目。
    @Published public var previewItem: ClipItem?
    /// 批量多选（⇧↑↓ 扩展，存条目 id 以免列表刷新错位）。
    @Published public var multiSelectedIDs: Set<Int64> = []

    public let store: ClipStore
    public let settings: AppSettings
    public let ai: AIService
    let monitor: ClipboardMonitor
    let frontApps: FrontAppTracker

    /// 面板可见期间记录的粘贴目标（唤起前的前台应用）。
    public var pasteTarget: NSRunningApplication?
    var dismiss: (() -> Void)?
    var openSettings: (() -> Void)?

    private var searchTask: Task<Void, Never>?
    private let thumbCache = NSCache<NSNumber, NSImage>()
    private var cancellables = Set<AnyCancellable>()

    public init(store: ClipStore, settings: AppSettings, monitor: ClipboardMonitor,
                frontApps: FrontAppTracker, ai: AIService) {
        self.store = store
        self.settings = settings
        self.monitor = monitor
        self.frontApps = frontApps
        self.ai = ai
        self.aiModel = AIWorkspaceModel(ai: ai, store: store, monitor: monitor, settings: settings)
        self.aiModel.pasteTargetProvider = { [weak self] in self?.pasteTarget }
        self.aiModel.hidePanel = { [weak self] in self?.dismiss?() }

        settings.$appLanguage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        settings.$appTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // 预热加载历史条目，确保面板初次唤起时即开即用零等待
        reload(resetSelection: false)
    }

    // MARK: - 数据

    /// 当前情境过滤（来源应用 + 时间范围）。
    public var contextFilter: ContextFilter {
        ContextFilter(time: timeFilter, sourceBundle: sourceFilter)
    }

    public func reload(resetSelection: Bool = false) {
        let q = query
        let f = filter
        let sg = snippetGroup
        let ctx = contextFilter
        if q.isEmpty {
            searchTask?.cancel()
            searchTask = nil
            let results = store.search(query: q, filter: f, snippetGroup: sg, context: ctx, limit: 300)
            applySearchResults(results, resetSelection: resetSelection)
        } else {
            searchTask?.cancel()
            let store = self.store
            searchTask = Task.detached(priority: .userInitiated) { [weak self] in
                let results = store.search(query: q, filter: f, snippetGroup: sg, context: ctx, limit: 300)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self, self.query == q, self.filter == f, self.snippetGroup == sg,
                          self.contextFilter == ctx else { return }
                    self.applySearchResults(results, resetSelection: resetSelection)
                }
            }
        }
        if filter == .snippet {
            refreshSnippetGroups()
        }
        refreshSources()
    }

    /// 用户在搜索框键入内容时，防抖 100ms 触发异步检索
    public func queryChanged() {
        searchTask?.cancel()
        let q = query
        let f = filter
        let sg = snippetGroup
        let ctx = contextFilter
        if q.isEmpty {
            reload(resetSelection: true)
            return
        }
        let store = self.store
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            let results = store.search(query: q, filter: f, snippetGroup: sg, context: ctx, limit: 300)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.query == q, self.filter == f, self.snippetGroup == sg,
                      self.contextFilter == ctx else { return }
                self.applySearchResults(results, resetSelection: true)
            }
        }
    }

    // MARK: - 情境过滤（来源应用 + 时间范围）

    public func refreshSources() {
        availableSources = store.distinctSources()
    }

    public func setTimeFilter(_ time: TimeFilter) {
        guard timeFilter != time else { return }
        timeFilter = time
        clearMultiSelection()
        reload(resetSelection: true)
        HapticHelper.alignment()
    }

    public func setSourceFilter(_ bundle: String?) {
        guard sourceFilter != bundle else { return }
        sourceFilter = bundle
        clearMultiSelection()
        reload(resetSelection: true)
        HapticHelper.alignment()
    }

    public func clearContextFilter() {
        guard timeFilter != .all || sourceFilter != nil else { return }
        timeFilter = .all
        sourceFilter = nil
        clearMultiSelection()
        reload(resetSelection: true)
        HapticHelper.alignment()
    }

    /// 来源筛选的展示名。
    public var sourceFilterName: String? {
        guard let bundle = sourceFilter else { return nil }
        return availableSources.first { $0.bundle == bundle }?.name ?? bundle
    }

    private func applySearchResults(_ newItems: [ClipItem], resetSelection: Bool = false) {
        items = newItems
        if resetSelection || selectedID == nil {
            selectedIndex = 0
            selectedID = items.first?.id
        } else if let id = selectedID, let index = items.firstIndex(where: { $0.id == id }) {
            selectedIndex = index
        } else if selectedIndex >= items.count {
            selectedIndex = max(0, items.count - 1)
            selectedID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        } else {
            selectedID = items.indices.contains(selectedIndex) ? items[selectedIndex].id : nil
        }
        // 多选只对当前可见列表有意义，清理失效引用
        let visibleIDs = Set(items.map(\.id))
        multiSelectedIDs.formIntersection(visibleIDs)
        syncAITargetIfNeeded()
    }

    public func handleCaptured(_ item: ClipItem) {
        thumbCache.removeObject(forKey: NSNumber(value: item.id))
        fieldsCache.removeValue(forKey: item.id)
        actionCache.removeValue(forKey: item.id)
        reload()
    }

    /// 后台异步识别（OCR/智能标题/链接元数据等）完成后就地更新单条，不重排列表、不改变选中项与按钮位置
    public func handleItemUpdated(_ item: ClipItem) {
        thumbCache.removeObject(forKey: NSNumber(value: item.id))
        fieldsCache.removeValue(forKey: item.id)
        actionCache.removeValue(forKey: item.id)
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
            if selectedID == item.id {
                selectedIndex = index
                syncAITargetIfNeeded()
            }
        }
    }

    public var selectedItem: ClipItem? {
        if let id = selectedID, let item = items.first(where: { $0.id == id }) {
            return item
        }
        return items.indices.contains(selectedIndex) ? items[selectedIndex] : nil
    }

    // MARK: - 选择与过滤

    public func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let nextIndex = min(max(0, selectedIndex + delta), items.count - 1)
        selectedID = items[nextIndex].id
        selectedIndex = nextIndex
    }

    public func cycleFilter() {
        let all = FilterKind.allCases
        guard let index = all.firstIndex(of: filter) else { return }
        changeFilter(all[(index + 1) % all.count])
    }

    /// 切换分类：多选清除，选中重置到首项，刷新列表
    public func changeFilter(_ kind: FilterKind) {
        guard filter != kind else { return }
        filter = kind
        snippetGroup = nil
        clearMultiSelection()
        selectedIndex = 0
        selectedID = nil
        reload(resetSelection: true)
    }

    /// 切换片段子分组（如：开发 / 常用 / 邮件）
    public func changeSnippetGroup(_ group: String?) {
        guard snippetGroup != group else { return }
        snippetGroup = group
        clearMultiSelection()
        selectedIndex = 0
        selectedID = nil
        reload(resetSelection: true)
        HapticHelper.alignment()
    }

    public func refreshSnippetGroups() {
        availableSnippetGroups = store.allSnippetGroups()
    }

    /// 单选语义：点击行 = 只选中这一行，清除批量多选残留。
    public func selectOnly(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
        selectedID = items[index].id
        clearMultiSelection()
    }

    public func selectOnly(item: ClipItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            selectedIndex = index
            selectedID = item.id
            clearMultiSelection()
        }
    }

    // MARK: - 动作

    public func pasteSelected() {
        guard let item = selectedItem else { return }
        paste(item: item)
    }

    /// 忽略富文本格式，按纯文本粘贴/复制。
    public func pasteAsPlainText(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        pasteContent(.text(target.plainText))
    }

    public func copyAsPlainText(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        PasteBack.write(.text(target.plainText))
        monitor.suppress(seconds: 1.5)
    }

    public func paste(item: ClipItem) {
        pasteContent(store.pasteboardContent(for: item))
    }

    public func pasteIndex(_ index: Int) {
        guard items.indices.contains(index) else { return }
        selectOnly(at: index)
        paste(item: items[index])
    }

    private func pasteContent(_ content: PasteboardContent?) {
        guard let content else { return }
        let target = pasteTarget
        dismiss?()
        PasteBack.paste(
            content: content,
            toPID: target?.processIdentifier,
            targetApp: target,
            suppress: { [weak self] seconds in
                self?.monitor.suppress(seconds: seconds)
            },
            onFallback: { [weak self] reason in
                self?.handlePasteFallback(reason)
            }
        )
    }

    public func handlePasteFallback(_ reason: PasteFallbackReason) {
        NSSound(named: "Basso")?.play()
        let title: String
        let subtitle: String
        switch reason {
        case .permissionDenied:
            title = L10n.tr("toast.paste_fallback.permission", lang: settings.appLanguage)
            subtitle = L10n.tr("toast.paste_fallback.permission_hint", lang: settings.appLanguage)
        case .targetUnavailable:
            title = L10n.tr("toast.paste_fallback.target_lost", lang: settings.appLanguage)
            subtitle = L10n.tr("toast.paste_fallback.manual_hint", lang: settings.appLanguage)
        case .pasteFailed:
            title = L10n.tr("toast.paste_fallback.title", lang: settings.appLanguage)
            subtitle = L10n.tr("toast.paste_fallback.manual_hint", lang: settings.appLanguage)
        }
        ToastHUD.shared.show(
            icon: "exclamationmark.triangle.fill",
            title: title,
            subtitle: subtitle,
            duration: 2.8
        )
    }

    public func copySelected() {
        guard let item = selectedItem else { return }
        copy(item: item)
    }

    public func copy(item: ClipItem) {
        guard let content = store.pasteboardContent(for: item) else { return }
        PasteBack.write(content)
        monitor.suppress(seconds: 1.5)
    }

    // MARK: - 局部字段快捷取用

    public func fields(for item: ClipItem) -> [ExtractedField] {
        if let cached = fieldsCache[item.id] { return cached }
        let extracted = ContentExtractor.extractFields(from: item)
        fieldsCache[item.id] = extracted
        return extracted
    }

    public func toggleExpandFields(for itemID: Int64) {
        if expandedFieldItemIDs.contains(itemID) {
            expandedFieldItemIDs.remove(itemID)
        } else {
            expandedFieldItemIDs.insert(itemID)
        }
    }

    public func isFieldsExpanded(for itemID: Int64) -> Bool {
        expandedFieldItemIDs.contains(itemID)
    }

    public func pasteField(_ field: ExtractedField) {
        pasteFieldText(field.value)
    }

    public func pasteFieldText(_ text: String) {
        pasteContent(.text(text))
    }

    public func copyField(_ field: ExtractedField) {
        copyFieldText(field.value)
    }

    public func copyFieldText(_ text: String) {
        PasteBack.write(.text(text))
        monitor.suppress(seconds: 1.5)
        HapticHelper.feedback()
        ToastHUD.shared.show(
            icon: "doc.on.doc.fill",
            title: L10n.tr("action.copied", lang: settings.appLanguage),
            subtitle: text,
            duration: 1.5
        )
    }

    public func pasteField(at index: Int) {
        guard let item = selectedItem else { return }
        let list = fields(for: item)
        guard list.indices.contains(index) else { return }
        pasteField(list[index])
    }

    public func copyField(at index: Int) {
        guard let item = selectedItem else { return }
        let list = fields(for: item)
        guard list.indices.contains(index) else { return }
        copyField(list[index])
    }

    public func moveFieldSelection(_ delta: Int) {
        guard let item = selectedItem else { return }
        let list = fields(for: item)
        guard !list.isEmpty else { return }
        if let current = selectedFieldIndex {
            let next = current + delta
            if next < 0 {
                selectedFieldIndex = nil
            } else {
                selectedFieldIndex = min(next, list.count - 1)
            }
        } else if delta > 0 {
            selectedFieldIndex = 0
        }
    }

    // MARK: - 第三阶段：按内容提供一键处理

    public func recommendedAction(for item: ClipItem) -> RecommendedAction? {
        if let cached = actionCache[item.id] { return cached }
        let action = ContentActionEngine.recommendAction(
            for: item.plainText,
            kind: item.kind,
            tags: item.tags,
            appLanguage: settings.appLanguage
        )
        actionCache[item.id] = action
        return action
    }

    public func executeAction(_ actionKind: ContentActionKind, on item: ClipItem? = nil, targetLanguage: String? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }

        cancelAction()

        switch actionKind {
        case .fixLineBreaks:
            let fixed = ContentActionEngine.fixLineBreaks(target.plainText)
            activeActionResult = InlineActionResult(
                itemID: target.id,
                actionKind: .fixLineBreaks,
                text: fixed,
                originalText: target.plainText,
                badge: L10n.tr("action.diff_breaks_fixed", lang: settings.appLanguage)
            )
            HapticHelper.feedback()

        case .deduplicateList:
            let (result, removedCount) = ContentActionEngine.deduplicateList(target.plainText)
            let badge = String(format: L10n.tr("action.diff_deduped", lang: settings.appLanguage), removedCount)
            activeActionResult = InlineActionResult(
                itemID: target.id,
                actionKind: .deduplicateList,
                text: result,
                originalText: target.plainText,
                badge: badge
            )
            HapticHelper.feedback()

        case .formatJSON:
            let res = ContentActionEngine.formatJSON(target.plainText)
            switch res {
            case .success(let formatted):
                activeActionResult = InlineActionResult(
                    itemID: target.id,
                    actionKind: .formatJSON,
                    text: formatted,
                    originalText: target.plainText,
                    badge: L10n.tr("action.diff_json_formatted", lang: settings.appLanguage)
                )
                HapticHelper.feedback()
            case .failure(let err):
                activeActionResult = InlineActionResult(
                    itemID: target.id,
                    actionKind: .formatJSON,
                    text: "",
                    originalText: target.plainText,
                    errorMessage: err.localizedDescription
                )
                HapticHelper.generic()
            }

        case .translate:
            let targetLang = targetLanguage ?? (settings.appLanguage == .en ? "en" : "zh-Hans")
            let langDisplayName = targetLang == "en" ? "English" : "简体中文"

            guard ai.isConfigured else {
                activeActionResult = InlineActionResult(
                    itemID: target.id,
                    actionKind: .translate,
                    text: "",
                    originalText: target.plainText,
                    errorMessage: L10n.tr("action.need_ai_config", lang: settings.appLanguage),
                    targetLanguage: targetLang
                )
                HapticHelper.generic()
                return
            }

            activeActionResult = InlineActionResult(
                itemID: target.id,
                actionKind: .translate,
                text: "",
                originalText: target.plainText,
                badge: langDisplayName,
                isStreaming: true,
                targetLanguage: targetLang
            )

            let prompt = "请将以下内容翻译为\(langDisplayName)。直接输出纯译文，不要包含任何解释、说明或引言：\n\n\(String(target.plainText.prefix(8000)))"

            actionTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await delta in self.ai.stream(prompt: prompt) {
                        try Task.checkCancellation()
                        guard self.activeActionResult?.itemID == target.id else { return }
                        self.activeActionResult?.text += delta
                    }
                    guard self.activeActionResult?.itemID == target.id else { return }
                    self.activeActionResult?.isStreaming = false
                    HapticHelper.feedback()
                } catch {
                    guard !Task.isCancelled, self.activeActionResult?.itemID == target.id else { return }
                    self.activeActionResult?.isStreaming = false
                    self.activeActionResult?.errorMessage = "翻译失败：\(error.localizedDescription)"
                }
            }
        }
    }

    public func cancelAction() {
        actionTask?.cancel()
        actionTask = nil
        if activeActionResult?.isStreaming == true {
            activeActionResult = nil
        }
    }

    public func retryAction() {
        guard let cur = activeActionResult, let item = selectedItem, cur.itemID == item.id else { return }
        executeAction(cur.actionKind, on: item, targetLanguage: cur.targetLanguage)
    }

    public func toggleActionResultOriginal() {
        activeActionResult?.showOriginal.toggle()
        HapticHelper.alignment()
    }

    public func dismissActionResult() {
        cancelAction()
        activeActionResult = nil
        HapticHelper.alignment()
    }

    public func pasteActionResult() {
        guard let res = activeActionResult, !res.text.isEmpty else { return }
        pasteFieldText(res.text)
    }

    public func copyActionResult() {
        guard let res = activeActionResult, !res.text.isEmpty else { return }
        copyFieldText(res.text)
    }

    public func togglePin(_ item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        try? store.setPinned(target.id, !target.pinned)
        reload()
    }

    public func delete(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        try? store.delete(target.id)
        reload()
    }

    public func beginEdit(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target, target.kind != .image else { return }
        editText = target.plainText
        showEditOverlay = true
    }

    public func saveEdit() {
        guard let target = selectedItem else { return }
        try? store.updateText(target.id, editText)
        showEditOverlay = false
        reload()
        copy(item: store.item(id: target.id) ?? target)
    }

    /// 当前重命名目标条目。
    public var renameTarget: ClipItem? {
        guard let id = renameTargetID else { return nil }
        return items.first { $0.id == id } ?? store.item(id: id)
    }

    /// 打开重命名浮层：预填当前标题。
    public func beginRename(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        guard let target else { return }
        renameTargetID = target.id
        renameDraft = target.title ?? ""
        showRenameOverlay = true
    }

    /// 保存自定义标题（写入 title 列，可被检索命中）。
    public func saveRename() {
        guard let id = renameTargetID else { return }
        try? store.setUserTitle(id, title: renameDraft)
        closeRenameOverlay()
        reload()
        HapticHelper.feedback()
    }

    /// 直接清除自定义标题（右键菜单入口）。
    public func clearTitle(item: ClipItem? = nil) {
        guard let target = item ?? selectedItem else { return }
        try? store.setUserTitle(target.id, title: nil)
        reload()
        HapticHelper.feedback()
    }

    /// 清除自定义标题，恢复自动标题。
    public func clearRename() {
        guard let id = renameTargetID else { return }
        try? store.setUserTitle(id, title: nil)
        closeRenameOverlay()
        reload()
        HapticHelper.feedback()
    }

    private func closeRenameOverlay() {
        showRenameOverlay = false
        renameTargetID = nil
        renameDraft = ""
    }

    public func requestClearAll() {
        showConfirmClear = true
    }

    public func confirmClearAll() {
        try? store.deleteAll(keepPinned: true)
        showConfirmClear = false
        queue.removeAll()
        reload()
    }

    // MARK: - 粘贴队列

    @discardableResult
    public func toggleQueue(item: ClipItem? = nil) -> Bool {
        let target = item ?? selectedItem
        guard let target else { return false }
        if let index = queue.firstIndex(where: { $0.id == target.id }) {
            queue.remove(at: index)
            return false
        }
        guard queue.count < 9 else { return false }
        queue.append(target)
        return true
    }

    public func clearQueue() {
        queue.removeAll()
    }

    /// 顺序粘贴队列内容，完成后清空队列。
    public func pasteQueue() {
        guard !queue.isEmpty else { return }
        let contents = queue.compactMap { store.pasteboardContent(for: $0) }
        let target = pasteTarget
        queue.removeAll()
        dismiss?()
        guard !contents.isEmpty else { return }
        PasteBack.pasteSequence(
            contents: contents,
            toPID: target?.processIdentifier,
            targetApp: target,
            suppress: { [weak self] seconds in
                self?.monitor.suppress(seconds: seconds)
            },
            onFallback: { [weak self] reason in
                self?.handlePasteFallback(reason)
            }
        )
    }

    // MARK: - 详情预览

    public func togglePreview(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        if previewItem != nil, target == nil || target?.id == previewItem?.id {
            previewItem = nil
        } else if let target {
            previewItem = target
        }
    }

    // MARK: - 批量多选

    /// 全选当前视图下的所有可见条目
    public func selectAllVisible() {
        guard !items.isEmpty else { return }
        multiSelectedIDs = Set(items.map(\.id))
    }

    /// ⇧↑/⇧↓ 扩展多选（从当前选中行起）。
    public func extendSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        if multiSelectedIDs.isEmpty, items.indices.contains(selectedIndex) {
            multiSelectedIDs.insert(items[selectedIndex].id)
        }
        let next = min(max(0, selectedIndex + delta), items.count - 1)
        selectedIndex = next
        selectedID = items[next].id
        multiSelectedIDs.insert(items[next].id)
    }

    public func clearMultiSelection() {
        multiSelectedIDs.removeAll()
    }

    /// 批量合并复制选中的条目（默认换行分隔）
    public func copyMulti(separator: String = "\n") {
        guard !multiSelectedIDs.isEmpty else { return }
        let selected = items.filter { multiSelectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        let merged = selected.map(\.plainText).filter { !$0.isEmpty }.joined(separator: separator)
        guard !merged.isEmpty else { return }
        PasteBack.write(.text(merged))
        monitor.suppress(seconds: 1.5)
        multiSelectedIDs.removeAll()
    }

    /// 批量固定 / 取消固定
    public func togglePinMulti() {
        guard !multiSelectedIDs.isEmpty else { return }
        let selected = items.filter { multiSelectedIDs.contains($0.id) }
        let allPinned = selected.allSatisfy(\.pinned)
        let targetPinned = !allPinned
        for item in selected {
            try? store.setPinned(item.id, targetPinned)
        }
        reload()
    }

    /// 批量加入粘贴队列
    public func enqueueMulti() {
        guard !multiSelectedIDs.isEmpty else { return }
        let selected = items.filter { multiSelectedIDs.contains($0.id) }
        for item in selected {
            if !queue.contains(where: { $0.id == item.id }), queue.count < 9 {
                queue.append(item)
            }
        }
    }

    public func deleteMulti() {
        guard !multiSelectedIDs.isEmpty else { return }
        for id in multiSelectedIDs {
            try? store.delete(id)
        }
        multiSelectedIDs.removeAll()
        reload()
    }

    // MARK: - 片段管理

    @discardableResult
    public func toggleSnippet(item: ClipItem? = nil) -> Bool {
        let target = item ?? selectedItem
        guard let target else { return false }
        let isSnippet = target.tags.contains(FilterKind.snippetTag)
        try? store.mutateTag(target.id, tag: FilterKind.snippetTag, add: !isSnippet)
        refreshSnippetGroups()
        reload()
        HapticHelper.alignment()
        return !isSnippet
    }

    public func openNewSnippet() {
        snippetTargetID = nil
        snippetDraftTitle = ""
        snippetDraftGroup = snippetGroup ?? ""
        snippetDraftShortcode = ""
        snippetDraftContent = ""
        refreshSnippetGroups()
        showSnippetOverlay = true
    }

    public func openEditSnippet(item: ClipItem? = nil) {
        guard let target = item ?? selectedItem else { return }
        snippetTargetID = target.id
        snippetDraftTitle = target.title ?? ""
        snippetDraftGroup = target.snippetGroup ?? ""
        snippetDraftShortcode = target.snippetShortcode ?? ""
        snippetDraftContent = target.plainText
        refreshSnippetGroups()
        showSnippetOverlay = true
    }

    public func saveSnippet() {
        let content = snippetDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        if let id = snippetTargetID {
            _ = try? store.updateSnippet(
                id: id,
                title: snippetDraftTitle,
                group: snippetDraftGroup,
                shortcode: snippetDraftShortcode,
                text: content
            )
        } else {
            _ = try? store.createSnippet(
                title: snippetDraftTitle,
                text: content,
                group: snippetDraftGroup,
                shortcode: snippetDraftShortcode
            )
        }
        showSnippetOverlay = false
        refreshSnippetGroups()
        reload()
        HapticHelper.feedback()
    }

    public func clearTransientState() {
        showEditOverlay = false
        showSnippetOverlay = false
        closeRenameOverlay()
        showConfirmClear = false
        previewItem = nil
        cancelAction()
        activeActionResult = nil
    }

    // MARK: - AI 侧边栏与问答联动

    /// 实时同步当前选中项至 AI 模型上下文
    public func syncAITargetIfNeeded() {
        guard isAISidebarOpen, let item = selectedItem else { return }
        if aiModel.item?.id != item.id {
            aiModel.load(item: item)
        }
    }

    /// 切换 AI 侧边栏展开/收起
    public func toggleAISidebar() {
        isAISidebarOpen.toggle()
        if isAISidebarOpen, let item = selectedItem {
            if aiModel.item?.id != item.id {
                aiModel.load(item: item)
            }
        }
        onAISidebarToggled?(isAISidebarOpen)
        HapticHelper.feedback()
    }

    /// 就地展开 AI 侧边栏并聚焦当前选中条目
    public func openAI(item: ClipItem? = nil) {
        let target = item ?? selectedItem
        if let target, let index = items.firstIndex(where: { $0.id == target.id }) {
            selectedIndex = index
        }
        if !isAISidebarOpen {
            isAISidebarOpen = true
            onAISidebarToggled?(true)
        }
        if let target {
            aiModel.load(item: target)
        }
        HapticHelper.feedback()
    }

    // MARK: - 缩略图

    public func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = item.inlineData ?? store.inlineData(for: item.id) else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }
}
