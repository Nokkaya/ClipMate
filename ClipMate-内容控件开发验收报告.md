# ClipMate 内容控件开发验收报告

- 验收日期：2026-09-14。
- 验收提交：`f868d2164352ab7ca32fdf447a59a424d37a728c`（简称 `f868d21`）。
- 相关功能提交：`8d936f0`、`f868d21`。
- 验收依据：[ClipMate-内容控件-feature开发计划.md](/Users/zhangdi/Documents/others/ClipMate/ClipMate-内容控件-feature开发计划.md)。
- 整理报告时确认项目 HEAD 仍为上述版本。本报告记录该版本的验收结果，不代表后续修复后的状态。

## 一、验收结论

**暂不符合完整验收预期。** 已具备基础控件、部分比例计算、时间平移、特定日期格式联动、重置及复制入口，但仍存在结果被误改、内容丢失、锁定失效、固定条件未保留等问题，不能按完整开发计划判定通过。

“场景仅为示例、不限制适用范围”尚未落实：当前入口由四类固定解析器构成，不能组合同一内容中的多种关系，普通会议记录也不能独立使用粘贴变焦。

优先修复影响内容正确性的 P1 问题，再补齐通用关系识别与交互缺项。P1 表示可能丢失或误改输出内容、违反明确条件；P2 表示计划能力或交互尚不完整。下文问题均记录为待修复或待补齐。

## 二、验收方式与证据范围

| 检查项 | 结果及范围 |
|---|---|
| 现有测试 | 隔离副本中执行现有 98 个测试，失败断言为 0；其中内容控件相关测试为 9 个。 |
| 补充检查 | 新增 21 组针对性检查，21 组均暴露缺项或边界问题，共 24 个失败断言。失败断言数不等于独立问题数，也不代表随机样本的失败率。 |
| 实现检查 | 检查解析、计算、原文替换、会话缓存、控件视图、快捷键入口、变焦及设置连接。 |
| 隔离方式 | 在临时源码副本运行测试，使用专用命名剪贴板和测试设置域；功能计算逻辑保持原样。 |
| 未覆盖 | 未进行真实目标应用中的完整界面粘贴验收，未做云模型效果验证，也未完成大规模性能基准或完整时区、夏令时验收。 |
| 工作区影响 | 验收未修改项目功能源码；本次仅新增报告文档。 |

测试 runner 会在测试闭包执行结束后打印“✅”，即使其中的断言失败。因此判断依据是失败断言和最终汇总，不能仅看日志中的绿色标记。

首次隔离运行有一个剪贴板恢复断言失败，原因是测试副本中的默认剪贴板参数尚未全部隔离。补齐该测试环境替换后，98 个现有测试全部通过；此项不计为产品缺陷。

证据文件位于临时目录，可能被系统清理。本报告已记录关键输入、实际结果和预期行为，不依赖临时文件才能阅读：

- [最终验收日志](/private/tmp/clipmate-controls-review-4zfslfx1/review.log)。
- [21 组补充检查代码](/private/tmp/clipmate-controls-review-4zfslfx1/boundary-tests.swift)。
- [隔离测试入口](/private/tmp/clipmate-controls-review-4zfslfx1/Tests/ClipMateTests/main.swift)。

## 三、逐阶段对照

| 计划阶段 | 已有实现 | 尚未达到预期 |
|---|---|---|
| 第一阶段：变量识别与控件生成 | 能识别部分结构明确的文本；支持缺失人数提示；提供基础控件卡片。 | 识别仍依赖固定解析模式；缺失基准可被快捷键绕过；缺少通用变量理解和完整来源对应。 |
| 第二阶段：比例、数量与计算联动 | 简单整数、小数比例和“单价 × 数量 + 固定费”示例通过现有测试。 | 同额误替换、币种混入、优惠遗漏、数值子串误改、分数范围遗漏及高精度原值替换失败。 |
| 第三阶段：时间、日期与顺序联动 | 部分时间区间平移、截止超时和既有中文日期替换可运行。 | 休息时长未生效，固定预约未保留，跨日提示缺失，部分日期格式无法同步，相对日序输出不完整。 |
| 第四阶段：依赖组合与约束 | 有单项锁定标记和部分提示；部分更新路径会清理缓存。 | 锁定结果不一致，多关系不能组合，固定日期冲突遗漏；缓存接口缺少版本自校验；缺少关系纠正与编辑保护。 |
| 第五阶段：交互与输出 | 提供加减、重置、复制、粘贴和会话内状态保留。 | 无直接输入和日期选择，缺失人数选项受限；无真正的原文差异对照、单步撤销、调整结果手动编辑保护；长文本输出会截断。 |
| 第六阶段：粘贴变焦 | 对已识别内容提供固定规则生成的层级及按钮切换。 | 普通文本无法独立使用；缺少按住预览、滚动选层、松开粘贴、信息锁定和逐层编辑；简短输出遗漏冲突。 |

