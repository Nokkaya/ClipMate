# ClipMate 全模块缺陷审查报告（交互、UI 与后端逻辑）

- **审查对象**：ClipMate 主工程（聚焦于工作草稿 `WorkingDraft`、内容控件 `InteractiveClip`、主面板控制器 `PanelController`、视图层 `PanelView` / `WorkingDraftCardView` 及底层数据与服务层）。
- **审查分支**：`feature/feature-interactive-clips`（HEAD: `760a979`）。
- **审查日期**：2026-09-17。
- **缺陷总数**：**19 项**（P0 致命缺陷 3 项，P1 严重缺陷 10 项，P2 中度缺陷 6 项）。

---

## 缺陷概览看板

| 序号 | 缺陷类别 | 严重级 | 缺陷简述 | 影响模块 | 状态 |
|---|---|---|---|---|---|
| **BUG-01** | 交互 | **P0** | 全局键盘监听劫持回车键，导致所有非主搜索框的输入框/多行文本微调回车直接触发外贴并关闭面板 | `PanelController` | ✅ 已修复 |
| **BUG-02** | 交互 | **P0** | 搜索词为空时 Delete 键拦截导致文本编辑退格直接在后台删除 SQLite 历史数据库记录 | `PanelController` | ✅ 已修复 |
| **BUG-03** | UI | **P0** | 520px 固定卡片高度与无滚动 VStack 导致草稿操作栏与“确认/复制/粘贴”主按钮被整屏裁剪截断 | `WorkingDraftCardView` | ✅ 已修复 |
| **BUG-04** | 后端逻辑 | **P0** | 异步请求取消、草稿切换或编辑导致 `isDraftGenerating` 加载转圈状态永久卡死 | `PanelViewModel` | ✅ 已修复 |
| **BUG-05** | 交互 | **P1** | 工作草稿未接入系统标准 `⌘Z` 撤销快捷键 | `PanelController` | ✅ 已修复 |
| **BUG-06** | 交互 | **P1** | `Esc` 键退出链路未感知工作草稿审查状态（Diff 抽屉 / 错误横幅 / 编辑态） | `PanelController` | ✅ 已修复 |
| **BUG-07** | 交互 | **P1** | 历史列表单条条目与右键上下文菜单缺少“创建/加入草稿”入口 | `ClipRowView` / `PanelView` | ✅ 已修复 |
| **BUG-08** | UI | **P1** | 多草稿标签切换时本地 `@State` 临时变量未复位，导致跨草稿正文被相互覆盖篡改 | `WorkingDraftCardView` | ✅ 已修复 |
| **BUG-09** | UI | **P1** | 多草稿标签栏缺少单草稿关闭入口，总关闭导致草稿孤儿滞留内存无法恢复 | `WorkingDraftCardView` / `PanelViewModel` | ✅ 已修复 |
| **BUG-10** | 后端逻辑 | **P1** | LLM 初次草稿生成就绪后漏调 `refreshDerivedState`，导致变焦层级停留在旧模板（LLM-R17 遗留） | `PanelViewModel` | ✅ 已修复 |
| **BUG-11** | 后端逻辑 | **P1** | `DraftAIService.generateZoomLevels` 错误将 `effectiveText` 传入模型导致文本自损截断 | `DraftAIService` | ✅ 已修复 |
| **BUG-12** | 后端逻辑 | **P1** | 控件重算仅修改 `confirmedText` 未清理 `userEditedText`，导致控件调整在用户编辑后永久失效 | `WorkingDraftEngine` / `WorkingDraftModel` | ✅ 已修复 |
| **BUG-13** | 后端逻辑 | **P1** | 全局清空历史 `confirmClearAll()` 漏调 `markDraftSourcesExcluded`（LLM-R12 修复不完整） | `PanelViewModel` | ✅ 已修复 |
| **BUG-14** | 后端逻辑 | **P1** | 跟随复制缺少条目去重校验，重复复制导致 `DraftSource.id` 冲突与 SwiftUI 渲染异常 | `PanelViewModel` | ✅ 已修复 |
| **BUG-15** | UI | **P2** | 草稿正文预览被 `lineLimit(8)` 硬截断且无滚动查看通道 | `WorkingDraftCardView` | ✅ 已修复 |
| **BUG-16** | UI | **P2** | 意图与偏好控件（options / slider / date / time）在 UI 上为静态只读文本，缺乏交互控件 | `WorkingDraftCardView` | 待后续规划 |
| **BUG-17** | 后端逻辑 | **P2** | 日程截止时间正则表达式捕获组索引越界潜在崩溃隐患 | `InteractiveControlEngine` | ✅ 已修复 |
| **BUG-18** | 后端逻辑 | **P2** | 工作草稿完全驻留内存，缺乏持久化与异常恢复机制 | `PanelViewModel` | 待后续规划 |
| **BUG-19** | 后端逻辑 | **P2** | `verifySourceCitation` 与 `DraftAIService.generateZoomLevels` 未被工作流调用形成死代码 | `WorkingDraftEngine` / `DraftAIService` | 待后续规划 |

