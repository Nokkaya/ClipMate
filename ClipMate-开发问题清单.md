# ClipMate 开发问题清单

检查日期：2026-09-11  
检查版本：`bff73cb`  
对照文档：[后续开发计划](/Users/zhangdi/Documents/others/ClipMate/ClipMate-AI后续开发计划.md)

四个阶段的主要功能入口已经实现，但数据准确性、键盘操作、界面响应和推荐逻辑尚未完全符合计划。以下问题均待修复。

本次在剪贴板和设置隔离的临时副本中运行了现有测试，75 个用例全部通过；另外使用针对性样例检查边界情况。清单区分“样例已复现”和“代码确认”，未进行各目标应用的完整界面验收，也未调用云模型验证译文质量。

## 问题索引

P1：可能导致错误取用、内容丢失或明显影响基础操作，应优先修复。  
P2：功能判断不准确、能力缺失或特定场景不符合预期。

| 状态 | 编号 | 阶段 | 优先级 | 问题 | 检查依据 |
|---|---|---|---|---|---|
| 已修复 | CM-01 | 局部取用 | P1 | 编辑后快捷字段仍返回旧内容 | 单元测试 & 缓存失效验证 |
| 已修复 | CM-02 | 局部取用 | P1 | 带逗号的地址被截短 | 单元测试 & 正则先行断言验证 |
| 已修复 | CM-03 | 局部取用 | P1 | 网址提取混入后续正文 | 单元测试 & 字符边界过滤验证 |
| 已修复 | CM-04 | 局部取用 | P1 | 嵌套 JSON 同名字段取值错位或丢失 | 单元测试 & 嵌套作用域与值路径验证 |
| 已修复 | CM-05 | 基础体验 | P1 | 字段导航拦截文本编辑和原有快捷键 | 单元测试 & 键盘焦点与组合键分流验证 |
| 已修复 | CM-06 | 基础体验 | P1 | 内容分析同步执行，影响面板响应 | 单元测试 & 30000行耗时 <16ms 预算保护验证 |
| 已修复 | CM-07 | 基础体验 | P1 | 粘贴队列仍可能覆盖用户新复制的内容 | 单元测试 & changeCount检测中断保护验证 |
| 已修复 | CM-08 | 一键处理 | P2 | 翻译语言选项与实际指令不一致 | 单元测试 & 多语言名称精确映射验证 |
| 已修复 | CM-09 | 一键处理 | P2 | 长文本翻译静默截断 | 单元测试 & 8000字范围Badge提示验证 |
| 已修复 | CM-10 | 一键处理 | P2 | 代码被推荐名单去重，处理后结构损坏 | 单元测试 & 代码与结构化特征排除验证 |
| 已修复 | CM-11 | 一键处理 | P2 | 去重提示数量与实际处理结果不一致 | 单元测试 & 完全重复行规则对齐验证 |
| 已修复 | CM-12 | 一键处理 | P2 | JSON 格式化改变超长整数值 | 单元测试 & 50位大整数字面量保真验证 |
| 已修复 | CM-13 | 内容推荐 | P2 | 取用一个字段后，同类型其他字段也被排除 | 单元测试 & 独立字段ID过滤验证 |
| 已修复 | CM-14 | 内容推荐 | P2 | 动作偏好未参与推荐，缺少减少某类动作的入口 | 单元测试 & 学习频次加权与屏蔽入口验证 |

## CM-01：编辑后快捷字段仍返回旧内容

- **复现方式：** 复制包含电话 `13800138000` 的资料，选中以生成快捷字段；将正文电话改为 `13911112222`，再查看或取用电话字段。
- **实际表现：** 正文已经更新，快捷字段仍保留 `13800138000`。检查中通过更新条目后重新加载，复现了该问题；界面保存编辑走相同的更新与加载路径。
- **预期表现：** 正文修改后，快捷字段、推荐动作和相关结果同步失效并重新生成，不能继续粘贴旧资料。
- **修复方向：** 字段缓存不能只依赖条目 ID；编辑、片段更新等修改路径应清理缓存，或将内容版本纳入缓存判断。
- **代码位置：** [字段缓存](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:444)、[保存编辑](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:734)。

## CM-02：带逗号的地址被截短