## 四、已复现问题与功能缺项

IC-01 至 IC-21 分别对应日志和补充代码中的 REVIEW 01 至 REVIEW 21。除特别说明的接口级或计算层检查外，均以自然文本输入调用当前实现复现；这些检查不等同于真实界面端到端操作。

### IC-01｜P2｜通用比例识别仍受固定场景限制

- 对应计划：第一、二阶段。
- 复现方式：输入“制作 3 套展示架，每套需要 2 米木条和 4 枚螺丝；总用量为木条 6 米、螺丝 12 枚。”。
- 实际结果：分析结果为 nil，没有套数控件。入口只有菜谱、报价、排期、行程四个解析分支。
- 预期行为：在已支持的比例关系范围内，依据变量与依赖生成控件；举例场景不应成为类别门槛。
- 修复方向：将变量和关系识别与场景名称分离，使同一种计算关系可用于不同内容结构。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:17)。

### IC-02｜P2｜同一内容不能组合数量与日期控件

- 对应计划：第一、四阶段。
- 复现方式：同一条内容包含“单价：20 元、数量：3 件、运费：10 元、总额：70 元”，以及“开始日期：2026-10-01、第 1 天准备、第 2 天交付”。
- 实际结果：只生成数量控件，没有日期控件；命中报价解析后立即返回，后续日期关系未参与分析。
- 预期行为：多个独立且可靠的关系可以共存；调整数量不改变日期，调整日期不改变金额。
- 修复方向：汇集受支持的关系并保留各自的变量与影响范围，避免第一个模式独占整份内容。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:17)。

### IC-03｜P1｜总额替换改写无关的同额文字

- 对应计划：第二、四阶段。
- 复现方式：输入单价 20 元、数量 3 件、运费 70 元、总额 130 元，另有“备注：服务包 130 元，单独计费”；数量调为 5。
- 实际结果：总额正确变为 170 元，但备注也变成“服务包 170 元，单独计费”。
- 预期行为：仅更新当前总额对应的原文位置，无关的相同数字保持原样。
- 修复方向：使用已识别字段的来源范围替换，取消按金额字符串在全文替换。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:563)。

### IC-04｜P1｜金额输出混入错误币种

- 对应计划：第二阶段。
- 复现方式：输入“单价：20 USD、数量：3 件、运费：10 USD、总额：70 USD”，数量调为 5。
- 实际结果：总额输出为“110 元 USD”。
- 预期行为：输出“110 USD”，保留原币种；不确定币种关系时不得自动换算。
- 修复方向：金额值和币种分别保存，按原文币种渲染，避免写死“元”。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:215)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:563)。

### IC-05｜P1｜忽略优惠，在用户未调节时改写总额

- 对应计划：第二、四阶段。
- 复现方式：输入单价 20 元、数量 3 件、运费 10 元、优惠 10 元、总额 60 元，仅调用分析，不调整参数。
- 实际结果：调整预览中的总额直接变成 70 元，冲突列表为空。原始历史没有被修改，但该预览可成为后续复制内容。
- 预期行为：未操作时保留原文；发现未支持的优惠关系时提示需要确认，不能忽略已写明的条件。
- 修复方向：校验推导关系与原文总额是否一致；存在遗漏条件时暂停相关计算，补齐后再启用。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:167)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:237)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:555)。

### IC-06｜P1｜调整后锁定恢复旧值，正文与摘要不一致

- 对应计划：第四阶段。
- 复现方式：输入“4人份、面粉 200 克、糖 100 克”；调为 8 人，再锁定糖。
- 实际结果：锁定前糖为 200 克；锁定后正文恢复成 100 克，而核心要点仍显示糖 200 克。
- 预期行为：锁定当前 200 克，正文、明细、摘要和复制结果应一致。
- 修复方向：保存锁定时的实际值，并将锁定值参与统一结果生成；不能简单跳过替换并回用原文。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:465)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:479)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:824)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:534)。

