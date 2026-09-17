# ClipMate：LLM 工作草稿与意图控件验收报告

- 验收日期：2026-09-16。
- 分支：`feature/feature-interactive-clips`。
- HEAD：`55bcf75f47ec47a08cf535581421ccbdff2870a5`。
- **验收对象：上述 HEAD 加本次未提交、未跟踪的工作区实现，不是仅验收该提交本身。**
- 验收依据：[ClipMate-LLM工作草稿与意图控件-设计与开发方案.md](/Users/zhangdi/Documents/others/ClipMate/ClipMate-LLM工作草稿与意图控件-设计与开发方案.md)。
- 报告整理时，已将源码与验收快照的 SHA-256 清单对照，未发现源码变化。本报告不代表后续修复后的状态。

## 一、结论

**暂不通过完整验收。** LLM 已接入草稿生成、材料归属和自然语言修改调用，但模型调用范围、异步状态保护、修改采用、约束与派生版本处理仍有缺陷；正文查看编辑、目标驱动候选方案、多草稿管理及完整变焦流程也未形成可用闭环。

主要阻断问题包括：仅本地模式仍发起模型请求、关闭后的草稿被迟到响应恢复、新增限制未实际写入、过期建议改写新版本、全文替换误伤其他内容、硬约束失效，以及移出来源丢失用户编辑。

P1 表示可能误改或丢失内容、违反明确约束或分析范围；P2 表示功能闭环、交互或状态处理仍不完整。下文均为待修复或待补齐项。

## 二、范围与测试结果

### 1. 验收快照包含的主要变更

| 类型 | 文件或目录 |
|---|---|
| 新增实现 | `Sources/ClipMateCore/Draft/WorkingDraftModel.swift`、`WorkingDraftEngine.swift`、`DraftAIService.swift` |
| 新增界面 | `Sources/ClipMateCore/Panel/WorkingDraftCardView.swift` |
| 修改现有文件 | `PanelView.swift`、`PanelViewModel.swift`、`L10n.swift`、`Tests/ClipMateTests/main.swift` |

### 2. 测试结果

| 检查 | 结果 |
|---|---|
| 现有测试 | 131 个全部通过，其中新草稿相关测试为 12 个。 |
| 补充检查 | 19 组针对性检查均发现缺项或边界问题，共 21 个失败断言。失败断言数不等于独立问题数，也不代表随机样本失败率。 |
| 模型调用链 | 使用进程内 URLProtocol 模拟响应，经过实际 AIService 与 DraftAIService 的请求、解析及状态写入路径；包括延迟返回和部分无效结果。 |
| 隔离措施 | 临时源码副本、独立命名剪贴板、独立设置域；测试副本不读取或写入真实模型凭据。 |
| 未验证范围 | 未调用真实云模型评估生成质量；未做完整的真实界面操作、目标应用粘贴和性能压力验收。 |
| 项目变更 | 验收未修改功能源码。本次整理仅新增本报告，未提交 Git。 |

测试 runner 的“✅”表示测试闭包执行结束，并不保证内部断言全部通过。验收依据是失败断言与最终汇总。现有 131 个测试通过，不能证明完整方案已经实现。

补充检查分为引擎级、ViewModel 级、接口级和模拟模型调用链。特别是变焦、正文编辑状态及部分语义控件测试，构造了当前数据模型允许的状态；报告明确标注，不能据此声称相应界面已经存在。

### 3. 证据文件

- [现有测试日志](/private/tmp/clipmate-llm-review-_374i8ao/baseline.log)。
- [完整补充验收日志](/private/tmp/clipmate-llm-review-_374i8ao/review.log)。
- [19 组补充检查代码](/private/tmp/clipmate-llm-review-_374i8ao/review-probes.swift)。
- [验收源码指纹清单](/private/tmp/clipmate-llm-review-_374i8ao/source-hashes.json)。

这些证据位于临时目录，可能被系统清理。下文已保留关键复现条件、实际结果与预期行为，报告可独立阅读。

## 三、逐阶段对照