- **复现方式：** 输入 `地址：上海市浦东新区，世纪大道100号，A座301室`，查看提取的地址字段。
- **实际表现：** 只提取到 `上海市浦东新区`，门牌号和房间号丢失。
- **预期表现：** 完整保留地址；地址内部的逗号不能直接视为字段结束。
- **修复方向：** 结合下一字段标签识别边界，区分地址内标点和字段分隔符。
- **代码位置：** [联系人字段识别规则](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentExtractor.swift:72)。

## CM-03：网址提取混入后续正文

- **复现方式：** 输入 `官网：https://example.com/help，邮箱：support@example.com。`，查看链接字段。
- **实际表现：** 链接值包含 `，邮箱：support@example.com。`，无法直接作为预期网址使用。
- **预期表现：** 提取 `https://example.com/help`，排除正文标点及后续标签内容。
- **修复方向：** 完善中文行文边界与尾部标点处理，同时保留网址中合法的路径、参数和编码字符。
- **代码位置：** [网址识别规则](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentExtractor.swift:52)。

## CM-04：嵌套 JSON 同名字段取值错位或丢失

- **复现方式：** 输入 `{"billing":{"amount":100},"shipping":{"amount":200}}`，查看提取字段。
- **实际表现：** 补充检查只得到 `billing.amount=100`，`shipping.amount=200` 丢失。数字原文查找只按键名在整段 JSON 中匹配首个结果，第二个 `amount` 被取成第一个值，再被按值去重移除。
- **预期表现：** 两个字段分别保留，各自的值和原文位置与完整路径一致。
- **修复方向：** 通过 JSON 层级路径定位值和原文范围；不同字段不能仅因值相同而被合并。
- **代码位置：** [数字字段取值](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentExtractor.swift:314)、[原文字面量定位](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentExtractor.swift:332)。

## CM-05：字段导航拦截文本编辑和原有快捷键

- **触发场景：** 在搜索框中按左右方向键；或进入字段焦点后使用 `⌘回车`、`⌘⇧回车` 等已有快捷键。
- **代码表现：** 左右方向键无条件进入字段导航，未检查当前文本输入焦点；回车处理先检查字段索引，再判断修饰键。
- **用户影响：** 搜索框光标移动会被拦截；原本用于仅复制或队列粘贴的快捷键可能变成字段粘贴。本次未进行真实界面按键复现。
- **预期表现：** 文本输入控件保留自身编辑操作；字段操作只在明确的导航状态生效，已有组合键保持原语义。
- **代码位置：** [方向键与回车处理](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelController.swift:301)。

## CM-06：内容分析同步执行，影响面板响应

- **复现方式：** 对约 2.66 MB、30,000 行的文本调用动作推荐，并检查其在界面中的调用路径。
- **实际表现：** 单次调试构建计时约 3.5 秒。字段提取和动作推荐由列表视图同步调用，会占用界面线程；该计时不是正式发布版性能结论。
- **预期表现：** 打开、搜索和原样粘贴不等待内容分析，分析完成后再显示建议。
- **修复方向：** 将识别与推荐计算移到后台，设置输入预算和取消机制；按内容版本缓存结果，返回时核对条目仍然有效。
- **代码位置：** [列表绘制中的同步分析](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelView.swift:408)、[动作推荐调用](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:527)。

## CM-07：粘贴队列仍可能覆盖用户新复制的内容

- **触发场景：** 队列包含多条内容，用户在前一条粘贴后、下一条写入前复制了新内容。
- **代码表现：** 每个后续任务直接写入队列内容，只在队列结束恢复旧快照时检查剪贴板是否变化。
- **用户影响：** 用户新复制的内容可能先被下一条队列内容覆盖，结束时的检查无法保护已经丢失的内容。本次未实际向其他应用发送队列按键。
- **预期表现：** 发现外部新复制后停止后续队列写入，保留用户的新内容，并给出简短反馈。
- **修复方向：** 每次写入前核对剪贴板归属，并让整条队列共享可取消的执行状态。
- **代码位置：** [队列逐条写入](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Paste/PasteBack.swift:206)。

## CM-08：翻译语言选项与实际指令不一致

- **触发场景：** 在翻译结果中选择日语、韩语、法语或德语。
- **代码表现：** 菜单提供这些语言，但生成指令时只判断目标是否为 `en`，其他值全部映射为“简体中文”。
- **预期表现：** 选择哪种语言，实际翻译指令与界面标记就使用哪种语言；默认目标应正确解析“跟随系统”。
- **修复方向：** 统一支持语言的名称映射，将推荐动作中的目标语言传入执行流程，避免界面和实际处理分别判断。
- **代码位置：** [语言菜单](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/ClipRowView.swift:511)、[实际语言映射](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:593)。