### IC-07｜P1｜同行替换破坏锁定项的正文引用

- 对应计划：第二、四阶段。
- 复现方式：输入“4人份、糖 100 克、黄油 100 克、步骤：混合糖 100 克与黄油 100 克。”；锁定糖，再调为 8 人。
- 实际结果：食材表中糖保持 100 克，但步骤变成“混合糖 200 克与黄油 200 克”。
- 预期行为：步骤中糖仍为 100 克，只有黄油改为 200 克。
- 修复方向：逐个绑定明确的食材引用，不能仅凭整行包含食材名称就替换行内所有同额片段。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:502)。

### IC-08｜P1｜数值子串匹配误改无关数量

- 对应计划：第二阶段。
- 复现方式：输入“4人份、面粉 40 克、水 100 毫升、备注：面粉另备 140 克，不参与配方缩放。”；调为 8 人。
- 实际结果：面粉变为 80 克，但备注的 140 克被改成 180 克。
- 预期行为：面粉原用量更新，明确不参与缩放的另备 140 克保持不变。
- 修复方向：使用完整数值边界与来源位置，并识别排除条件，避免“40 克”匹配到“140 克”内部。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:496)。

### IC-09｜P1｜分数与范围数量被静默遗漏

- 对应计划：第二阶段。
- 复现方式：输入“4人份、米 400 克、水 200 毫升、糖 1/2 杯、盐 2-3 克”；调为 8 人。
- 实际结果：米和水翻倍，但糖仍为 1/2 杯、盐仍为 2-3 克，且没有未处理提示。
- 预期行为：分别更新为 1 杯、4-6 克；无法处理时标明相关片段未完成。
- 修复方向：补充结构化分数与上下限支持，并使未识别的潜在关联量进入不完整结果提示。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:73)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:546)。

### IC-10｜P1｜高精度原值无法正确替换

- 对应计划：第二阶段。
- 复现方式：输入“4人份、酵母 0.125 克、面粉 200 克”；调为 8 人。
- 实际结果：面粉变为 400 克，酵母仍为 0.125 克。替换时原值先格式化为两位小数，与原文不匹配。
- 预期行为：酵母正确更新为 0.25 克，展示格式不能改变原文定位依据。
- 修复方向：保留原始数值片段及精度，将数值计算、原文定位和结果展示分开。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:488)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:880)。

### IC-11｜P2｜休息时长控件未生成，计算也未使用该变量

- 对应计划：第三阶段。
- 复现方式：输入“14:00–14:45 分享、14:45–15:00 休息、15:00–15:30 讨论”。另在测试会话中手动补入休息时长变量，将 15 分钟改为 30 分钟。
- 实际结果：自然输入仅生成开始时间控件；名称解析只取到部分名称，无法匹配“休息”。手动补入变量后，时间表仍保持原样。后半项属于计算层检查，不代表界面已有该控件。
- 预期行为：生成休息时长控件；调整后休息为 14:45–15:15，讨论为 15:15–15:45，仅影响依赖该休息的环节。
- 修复方向：修正环节名称解析，并把时长变量纳入后续依赖计算，不能只声明变量类型。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:246)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:354)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:588)。

### IC-12｜P1｜固定预约被移动且未检测重叠

- 对应计划：第三、四阶段。
- 复现方式：输入“14:00–15:00 分享、15:00–15:30 固定预约不可改”；开始时间调为 14:30。
- 实际结果：分享变成 14:30–15:30，固定预约也变成 15:30–16:00，冲突列表为空。
- 预期行为：预约保持 15:00–15:30，并提示分享与预约重叠 30 分钟。
- 修复方向：识别固定事项，保留其时间；对移动事项与固定事项统一检查重叠及先后约束。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:323)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:599)。

### IC-13｜P2｜跨午夜仅回绕时钟，未标明跨日

- 对应计划：第三阶段。
- 复现方式：输入“22:00–22:30 分享、22:30–23:00 讨论”；开始时间调为 23:45。
- 实际结果：输出“23:45–00:15 分享、00:15–00:45 讨论”，没有次日、日期或需核对提示。
- 预期行为：明确标记跨日后的日期或“次日”，保留完整时间先后关系。
- 修复方向：在计算中保存日期偏移，不只对分钟数取 24 小时余数；日期语义参与约束检查。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:602)。