| 阶段 | 已有实现 | 验收判断 |
|---|---|---|
| 第一阶段：工作草稿生成 | 多选材料、本地初稿、模型生成、标题及用途、来源列表、复制和粘贴入口。 | 部分实现。缺少完整正文查看编辑、初次确认采用、逐项来源追溯和未决问题回答；仅本地策略不统一。 |
| 第二阶段：持续更新 | 跟随复制开关、模型归属评估、来源加入、待采用建议。 | 不符合完整预期。默认跟随、迟到结果恢复旧草稿、新增材料不进入正文；多草稿管理与独立存储缺失。 |
| 第三阶段：关联修改 | 自然语言请求、修改前后片段、整组采用和撤销入口。 | 不符合完整预期。追加被忽略、版本未检查、重复和串联替换、硬约束未校验，撤销状态不完整。 |
| 第四阶段：目标与约束控件 | 数量及约束控件模型、部分界面和本地计算连接。 | 核心目标未完成。未接入目标驱动 LLM 候选生成；语义选项只改状态，数值兜底仍可能误改。 |
| 第五阶段：信息层级 | 本地层级数据，以及独立的 LLM 层级生成方法。 | 尚未接成工作草稿的完整交互。缺少选择与逐层编辑入口，生成方法未被工作流调用；接口测试发现正文与层级版本混用。 |

## 四、已复现问题

下列 LLM-R01 至 LLM-R19 与补充测试代码及日志编号一致。运行复现说明的是给定输入和状态下的行为，不以模型一定产生这些输出为前提；模拟响应用于检查系统能否正确处理合法、迟到或不完整的模型结果。

### LLM-R01｜P1｜新增限制显示已采用，但没有写入正文

- 对应范围：第三阶段。
- 验证方式：引擎级运行复现。
- 复现条件：草稿为“需要导出报告”。创建一条原文片段为空、建议内容为“不得包含个人信息”的追加建议，然后采用。
- 实际结果：草稿仍为“需要导出报告”，建议被标为已采用，版本升为 2。采用逻辑只处理非空原文片段，忽略追加内容。
- 预期行为：追加建议必须实际写入；不支持的修改类型应提示失败，不能显示采用成功。
- 修复方向：明确区分新增、替换、删除动作，并校验采用后的实际结果。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:114)。

### LLM-R02｜P1｜过期建议直接修改新版本草稿

- 对应范围：第三阶段及版本保护。
- 验证方式：引擎级运行复现。
- 复现条件：当前草稿版本为 4，正文含“本周上线”；采用针对版本 1 的“本周上线 → 下月上线”建议。
- 实际结果：采用成功，版本变为 5。targetVersion 虽然存储在建议中，但采用时没有检查。
- 预期行为：针对旧版本的建议需要重新定位和检查冲突，不能仅凭相同文字仍存在就直接应用。
- 修复方向：采用前校验草稿版本、原文范围和用户编辑；不匹配时重新生成或显示冲突。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:99)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:109)。

### LLM-R03｜P1｜重复片段被全文替换，误改其他事项

- 对应范围：第三阶段。
- 验证方式：引擎级运行复现。
- 复现条件：草稿为“甲项目：周五上线。乙项目：周五上线。”；建议仅修改甲项目，但原文定位只提供“周五上线”。
- 实际结果：甲乙项目同时变成“下周上线”。
- 预期行为：只修改甲项目；定位信息不足或存在多个命中时应要求确认或拒绝应用。
- 修复方向：绑定段落、来源范围和基准版本，不使用无范围的全文替换。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:117)。

### LLM-R04｜P1｜成组修改发生串联替换

- 对应范围：第三阶段。
- 验证方式：引擎级运行复现。
- 复现条件：原文“阶段A；阶段B”；同组修改为“阶段A → 阶段B”和“阶段B → 阶段C”。
- 实际结果：实际结果为“阶段C；阶段C”，第一步生成的文本又被第二步改写。
- 预期行为：基于同一原文版本执行，结果应为“阶段B；阶段C”。
- 修复方向：先定位并检查所有原文范围，再原子应用；重叠或冲突的范围需要单独处理。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:102)、[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:114)。

### LLM-R05｜P1｜硬约束没有参与修改采用检查

- 对应范围：第三、四阶段。
- 验证方式：引擎级运行复现。
- 复现条件：正文为“导出不能包含个人信息。”，控件将此标记为已锁定的硬约束；采用“不能包含 → 需要包含”的建议。
- 实际结果：正文变成“导出需要包含个人信息。”，没有拦截或冲突提示。
- 预期行为：已锁定硬约束必须参与建议检查；与之冲突的结果不能被当作有效修改采用。
- 修复方向：将约束及其关联文本传入生成任务并在采用前检查；不能仅依赖控件的布尔标记或模型提示词。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:99)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:152)。

### LLM-R06｜P1｜数量控件兜底修改无关数字