---

## 详细缺陷报告

### 一、交互缺陷 (Interaction Bugs)

#### BUG-01｜P0｜全局键盘监听劫持回车键，导致所有非主搜索框的输入框/多行文本微调回车直接触发外贴并关闭面板
- **源码位置**：[`PanelController.swift:325-351`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift#L325-L351)
- **触发条件**：
  1. 用户在工作草稿卡片中点击“微调”，进入 `TextEditor` 准备编辑正文并按回车换行；
  2. 或在自然语言修改栏 `TextField` 输入指令后按回车提交；
  3. 或在 AI 侧边栏的 `promptBar` 输入框中按回车；
  4. 或在内容控件（如份数、时间）上手动输入数值后按回车。
- **实际现象**：
  `handleKey` 在 `case 36: // Return` 中无条件拦截了键盘事件，调用 `viewModel.pasteSelected()`。系统直接将剪贴板历史列表底层的首条记录模拟 `⌘V` 粘贴到前台第三方应用，并立即调用 `hidePanel()` 关闭了面板！不仅微调 TextEditor 无法按回车换行，用户的提问和修改指令也直接被打断，造成了极其严重的破坏性误操作。
- **根本原因**：
  `handleKey` 仅对预设的 5 个覆盖层（`showEditOverlay` 等）放行了按键，完全未检查 `panel.firstResponder is NSTextView`（即输入焦点是否正处于某个文本输入控件中）。
- **修复方案**：
  检查当前是否有焦点处于文本框，且排除主搜索框：
  ```swift
  case 36: // Return
      let isTextViewFocused = (panel.firstResponder is NSTextView)
      // 若当前焦点在文本控件内部，且不是主搜索框（比如正在编辑草稿或输入提示词），放行给原生控件处理
      if isTextViewFocused && !isSearchBarFocused {
          return false
      }
      ...
  ```

---

#### BUG-02｜P0｜搜索词为空时 Delete 键拦截导致文本编辑退格直接在后台删除 SQLite 历史数据库记录
- **源码位置**：[`PanelController.swift:352-362`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift#L352-L362)
- **触发条件**：
  当主搜索框无内容（`viewModel.query.isEmpty == true` 时，这是大多数使用常态），用户在工作草稿正文微调框、自然语言提示词框、草稿重命名框或 AI 侧边栏输入文本，然后按下 Backspace（Delete）键退格。
- **实际现象**：
  文本框里的字符一个没删，反而后台的 SQLite 剪贴板条目被一条一条静默删除（调用了 `viewModel.delete()`）！
- **根本原因**：
  ```swift
  case 51: // Delete
      if !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
          && viewModel.query.isEmpty {
          if viewModel.multiSelectedIDs.count > 1 {
              viewModel.deleteMulti()
          } else {
              viewModel.delete()
          }
          return true
      }
      return false
  ```
  该逻辑默认假定“只要搜索词为空，按 Delete 就是想删历史条目”。在存在其他内嵌输入框时，此假设彻底瓦解。
- **修复方案**：
  必须判断当前焦点不在任何活动文本编辑控件内：
  ```swift
  case 51: // Delete
      let isTextViewFocused = (panel.firstResponder is NSTextView)
      if isTextViewFocused { return false } // 放行退格删除文字
      if !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)
          && viewModel.query.isEmpty {
          ...
      }
  ```

---

#### BUG-05｜P1｜工作草稿未接入系统标准 `⌘Z` 撤销快捷键
- **源码位置**：[`PanelController.swift:377-382`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift#L377-L382)
- **触发条件**：用户在工作草稿中采纳了一项建议或手动修改了正文，随后按下 `⌘Z`。
- **实际现象**：毫无反应。
- **根本原因**：
  ```swift
  case 6 where cmdOnly: // ⌘Z 撤销内容控件单步调节
      if let session = viewModel.activeInteractiveSession, !session.undoStack.isEmpty {
          viewModel.undoInteractiveSession(itemID: session.itemID)
          return true
      }
      return false
  ```
  `handleKey` 只分派给了 `InteractiveSession`，对 `viewModel.activeDraft?.undoStack` 视而不见。
- **修复方案**：
  优先分派给活动草稿撤销：
  ```swift
  case 6 where cmdOnly:
      if let draft = viewModel.activeDraft, !draft.undoStack.isEmpty {
          viewModel.undoDraft()
          return true
      } else if let session = viewModel.activeInteractiveSession, !session.undoStack.isEmpty {
          viewModel.undoInteractiveSession(itemID: session.itemID)
          return true
      }
      return false
  ```

---

#### BUG-06｜P1｜`Esc` 键退出链路未感知工作草稿审查状态
- **源码位置**：[`PanelController.swift:383-398`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift#L383-L398)
- **触发条件**：草稿正展开 Diff 差异审查抽屉、或正在提示错误横幅、或处于正文微调态，用户按下 `Esc`。
- **实际现象**：不会关闭 Diff 抽屉或退出微调，而是直接跳过去清空搜索词，若搜索词为空则直接关闭隐藏主面板。
- **修复方案**：
  在 `case 53: // Esc` 响应链中加入工作草稿的子状态退栈：
  ```swift
  } else if viewModel.isDraftReviewingDiff {
      viewModel.isDraftReviewingDiff = false
  } else if viewModel.draftErrorMessage != nil {
      viewModel.draftErrorMessage = nil
  ```

---

#### BUG-07｜P1｜历史列表单条条目与右键上下文菜单缺少“创建/加入草稿”入口
- **源码位置**：[`PanelView.swift:616`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelView.swift#L616) 与 [`PanelView.swift:481-525`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelView.swift#L481-L525)
- **问题分析**：
  在主界面上，“创建工作草稿”按钮目前只放在多选模式下的 `BatchActionBar`（`multiSelectedIDs.count > 1` 时才显示）。单选某一条条目时，右键上下文菜单包含复制、粘贴、收藏、转片段、重命名、预览、队列、AI等十余项，唯独没有“基于此条创建草稿”或“加入当前活动草稿”的操作，导致单条材料无法便捷发起草稿流程。
- **修复方案**：
  在 `ContextMenuItems` 中增加：
  ```swift
  Button("基于此项创建草稿") { viewModel.createDraftFromSelected() }
  if viewModel.activeDraft != nil {
      Button("加入当前草稿") { viewModel.addSourceToActiveDraft(item: item) }
  }
  ```

---

### 二、UI 与界面布局缺陷 (UI & Layout Bugs)

#### BUG-03｜P0｜520px 固定卡片高度与无滚动 VStack 导致草稿操作栏与“确认/复制/粘贴”主按钮被整屏裁剪截断
- **源码位置**：[`PanelView.swift:20-55, 78`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelView.swift#L20-L55)
- **触发条件**：用户创建了一份包含正文、修改建议或未决问题的草稿。
- **实际现象**：
  主面板卡片高度被固定写死为 `height: 520` 并带 `clipShape`；左侧是一个无滚动的竖向 `VStack`。
  由于包含：搜索栏 (45px) + 分类栏 (35px) + 推荐栏 (35px) + 工作草稿卡片（包含多草稿栏、头部、变焦栏、内容预览、控件行、修改建议、问题抽屉）+ 列表 + 底部栏，草稿卡片本身就可达到 350~500px 高度。
  这不仅导致下方的剪贴板列表 `ClipList` 被挤压到几乎 0 高度，更致命的是，**草稿卡片底部的操作按钮栏（确认采用、查看修改、复制、粘贴）被直接挤出 520px 范围，被完全裁剪隐藏**！用户甚至找不到按钮来复制或粘贴草稿！
- **修复方案**：
  1. 对 `WorkingDraftCardView` 内部较长内容（如内容预览、修改建议列表、来源抽屉）施加带滚动的限制高度（如 `.frame(maxHeight: 180)`）；
  2. 或允许草稿卡片在主面板中与列表协同滚动，或在草稿展开时动态调整左侧布局结构。

---

#### BUG-08｜P1｜多草稿标签切换时本地 `@State` 临时变量未复位，导致跨草稿正文被相互覆盖篡改
- **源码位置**：[`WorkingDraftCardView.swift:11-12, 160-179, 307-352`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift#L11-L12)
- **触发条件**：
  1. 用户在草稿 1 中点击“微调”，进入编辑状态，此时 `@State private var tempContent` 载入草稿 1 的内容；
  2. 用户未点击保存，直接在标签栏点击草稿 2；
  3. 用户在草稿 2 界面上看到微调框仍然开着，点击“保存”。
- **实际现象**：
  草稿 2 的正文被瞬间覆盖为草稿 1 的内容！
- **根本原因**：
  `WorkingDraftCardView` 中的 `isEditingContent` 与 `tempContent` 是 View 层级的 `@State`。当 `activeDraft` 切换时，SwiftUI 重用当前 View，状态变量不会自动重置。
- **修复方案**：
  监听 `viewModel.activeDraft?.id` 的变化，发生切换时强制复位编辑态：
  ```swift
  .onChange(of: viewModel.activeDraft?.id) { _ in
      isEditingContent = false
      tempContent = ""
      isEditingTitle = false
      tempTitle = ""
  }
  ```

---

#### BUG-09｜P1｜多草稿标签栏缺少单草稿关闭入口，总关闭导致草稿孤儿滞留内存无法恢复
- **源码位置**：[`WorkingDraftCardView.swift:86-116`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift#L86-L116) 与 [`PanelViewModel.swift:1645-1653`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L1645-L1653)
- **问题分析**：
  1. 标签栏（`draftTabsView`）只提供了点击切换草稿的 Button，没有单个 Tab 上的“x”关闭按钮；
  2. 头部右侧的关闭按钮调用 `viewModel.closeDraft()`，其实现仅执行 `activeDraft = nil`，而**未从 `drafts` 数组中移除任何草稿**；
  3. 一旦 `activeDraft` 变为 `nil`，`WorkingDraftCardView` 整个消失。此前创建的草稿既没有被彻底关闭销毁，用户在界面上也再没有任何入口将其重新打开。
- **修复方案**：
  1. 在每个草稿 Tab 上添加悬浮或常驻的小叉按钮，点击调用 `removeDraft(id: d.id)`；
  2. 头部关闭按钮区分“关闭所有草稿”与“关闭并移除当前活动草稿”。

---

#### BUG-15｜P2｜草稿正文预览被 `lineLimit(8)` 硬截断且无滚动查看通道
- **源码位置**：[`WorkingDraftCardView.swift:353-361`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift#L353-L361)
- **问题分析**：非微调模式下，预览仅通过 `Text(displayText).lineLimit(8)` 展示，长文本后面全部被截断，且没有滚动条，用户在复制或外贴前无法检视全貌。
- **修复方案**：放入限定最大高度（如 120px）的 `ScrollView` 中，并允许折叠/展开。

---

#### BUG-16｜P2｜意图与偏好控件（options / slider / date / time）在 UI 上为静态只读文本，缺乏交互控件
- **源码位置**：[`WorkingDraftCardView.swift:418-422`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift#L418-L422)
- **问题分析**：
  在 `controlsView` 中，只有 `stepper` 和 `constraintToggle` 渲染了交互按钮，而 `.options(let choices)` 与 `.preferenceSlider` 均落入 `default:`，仅仅展示了 `Text("\(control.name): \(control.currentValue)")`。用户无法在 UI 上切换选项或调节偏好，导致底层已经实现的意图触发逻辑无法通过界面使用。
- **修复方案**：
  为 `.options` 提供胶囊选项切换按钮组（Picker / Segmented style），为 `.preferenceSlider` 提供左右偏好选择按钮。

---

### 三、后端与引擎逻辑缺陷 (Backend & Core Logic Bugs)

#### BUG-04｜P0｜异步请求取消、草稿切换或编辑导致 `isDraftGenerating` 加载转圈状态永久卡死
- **源码位置**：[`PanelViewModel.swift:1430, 1507, 1550`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L1430)
- **代码片段**：
  ```swift
  draftTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      let result = await self.draftAI.generateDraft(sources: sources, purpose: purpose)
      // 致命隐患：如果条件不满足直接 return，从未执行 self.isDraftGenerating = false！
      guard !Task.isCancelled, var current = self.activeDraft, current.id == targetId else { return }
      ...
      self.isDraftGenerating = false
  }
  ```
- **触发条件**：
  在 AI 生成初稿、分析修改建议或调整目标期间，用户切换了草稿、关闭了草稿或对草稿进行了手动编辑（导致 `version` 变化）。
- **实际现象**：
  `guard` 条件判定失败提前 `return`，`isDraftGenerating = false` 永远无法执行。界面上的加载菊花将永久旋转，阻碍后续的生成状态指示。
- **修复方案**：
  在 Task 内部使用 `defer` 确保标志位必定重置：
  ```swift
  draftTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      defer { self.isDraftGenerating = false }
      ...
  ```

---

#### BUG-10｜P1｜LLM 初次草稿生成就绪后漏调 `refreshDerivedState`，导致变焦层级停留在旧模板
- **源码位置**：[`PanelViewModel.swift:1431-1438`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L1431-L1438)
- **问题分析**：
  `createDraftFromSelected` 最初使用本地模板生成了 `candidateText` 和对应的 `zoomLevels`。当异步的大模型结果返回后：
  ```swift
  current.title = result.title
  current.purpose = result.purpose
  current.candidateText = result.draftText
  current.controls = result.controls
  current.unresolvedItems = result.unresolvedItems
  current.changeSummary = result.summary
  self.activeDraft = current
  ```
  此处给 `candidateText` 赋予了模型高质量正文，但**没有调用 `WorkingDraftEngine.refreshDerivedState(draft: &current)`**！导致草稿中的 `zoomLevels[.full]`、`[.keyPoints]`、`[.actionItems]`、`[.oneLine]` 依旧保持为最开始生成的简陋本地占位文本，变焦文本与真实正文完全脱节。
- **修复方案**：
  赋值后加入 `WorkingDraftEngine.refreshDerivedState(draft: &current)`。

---

#### BUG-11｜P1｜`DraftAIService.generateZoomLevels` 错误将 `effectiveText` 传入模型导致文本自损截断
- **源码位置**：[`DraftAIService.swift:406, 429`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift#L406)
- **代码片段**：
  ```swift
  result[.full] = draft.effectiveText
  ...
  let userPrompt = "草稿正文：\n\(draft.effectiveText)"
  ```
- **问题分析**：
  若当前草稿恰好处在 `.oneLine` 或 `.keyPoints` 变焦状态下，`draft.effectiveText` 返回的正是该简略文本！这会导致两重灾难：
  1. `result[.full]` 被写成简略文本，全量正文被永久抹杀；
  2. 发送给大模型的提示词变成了简略文本，要求模型对“一句话摘要”再次做要点与行动项提炼。
- **修复方案**：
  统一使用 `draft.fullDraftText`：
  ```swift
  result[.full] = draft.fullDraftText
  ...
  let userPrompt = "草稿正文：\n\(draft.fullDraftText)"
  ```

---

#### BUG-12｜P1｜控件重算仅修改 `confirmedText` 未清理 `userEditedText`，导致控件调整在用户编辑后永久失效
- **源码位置**：[`WorkingDraftEngine.swift:380-415`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift#L380-L415) 与 [`WorkingDraftModel.swift:328-336`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift#L328-L336)
- **问题分析**：
  在 `WorkingDraftModel` 中：
  ```swift
  public var fullDraftText: String {
      if let edited = userEditedText, !edited.isEmpty { return edited }
      if !confirmedText.isEmpty { return confirmedText }
      return candidateText ?? ""
  }
  ```
  `userEditedText` 的优先级高于 `confirmedText`。
  而在 `WorkingDraftEngine.applyControlValue` 中，重新计算数量或正则替换后，仅更新了 `draft.confirmedText = ...`，并未清空或同步更新 `draft.userEditedText`。
  因此，只要用户曾经手动微调过正文，之后无论怎么点击加减按钮调节控件数值，`fullDraftText` 始终返回旧的 `userEditedText`，界面和外贴内容毫无变化！
- **修复方案**：
  在 `applyControlValue` 成功更新后，清空 `draft.userEditedText = nil`（或者将重算后的文本同步写至 `userEditedText`）。

---

#### BUG-13｜P1｜全局清空历史 `confirmClearAll()` 漏调 `markDraftSourcesExcluded`
- **源码位置**：[`PanelViewModel.swift:1113-1118`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L1113-L1118)
- **问题分析**：
  单条删除与批量删除均已正确调用 `markDraftSourcesExcluded` 维护草稿来源状态。但在用户点击“清空历史记录”时，底层 SQLite 记录被清空，草稿关联来源的状态却未同步标记为 `.excluded`。
- **修复方案**：
  在 `confirmClearAll()` 中，收集所有未 pin 的来源 ID 并执行 `markDraftSourcesExcluded`。

---

#### BUG-14｜P1｜跟随复制缺少条目去重校验，重复复制导致 `DraftSource.id` 冲突与 SwiftUI 渲染异常
- **源码位置**：[`PanelViewModel.swift:337-345`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L337-L345)
- **问题分析**：
  在 `handleCaptured` 中，只要判定为相关内容，就直接向 `currentDraft.sources` `append` 一个新的 `DraftSource`。若用户重复复制了相同内容或相同 item，`currentDraft.sources` 中会出现多个 `id: item.id` 相同的实例。在 `WorkingDraftCardView` 中使用 `ForEach(draft.sources)` 遍历时，会导致 SwiftUI 抛出重复 ID 警告与界面渲染异常。
- **修复方案**：
  加入去重判断：`guard !currentDraft.sources.contains(where: { $0.id == item.id }) else { return }`。

---

#### BUG-17｜P2｜日程截止时间正则表达式捕获组索引越界潜在崩溃隐患
- **源码位置**：[`InteractiveControlEngine.swift:928-930`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift#L928-L930)
- **代码片段**：
  ```swift
  let groupIdx = match.range(at: 1).location != NSNotFound ? 1 : 2
  if let r = Range(match.range(at: groupIdx), in: session.originalText) ...
  ```
- **问题分析**：
  代码中声明的两个正则模式均只包含 1 个捕获括号（其余括号均为 `(?:...)` 非捕获组）。`match.numberOfRanges` 仅为 2（索引 0 为全文匹配，索引 1 为捕获的时间）。若组 1 恰好为 `NSNotFound`，代码试图取索引 `2`，这会直接超出 `match` 的捕获组范围，在特定边界输入下存在安全隐患。
- **修复方案**：
  严格校验 `match.numberOfRanges > groupIdx` 或固定使用索引 1。

---

#### BUG-18｜P2｜工作草稿完全驻留内存，缺乏持久化与异常恢复机制
- **源码位置**：[`PanelViewModel.swift:110-111`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift#L110-L111)
- **问题分析**：
  `drafts` 与 `activeDraft` 纯粹存放在 `PanelViewModel` 的内存中。当 ClipMate 退出、崩溃或系统重启后，正在编辑的多篇草稿和历史撤销栈将被永久丢失。
- **修复建议**：
  在 `ClipStore` 或专用 JSON 存储层中实现 `WorkingDraft` 的本地文件落盘（如 `~/Library/Application Support/ClipMate/drafts.json`），在应用启动时恢复。

---

#### BUG-19｜P2｜`verifySourceCitation` 与 `DraftAIService.generateZoomLevels` 未被工作流调用形成死代码
- **源码位置**：[`WorkingDraftEngine.swift:85`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift#L85) 与 [`DraftAIService.swift:402`](file:///Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift#L402)
- **问题分析**：
  两个核心能力已完整编写并通过了单元测试，但在实际的 ViewModel 和 Card 交互流程中未真正接入调用，属于功能闭环未接通的死代码。

---

## 修复优先级建议

1. **第一优先级（阻断级交互修复 - 立即修复）**：
   - 修复 **BUG-01** 与 **BUG-02**：在 `PanelController.swift` 中为 `Return` 和 `Delete` 添加文本框焦点判断保护，彻底解决输入文本时误删剪贴板历史与误触发外贴强退的严重交互 Bug。
   - 修复 **BUG-03**：为 `WorkingDraftCardView` 增加合理的高度约束与滚动支持，确保操作栏与底部的“确认/复制/粘贴”按钮在 520px 窗口内始终完整可见可用。
   - 修复 **BUG-04**：在 `PanelViewModel` 的 Task 中引入 `defer { self.isDraftGenerating = false }`，彻底解决加载中菊花卡死问题。

2. **第二优先级（数据与状态一致性修复）**：
   - 修复 **BUG-08**（多草稿切换复位编辑态）、**BUG-10**（LLM 生成后刷新衍生层级）、**BUG-11**（变焦生成使用全量正文）、**BUG-12**（控件修改清理 userEditedText）。

3. **第三优先级（完善体验与边缘防护）**：
   - 修复 **BUG-05**（⌘Z）、**BUG-06**（Esc）、**BUG-09**（单草稿关闭 Tab）、**BUG-13**（清空历史同步）、**BUG-14**（来源去重）、**BUG-16**（丰富选项控件）、**BUG-18**（草稿持久化）。