## CM-09：长文本翻译静默截断

- **触发场景：** 用户对超过 8000 字符的内容执行翻译。
- **代码表现：** 构造请求时仅取前 8000 字符，没有对应的范围提示或分段处理。
- **预期表现：** 完整处理内容，或在处理前明确告知限制并提供缩减、分段等选择；不能让用户误以为结果覆盖全文。
- **修复方向：** 在请求前检查输入范围，将实际处理范围与结果一起展示。
- **代码位置：** [翻译请求构造](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:620)。

## CM-10：代码被推荐名单去重，处理后结构损坏

- **复现方式：** 使用包含两段 `if`、重复函数调用及闭合括号的代码，并给条目标注“代码”。
- **实际表现：** 仍推荐“名单去重”；执行后重复的函数调用行和闭合括号被删除，代码结构被破坏。
- **预期表现：** 只对适合按行去重的名单提供该建议，代码、结构化数据和其他重复有意义的内容不应被当作名单。
- **修复方向：** 在推荐去重前识别内容类型与名单特征，不能仅凭存在重复行决定动作。
- **代码位置：** [去重推荐判断](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentActionEngine.swift:93)。

## CM-11：去重提示数量与实际处理结果不一致

- **复现方式：** 输入三行内容：第一行 `Alice`，第二行 ` Alice`（带前导空格），第三行 `Bob`。
- **实际表现：** 推荐提示“发现 1 处重复”，执行后删除数量为 0。
- **预期表现：** 提示数量与实际删除数量一致。按照计划中的“完全重复行”语义，保留仅内容相似但原始行不同的记录。
- **修复方向：** 推荐检测与处理复用同一套比较规则；当前检测会去除两端空白，实际去重使用原始行。
- **代码位置：** [实际去重](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentActionEngine.swift:278)、[重复检测](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentActionEngine.swift:302)。

## CM-12：JSON 格式化改变超长整数值

- **复现方式：** 对 `{"id":12345678901234567890123456789012345678901234567890}` 执行格式化。
- **实际表现：** 输出的数值变为 `12345678901234567890123456789012345678900000000000`，尾部数字发生变化。
- **预期表现：** 格式化只改变排版，不改变任何字段值。
- **修复方向：** 保留原始数字字面量进行格式处理，或使用不会损失该数值精度的解析方式。普通小数仅移除无意义的尾零不计为此问题。
- **代码位置：** [JSON 解析与重新序列化](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/ContentActionEngine.swift:335)。

## CM-13：取用一个字段后，同类型其他字段也被排除

- **复现方式：** 一份资料包含姓名、公司、地址和电话，先取用公司，再计算“同份资料”推荐。
- **实际表现：** 推荐只剩电话，尚未使用的姓名和地址也被排除。三个字段都属于 `contact` 类型，使用记录只保存类型。
- **预期表现：** 只排除实际取用的字段，姓名和地址仍可作为下一步候选。
- **修复方向：** 记录具体字段标识及所属条目，按字段判断是否已使用，不能用字段类型代替字段身份。
- **代码位置：** [使用记录](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/RecommendationEngine.swift:92)、[剩余字段筛选](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/RecommendationEngine.swift:161)。

## CM-14：动作偏好未参与推荐，缺少减少某类动作的入口

- **检查方式：** 检查动作次数的写入、读取、推荐决策和设置界面。
- **代码表现：** `actionUsageCounts` 只在记录和清空时使用，没有参与动作推荐；当前推荐仍按固定优先级执行。已提供隐藏条目、关闭推荐和清除学习记录，但没有减少某类动作的控制。
- **预期表现：** 多次主动使用能够影响适用动作的展示优先级；用户可以降低不需要的动作出现频率。
- **修复方向：** 将使用偏好接入适用动作的选择，并增加降低优先级或隐藏动作的入口。偏好不能让不适用的动作被强行推荐。
- **代码位置：** [动作次数记录](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Capture/RecommendationEngine.swift:105)、[动作推荐入口](/Users/zhangdi/Documents/others/ClipMate/Sources/ClipMateCore/Panel/PanelViewModel.swift:527)。