- 对应范围：第四阶段。
- 验证方式：引擎级运行复现。
- 复现条件：正文“参会3人，编号2023，会议室A3。”；人数控件值从 3 调为 4，控件单位为空。
- 实际结果：输出“参会4人，编号2024，会议室A4。”。
- 预期行为：仅改变人数；无法确认绑定关系时不得修改其他数字。
- 修复方向：取消裸数字的全文替换兜底；控件需要有效变量绑定和来源定位，无法执行时生成待确认建议。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:249)。

### LLM-R07｜P2｜语义目标控件只改标签，不生成方案

- 对应范围：第四阶段。
- 验证方式：引擎级运行复现与调用链检查。
- 复现条件：为“需要开发全部功能，并完整交付。”设置“完整／尽快”交付偏好，选择“尽快”。
- 实际结果：控件值改变，正文不变，也没有产生候选修改。实际控件操作只调用本地 applyControlValue，没有接入 LLM 候选方案任务。
- 预期行为：根据目标提出范围调整与取舍建议，保留硬约束，并让用户查看后采用。
- 修复方向：区分确定计算与语义目标；语义目标调节应触发带当前来源、目标和约束的候选生成流程。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:271)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1455)。

### LLM-R08｜P1｜变焦状态下全部采用会把正文缩成摘要

- 对应范围：第五阶段。
- 验证方式：接口级运行复现；当前草稿界面尚无对应变焦入口。
- 复现条件：完整正文为“要求A；详细依据B；固定条件C。”；当前一句话层级为“要求A”，执行全部采用，将“要求A”改为“要求D”。
- 实际结果：confirmedText 只剩“要求D”，详细依据与固定条件丢失；当前摘要甚至仍显示旧的“要求A”。
- 预期行为：展示层级不能成为完整正文的编辑基准；修改应作用于完整草稿，再更新或失效相关层级。
- 修复方向：将完整正文与当前展示文本分开，采用和快照统一基于完整内容。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:144)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:275)。

### LLM-R09｜P1｜已取消的承诺仍出现在旧变焦层级

- 对应范围：第五阶段。
- 验证方式：接口级运行复现；当前草稿界面尚无对应变焦入口。
- 复现条件：正文和要点都含“周五必须上线”；采用修改，将正文改为“上线日期待确认”，再读取要点层级。
- 实际结果：要点仍输出“周五必须上线”。派生刷新未失效核心要点和结论清单。
- 预期行为：内容变更后所有受影响层级必须重新生成或标为过期，不能继续作为当前有效输出。
- 修复方向：层级绑定草稿版本，采用、编辑、撤销及约束变化后统一处理失效。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:555)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:275)。

### LLM-R10｜P2｜撤销只恢复文字，未恢复关联状态

- 对应范围：第三、四、五阶段。
- 验证方式：引擎级运行复现。
- 复现条件：先采用一个修改建议再撤销；另对一个已锁定约束执行切换后撤销。
- 实际结果：文字恢复，但原建议仍标为已采用，不能从待采用列表再次使用；约束锁定值也没有恢复。
- 预期行为：一次撤销应恢复对应内容、建议处理状态、控件、约束和有效层级。
- 修复方向：扩展快照内容并统一恢复；版本标识应能够区分撤销后的新状态，防止旧异步结果被误判为有效。
- 代码位置：[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:198)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:304)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:320)。

### LLM-R11｜P1｜移出来源覆盖已确认草稿和用户编辑

- 对应范围：第二、三阶段。
- 验证方式：ViewModel 运行复现；编辑状态由测试构造。
- 复现条件：草稿已有两条来源、已确认正文和独立的用户说明，版本为 7；移出其中一条来源。
- 实际结果：直接调用本地 createDraft 重建，用户说明消失，草稿 ID 和版本也被重置。当前界面尚无正文编辑入口，本检查验证的是模型中已存在的编辑状态保护。
- 预期行为：对受影响内容提出修改，保留无关的已确认文字和用户编辑，延续同一草稿身份。
- 修复方向：来源变更进入增量影响分析；不以重建草稿替代冲突检查和编辑合并。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1500)。

### LLM-R12｜P1｜删除历史来源后草稿副本仍然有效

- 对应范围：来源管理与清理。
- 验证方式：ViewModel 运行复现。
- 复现条件：从历史条目创建草稿，然后调用当前删除历史条目的入口。
- 实际结果：原历史已删除，但 activeDraft.sources 中仍保留该条目和完整来源内容，引用未标记失效。
- 预期行为：清理来源摘录与缓存，使关联引用失效，并按设计提示处理草稿内已派生内容。
- 修复方向：单条删除、批量删除和清理历史统一通知草稿来源管理，不只刷新历史列表。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1016)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:65)。