### IC-14｜P1｜已识别的日期格式不能同步替换

- 对应计划：第三阶段。
- 复现方式：输入“出发日期：2026/10/01”，下方为第 1 天 10月1日周四、第 2 天 10月2日周五；出发日调为 2026-10-05。
- 实际结果：下方日程变为 10月5日、10月6日，但出发日期仍显示 2026/10/01。
- 预期行为：基准日期与各依赖日期同步更新，保留或一致转换原格式。
- 修复方向：复用解析得到的日期来源范围和格式，不依靠固定的另一种格式重新查找。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:386)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:732)。

### IC-15｜P2｜仅有相对日序时未生成日期与星期

- 对应计划：第三阶段。
- 复现方式：输入“开始日期：2026-10-01、第 1 天：准备、第 2 天：交付”；开始日期调为 2026-10-05。
- 实际结果：只有开始日期更新，第 2 天仍没有推导出的 10月6日及星期。
- 预期行为：按相对日序生成可核对的新日期与星期，不要求原文事先含有具体日期才能联动。
- 修复方向：根据日序与日期基准渲染结果，兼容原文只有相对表达的情况。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:768)。

### IC-16｜P1｜固定日期脱离行程没有冲突提示

- 对应计划：第三、四阶段。
- 复现方式：原出发日为 2026-10-01，第 3 天 10月3日为固定演出；将出发日改为 10月5日。
- 实际结果：演出日期保留在 10月3日，但仍列为第 3 天，冲突列表为空。
- 预期行为：提示固定演出早于出发日、与日序矛盾；保留真实约束供用户处理。
- 修复方向：在保留固定日期之外，检查其与新基准、相对日序及其他事项的关系。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:755)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:800)。

### IC-17｜P1｜长文本调整导致尾部丢失

- 对应计划：第一、五阶段。
- 复现方式：输入“4人份\n米 400 克\n水 200 毫升\n” + 重复 17,000 次的“说明文字” + “尾部必须保留”，共 68,027 字符；调为 8 人。
- 实际结果：调整结果只有 65,536 字符，“尾部必须保留”消失。分析入口将截断后的扫描文本作为会话原文。
- 预期行为：限制分析范围时仍完整保留原文；允许局部调整并明确未分析范围，或放弃该条分析。
- 修复方向：将扫描窗口与完整来源分开；任何调整和粘贴结果都不能静默丢弃未扫描内容。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:15)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:151)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:578)。

### IC-18｜P2｜普通会议记录不能使用粘贴变焦

- 对应计划：第六阶段。
- 复现方式：输入“会议记录：客户希望增加导出功能。团队建议先调研，尚未决定是否开发。小王周五整理访谈反馈。”。
- 实际结果：分析结果为 nil，未生成信息层级。变焦入口依赖先成功识别数量、排期等内容控件。
- 预期行为：适合压缩的普通文本可以独立进入变焦，不必先包含可计算的数值关系。
- 修复方向：将信息层级适用性与数值控件识别分离，并保留建议、决定和未决事项的区别。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:10)、[PreviewOverlay.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PreviewOverlay.swift:31)。

### IC-19｜P1｜简短变焦输出隐藏未解决约束

- 对应计划：第六阶段。
- 复现方式：日程包含“必须在 16:45 结束”；调整后结束时间为 17:00，再选择一句话层级。
- 实际结果：会话中已有“超时 15 分钟”警告，但输出只有“日程安排：15:30 开始，共 3 个环节”，没有截止时间或冲突信息。
- 预期行为：简短结果保留未解决冲突及必要上下文，或要求处理后才能作为完整结果输出。
- 修复方向：把约束和冲突纳入各层级结果生成，复制内容不能依赖留在界面上的提示才可理解。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:852)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:578)。

### IC-20｜P2｜会话缓存缺少内容版本校验

- 对应计划：第四、五阶段。
- 复现方式：先对条目建立 4 人份会话，再构造相同条目 ID、正文已改为 8 人份的新条目，调用 interactiveSession(for:)。
- 实际结果：接口仍返回 4 人份原文对应的旧会话。此项为接口级复现：saveEdit 和 handleCaptured 已有缓存失效调用，不能据此声称普通界面编辑必然失效。
- 预期行为：即使调用方传入了同 ID 的新版本，接口也能识别并重新分析，不依赖每条更新路径都主动清理。
- 修复方向：缓存键加入正文版本或内容指纹，读取时校验；保留已有主动失效机制。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:505)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:283)。