### LLM-R13｜P2｜新草稿默认开启跟随复制

- 对应范围：第二阶段及分析范围设置。
- 验证方式：ViewModel 运行复现。
- 复现条件：直接从所选材料创建草稿，不操作跟随复制开关。
- 实际结果：followCopy 已为 true，后续复制会进入自动归属评估。
- 预期行为：按方案由用户明确开启跟随复制，并知晓其材料分析范围。
- 修复方向：新建默认不跟随；用户开启后记录选择，并让暂停、结束状态同时约束后台任务。
- 代码位置：[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:53)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:238)。

### LLM-R14｜P1｜仅本地模式仍然发起模型请求

- 对应范围：第一、二阶段及分析范围设置。
- 验证方式：真实调用链＋进程内模拟模型响应。
- 复现条件：模型配置可用、interactiveClipsLocalOnly=true；创建草稿后触发一条新复制内容。
- 实际结果：测试桩捕获 1 次模型请求，预期为 0。仅初次草稿生成检查仅本地开关，跟随复制路径没有检查；自然语言修改路径代码也没有统一检查。此次请求被本地测试桩截获，没有发送到真实云端。
- 预期行为：仅本地模式应对所有内容控件和草稿模型调用一致生效。
- 修复方向：集中校验模型调用策略和自动触发权限，避免各入口各自判断而遗漏。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:310)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1368)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1431)。

### LLM-R15｜P1｜关闭草稿后迟到响应将其恢复

- 对应范围：第二阶段及异步状态保护。
- 验证方式：真实调用链＋延迟模拟模型响应。
- 复现条件：触发新材料归属分析，确认请求已开始后关闭草稿，再返回 addition 响应。
- 实际结果：activeDraft 原已为空，响应返回后又被赋值成关闭前的草稿。
- 预期行为：关闭、暂停、切换或更新版本后，旧请求不能恢复或覆盖当前状态。
- 修复方向：保存并取消任务；响应写入前再次校验草稿 ID、版本、来源与跟随状态，合并到当前有效状态。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:311)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:328)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1493)。

### LLM-R16｜P2｜新增材料归入来源，但没有更新内容

- 对应范围：第二阶段。
- 验证方式：真实调用链＋模拟模型响应。
- 复现条件：新材料为“演示的负责人明确为张三”，模型返回 addition，没有替换建议。
- 实际结果：来源数量增加到 2，但草稿没有张三，也没有待采用更新。
- 预期行为：候选草稿应形成有依据的新增内容；已确认草稿应提出新增建议，而不是只记录材料数量变化。
- 修复方向：为 addition 建立增量草稿生成或追加修改流程，区分来源加入与内容更新两个动作。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:323)、[DraftAIService.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift:191)。

### LLM-R17｜P2｜初次 LLM 草稿与信息层级不同步

- 对应范围：第一、五阶段。
- 验证方式：真实调用链＋模拟模型响应。
- 复现条件：初次生成返回“模型整理的最终回复：演示范围待确认。”，检查草稿正文和缓存完整层级。
- 实际结果：正文是模型返回结果，但 zoomLevels[.full] 仍为先前的本地模板，其他层级也未同步。
- 预期行为：所有派生内容绑定同一草稿版本；模型结果就绪后旧层级失效或重新生成。
- 修复方向：将模型生成结果通过统一版本更新入口落地，避免只赋值 candidateText 而遗留派生状态。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1373)。

### LLM-R18｜P2｜关联组中的无效片段被静默丢弃

- 对应范围：第三阶段。
- 验证方式：真实调用链＋模拟模型响应。
- 复现条件：模拟返回包含两处关联修改：正文片段真实存在，结尾片段不存在。
- 实际结果：不存在的结尾修改被丢弃，只保留正文修改，仍作为正常的可采用建议展示。
- 预期行为：关联组验证不完整时，明确标记未完成、重新生成或拒绝整组，不能声称关联修改已完整准备。
- 修复方向：结构校验返回整组状态及具体错误；禁止用 compact 筛选后的残余结果代替完整方案。
- 代码位置：[DraftAIService.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift:275)。

### LLM-R19｜P2｜新建草稿替换唯一的现有草稿

- 对应范围：第二阶段及多事项管理。
- 验证方式：ViewModel 运行复现与存储结构检查。
- 复现条件：第一份草稿已有用户确认的内容，再次从所选材料创建草稿。
- 实际结果：activeDraft 被直接替换；未发现旧草稿存储、列表或恢复入口。测试检查草稿身份改变，结合只有单一内存实体的实现确认缺少保留路径。
- 预期行为：多份事项可保存、切换、暂停或结束；新建不能静默丢失之前的工作。
- 修复方向：引入草稿集合与独立持久化，活动草稿只是当前选择，关闭和删除分别处理。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:110)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1363)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1493)。

## 五、代码检查确认的功能缺项

以下为代码检查结果，不计入上述 19 组运行复现数量，也不声称已经进行真实界面端到端验收。

### LLM-C01｜P1｜完整草稿没有可查看、可编辑的正文入口

- 确认方式：代码检查。
- 当前实现：卡片显示标题、来源、控件、建议、问题和复制按钮，但没有正文预览或编辑控件，也没有初次草稿确认采用入口。用户难以在复制前核对完整结果。
- 预期与修复方向：补齐完整正文查看、编辑和采用；用户编辑状态接入版本保护，候选、已确认与生成中状态清晰可见。
- 代码位置：[WorkingDraftCardView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift:16)、[WorkingDraftCardView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift:410)。

### LLM-C02｜P2｜来源追溯与事实校验未连接到模型输出

- 确认方式：代码检查。
- 当前实现：模型草稿结果没有逐项事实、来源 ID、来源版本及原文定位；verifySourceCitation 只作为独立函数存在，未被实际生成或采用流程调用。来源列表只能看到材料名和前 40 字，不能从结论定位依据。
- 预期与修复方向：模型结果返回结构化来源绑定；检查引用真实性和版本，并允许从草稿中的关键事实返回对应材料。
- 代码位置：[DraftAIService.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift:17)、[DraftAIService.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift:43)、[WorkingDraftEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftEngine.swift:76)、[WorkingDraftCardView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift:349)。

### LLM-C03｜P2｜未决问题没有回答与解决入口

- 确认方式：代码检查。
- 当前实现：unresolvedItemsView 只展示问题文字，没有候选回答、自由输入或将答案写入后续任务的逻辑。draftErrorMessage 也未发现对应界面展示绑定，部分采用失败对用户不可见。
- 预期与修复方向：将必要问题做成可回答的一步操作，答案更新草稿与约束；失败原因在当前操作附近可见。
- 代码位置：[WorkingDraftCardView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift:391)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1404)。

### LLM-C04｜P2｜工作草稿变焦未接入实际使用流程

- 确认方式：代码检查。
- 当前实现：DraftAIService.generateZoomLevels 已定义，但未发现工作流调用；草稿卡片没有信息层级切换、按住预览、滚动选择、松开粘贴、重要信息锁定或逐层编辑入口。现有内容控件的变焦能力不能直接视为新草稿流程已完成。
- 预期与修复方向：以完整草稿版本生成和管理层级，再连接交互与粘贴；先解决 LLM-R08、R09、R17 的版本及正文混用问题。
- 代码位置：[DraftAIService.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/DraftAIService.swift:307)、[WorkingDraftCardView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/WorkingDraftCardView.swift:16)、[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:275)。

### LLM-C05｜P2｜来源版本使用进程内哈希，未形成稳定校验链

- 确认方式：代码检查。
- 当前实现：DraftSource.versionHash 默认来自 content.hashValue，ViewModel 创建来源时也使用 hashValue；该值不是跨进程稳定内容指纹，且未发现其被用于响应写入和采用时的来源版本校验。
- 预期与修复方向：使用稳定内容指纹或显式内容版本，并将其纳入请求、引用、缓存和采用校验。
- 代码位置：[WorkingDraftModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Draft/WorkingDraftModel.swift:73)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:1353)。

## 六、修复后的复核重点

1. 统一所有模型调用入口的分析范围设置，并检查默认跟随、暂停、关闭、切换草稿时的任务取消和迟到结果处理。
2. 修改采用以完整正文及明确版本为基准，支持新增、替换和删除；检查定位唯一性、关联组完整性、硬约束和原子性。
3. 控件只修改已绑定内容；语义目标通过 LLM 形成可核对的候选方案，不能用标签变化或裸数字替换代替。
4. 来源移出、删除、正文编辑、撤销和层级生成统一维护版本及用户内容，补齐独立草稿存储与切换。
5. 完成正文核对、问题回答和变焦交互后，再进行真实界面、目标应用粘贴及真实模型效果验收；保留现有测试并补齐本报告复现条件。

本报告的结论是针对当前工作区实现的功能和可靠性验收，不是对某个真实 LLM 的生成质量评分。