### IC-21｜P1｜缺失基准可被快捷调节绕过

- 对应计划：第一、五阶段。
- 复现方式：输入“米 400 克、水 200 毫升”，未补充原始人数，直接触发主变量加一操作。
- 实际结果：默认按原始 4 人计算，米变为 500 克、水变为 250 毫升；缺失基准提示仍未解决。
- 预期行为：原始人数明确之前，鼠标、快捷键和复制调整结果等入口都不能执行猜测性的缩放。
- 修复方向：在统一调节入口校验缺失条件；补充信息后才启用相关计算，不能只隐藏界面按钮。
- 代码位置：[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:129)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:595)、[PanelController.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift:265)。

## 五、代码检查确认的交互缺项

以下内容由实现检查确认，本次未通过真实界面操作验收；与上文运行复现的问题分开记录。

### IC-22｜P2｜参数不能直接输入，缺失人数仅有三个选项

- 对应计划：第一、五阶段。
- 确认方式：代码检查。
- 当前实现：变量值由 Text 展示，旁边只有加减按钮；没有数字输入、时间输入或日期选择器。缺失人数仅提供 1、2、4 三个按钮。
- 预期行为：支持直接输入任意有效参数、选择日期和时间；缺失基准允许填写真实值，不应只限于候选按钮。
- 代码位置：[InteractiveControlView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/InteractiveControlView.swift:201)、[InteractiveControlView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/InteractiveControlView.swift:246)。

### IC-23｜P2｜对比、撤销与手动编辑保护尚未实现

- 对应计划：第四、五阶段。
- 确认方式：代码检查。
- 当前实现：“对比”只展示调整后文本，未给出原文或改动高亮；现有重置恢复所有基准参数，没有单步撤销；结果预览为只读 Text，没有受控值编辑后的固定或交回控件管理流程。
- 预期行为：提供原文与改动对应、单步撤销、调整结果编辑及用户修改保护，避免用户为小改动重新整理整份内容。
- 代码位置：[InteractiveControlView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/InteractiveControlView.swift:294)、[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:517)。

### IC-24｜P2｜变焦交互、信息锁定与逐层编辑缺失

- 对应计划：第六阶段。
- 确认方式：代码检查。
- 当前实现：目前通过按钮切换少量固定层级；没有计划中的独立按住预览、滚动选层、松开粘贴流程，也没有锁定重要信息、省略来源对照或逐层编辑状态。
- 预期行为：完成计划描述的独立变焦交互，并将关键事实、否定、条件和未决事项保留在可理解的上下文中。
- 代码位置：[InteractiveControlView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/InteractiveControlView.swift:451)、[PanelController.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift:224)、[InteractiveControlEngine.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveControlEngine.swift:815)、[InteractiveClipModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/InteractiveClipModel.swift:207)。

### IC-25｜P2｜本地分析设置未连接到智能分析能力

- 对应计划：第一、五阶段。
- 确认方式：代码检查。
- 当前实现：interactiveClipsLocalOnly 只在设置中读写；当前内容控件分析始终调用本地规则引擎，没有根据该开关接入模型理解，也没有内容控件云分析的主动与自动触发控制。未发现因此上传历史的行为。
- 预期行为：实现用户授权范围内的模型辅助理解及触发设置；如当前版本仅支持本地，应让设置准确表达实际能力。
- 代码位置：[PanelViewModel.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:475)、[SettingsView.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Settings/SettingsView.swift:976)、[AppSettings.swift](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Settings/AppSettings.swift:306)。

## 六、修复后的复核重点

1. 先确认长文本完整保留、金额和数量只改动对应字段、锁定值在所有输出中一致、固定时间与日期不会被静默改动。
2. 使用本报告的输入重跑各项复现，同时保留现有 98 个测试；必须以断言结果判断，不以“✅”显示判断。
3. 验证不同业务内容中的相同关系可复用，以及一份内容同时包含多种关系时的联动范围；不能只增加几个固定场景模板来满足示例。
4. 补齐直接输入、缺失信息填写、撤销、编辑保护和变焦交互后，再进行真实界面与目标应用粘贴验收，核对当前预览与实际粘贴内容一致。

本报告不将“现有测试全部通过”视为产品整体通过，也不将尚未完成的界面、云模型或性能验证视为已通过。
