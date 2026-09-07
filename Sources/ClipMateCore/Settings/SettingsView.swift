import SwiftUI
import AppKit

/// 设置窗口：通用 / 片段 / 采集 / 隐私 / AI / 脚本 / 关于。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore
    let ai: AIService
    let frontApps: FrontAppTracker

    var body: some View {
        TabView {
            GeneralTab(settings: settings, store: store)
                .tabItem { Label("通用", systemImage: "gearshape") }
            SnippetsTab(store: store)
                .tabItem { Label("片段", systemImage: "bookmark") }
            CaptureTab(settings: settings, store: store)
                .tabItem { Label("采集", systemImage: "doc.on.doc") }
            PrivacyTab(settings: settings, frontApps: frontApps)
                .tabItem { Label("隐私", systemImage: "hand.raised") }
            AITab(settings: settings, ai: ai)
                .tabItem { Label("AI", systemImage: "sparkles") }
            ScriptsTab(settings: settings)
                .tabItem { Label("脚本", systemImage: "terminal") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 670, height: 540)
    }
}

// MARK: - 通用卡片与行布局组件

/// 统一风格的设置卡片容器
private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    var iconColor: Color
    var trailingView: AnyView?
    let content: Content

    init(
        _ title: String,
        icon: String,
        iconColor: Color = .accentColor,
        @ViewBuilder trailing: () -> some View = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.trailingView = AnyView(trailing())
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 6).fill(iconColor.opacity(0.12)))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let trailingView {
                    trailingView
                }
            }
            Divider().overlay(Color.primary.opacity(0.06))
            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// 统一风格的设置项行布局
private struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    let control: Control

    init(_ title: String, subtitle: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            control
        }
    }
}

// MARK: - 数据备份与恢复辅助类

@MainActor
private enum BackupHelper {
    static func exportBackup(store: ClipStore) {
        let savePanel = NSSavePanel()
        savePanel.title = "导出剪贴板历史与片段备份"
        savePanel.nameFieldStringValue = "ClipMate-Backup-\(Int(Date().timeIntervalSince1970)).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            let data = try store.exportJSON()
            try data.write(to: url)
            HapticHelper.generic()
            let alert = NSAlert()
            alert.messageText = "导出成功"
            alert.informativeText = "已成功将 \(store.itemCount()) 条记录备份至：\n\(url.lastPathComponent)"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "导出失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    static func importBackup(store: ClipStore) {
        let openPanel = NSOpenPanel()
        openPanel.title = "从备份文件恢复"
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let count = try store.importJSON(data)
            HapticHelper.generic()
            let alert = NSAlert()
            alert.messageText = "恢复成功"
            alert.informativeText = "新入库 \(count) 条记录（已有相同内容已自动跳过合并）。"
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = "恢复失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

// MARK: - 通用 Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 交互与启动
                SettingsCard("交互与常规设置", icon: "gearshape.fill", iconColor: .accentColor) {
                    VStack(spacing: 10) {
                        SettingsRow("全局热键", subtitle: "随时随地呼出或隐藏 ClipMate 主搜索面板") {
                            Picker("", selection: $settings.hotkeyPresetID) {
                                ForEach(AppSettings.hotkeyPresets) { preset in
                                    Text(preset.display).tag(preset.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("面板出现位置", subtitle: "选择主面板在多显示器或光标附近的定位策略") {
                            Picker("", selection: $settings.panelPositionMode) {
                                ForEach(PanelPositionMode.allCases) { mode in
                                    Text(L10n.positionModeTitle(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("界面显示语言", subtitle: "自定义应用程序的界面语言或自动跟随系统") {
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(L10n.languageTitle(lang)).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("开机自动启动", subtitle: "登录 macOS 系统时在后台自动启动常驻") {
                            Toggle("", isOn: $settings.launchAtLogin)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("剪贴板提示音", subtitle: "捕获到新的剪贴板内容时播放提示音") {
                            Toggle("", isOn: $settings.soundOnCapture)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("触控板触觉反馈", subtitle: "复制、粘贴、清空等操作时触发触控板轻微震动") {
                            Toggle("", isOn: $settings.hapticFeedbackEnabled)
                                .toggleStyle(.switch)
                        }
                    }
                }


                // 卡片 2: 备份与恢复
                SettingsCard(
                    "数据备份与迁移",
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .blue,
                    trailing: {
                        Text("历史 \(store.itemCount()) 条 · 片段 \(store.allSnippets().count) 条")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("支持将本地存储的全部剪贴板历史与自定义片段完整导出为 JSON 备份文件，换机或重装时可无损导入合并。")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                BackupHelper.exportBackup(store: store)
                            } label: {
                                Label("导出完整备份 (JSON)", systemImage: "square.and.arrow.up")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                BackupHelper.importBackup(store: store)
                            } label: {
                                Label("从备份恢复 (JSON)", systemImage: "square.and.arrow.down")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // 卡片 3: 快捷键指南
                SettingsCard("主面板常用快捷键", icon: "keyboard.fill", iconColor: .purple) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        shortcutBadge(key: "⏎ 回车", action: "粘贴至当前光标处")
                        shortcutBadge(key: "⌘⏎", action: "复制到剪贴板并置顶")
                        shortcutBadge(key: "⌥⏎", action: "原地快速编辑正文")
                        shortcutBadge(key: "⌘K", action: "唤起 AI 智能助手")
                        shortcutBadge(key: "⌘I", action: "开关详情抽屉预览")
                        shortcutBadge(key: "⌘1 ~ 9", action: "一键快速贴出指定序号项")
                        shortcutBadge(key: "⇧↑ / ⇧↓", action: "多选选中多条记录")
                        shortcutBadge(key: "Tab", action: "快速在分类栏间轮换")
                    }
                }
            }
            .padding(16)
        }
        .modernScrollbar()
    }

    private func shortcutBadge(key: String, action: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(action)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 片段管理 Tab

private struct SnippetsTab: View {
    let store: ClipStore
    @State private var snippets: [ClipItem] = []
    @State private var groups: [String] = []
    @State private var selectedGroup: String? = nil
    @State private var searchKeyword = ""
    @State private var showEditor = false
    @State private var editingID: Int64? = nil
    @State private var draftTitle = ""
    @State private var draftGroup = ""
    @State private var draftShortcode = ""
    @State private var draftContent = ""
    @State private var copiedID: Int64? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 顶部搜索与操作栏
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("搜索片段标题、正文或短码…", text: $searchKeyword)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                    if !searchKeyword.isEmpty {
                        Button {
                            searchKeyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )

                Button {
                    openNew()
                } label: {
                    Label("新建片段", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.purple)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // 分组胶囊筛选
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        selectedGroup = nil
                        HapticHelper.alignment()
                    } label: {
                        Text("全部 (\(snippets.count))")
                            .font(.system(size: 11, weight: selectedGroup == nil ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule().fill(
                                    selectedGroup == nil ? Color.purple.opacity(0.2) : Color.primary.opacity(0.05)
                                )
                            )
                            .foregroundStyle(selectedGroup == nil ? Color.purple : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    ForEach(groups, id: \.self) { g in
                        let count = snippets.filter { $0.snippetGroup == g }.count
                        let isSelected = selectedGroup == g
                        Button {
                            selectedGroup = g
                            HapticHelper.alignment()
                        } label: {
                            Text("\(g) (\(count))")
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule().fill(
                                        isSelected ? Color.purple.opacity(0.2) : Color.primary.opacity(0.05)
                                    )
                                )
                                .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .modernScrollbar()

            Divider().overlay(Color.primary.opacity(0.08))
                .padding(.top, 4)

            // 片段卡片列表
            if filteredSnippets.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text(snippets.isEmpty ? "暂无片段，点击右上角新建常用片段" : "未找到匹配的片段")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(snippets.isEmpty ? "可以将常用代码、开票信息、回复模板收录于此" : "尝试更换搜索关键字或分组")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredSnippets) { item in
                            snippetCard(item: item)
                        }
                    }
                    .padding(16)
                }
                .modernScrollbar()
            }
        }
        .onAppear { loadData() }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
    }

    private func snippetCard(item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 头部标题与标签
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.purple)

                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                } else {
                    Text(item.displayText)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }

                if let g = item.snippetGroup, !g.isEmpty {
                    Text("🏷 \(g)")
                        .font(.system(size: 9.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.purple.opacity(0.14)))
                        .foregroundStyle(Color.purple)
                }

                if let sc = item.snippetShortcode, !sc.isEmpty {
                    Text("⚡️ \(sc)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(Color.orange)
                }

                Spacer()

                Text("\(item.plainText.count) 字符")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                // 快捷操作按钮
                HStack(spacing: 4) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.plainText, forType: .string)
                        copiedID = item.id
                        HapticHelper.feedback()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedID == item.id { copiedID = nil }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                            if copiedID == item.id {
                                Text("已复制").font(.system(size: 10))
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(copiedID == item.id ? Color.green : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("复制片段内容")

                    Button {
                        openEdit(item: item)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help("编辑片段")

                    Button {
                        deleteSnippet(item: item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("删除片段")
                }
            }

            // 片段正文预览框
            Text(item.plainText)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.03)))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private var filteredSnippets: [ClipItem] {
        snippets.filter { item in
            if let selectedGroup, item.snippetGroup != selectedGroup { return false }
            if !searchKeyword.isEmpty {
                let kw = searchKeyword.lowercased()
                let matchTitle = item.title?.lowercased().contains(kw) ?? false
                let matchContent = item.plainText.lowercased().contains(kw)
                let matchShortcode = item.snippetShortcode?.lowercased().contains(kw) ?? false
                return matchTitle || matchContent || matchShortcode
            }
            return true
        }
    }

    private func loadData() {
        snippets = store.allSnippets()
        groups = store.allSnippetGroups()
    }

    private func openNew() {
        editingID = nil
        draftTitle = ""
        draftGroup = selectedGroup ?? ""
        draftShortcode = ""
        draftContent = ""
        showEditor = true
    }

    private func openEdit(item: ClipItem) {
        editingID = item.id
        draftTitle = item.title ?? ""
        draftGroup = item.snippetGroup ?? ""
        draftShortcode = item.snippetShortcode ?? ""
        draftContent = item.plainText
        showEditor = true
    }

    private func deleteSnippet(item: ClipItem) {
        try? store.delete(item.id)
        loadData()
        HapticHelper.generic()
    }

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 头部
            HStack(spacing: 8) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.purple.opacity(0.15)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(editingID == nil ? "新建常用片段" : "编辑片段")
                        .font(.system(size: 14, weight: .semibold))
                    Text("输入片段信息，保存后支持在主面板和设置中快速调用")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    showEditor = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            // 字段
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("片段标题（可选）", systemImage: "textformat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("如：日常开票信息、Git 常用流、邮箱签名…", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("分组", systemImage: "folder.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("如：开发 / 常用 / 邮件", text: $draftGroup)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("快捷短码（可选）", systemImage: "bolt.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField("如：;tax、;sig", text: $draftShortcode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // 已有分组快速标签
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Text("已有分组:")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            ForEach(groups, id: \.self) { g in
                                Button {
                                    draftGroup = g
                                    HapticHelper.alignment()
                                } label: {
                                    Text(g)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .modernScrollbar()
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("片段正文", systemImage: "doc.text.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(draftContent.count) 字符")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    TextEditor(text: $draftContent)
                        .font(.system(size: 12, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .modernScrollbar()
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                        )
                        .frame(height: 140)
                }
            }

            // 底部操作栏
            HStack {
                Button("取消") {
                    showEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("保存片段") {
                    let content = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !content.isEmpty else { return }
                    if let id = editingID {
                        _ = try? store.updateSnippet(
                            id: id,
                            title: draftTitle,
                            group: draftGroup,
                            shortcode: draftShortcode,
                            text: content
                        )
                    } else {
                        _ = try? store.createSnippet(
                            title: draftTitle,
                            text: content,
                            group: draftGroup,
                            shortcode: draftShortcode
                        )
                    }
                    showEditor = false
                    loadData()
                    HapticHelper.feedback()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.purple)
                .keyboardShortcut(.defaultAction)
                .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - 采集 Tab

private struct CaptureTab: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 留存与清理策略
                SettingsCard("历史容量与留存策略", icon: "clock.arrow.circlepath", iconColor: .blue) {
                    VStack(spacing: 10) {
                        SettingsRow("最多保留条数", subtitle: "超出上限时自动淘汰最旧的历史记录（已固定的条目永不清除）") {
                            HStack(spacing: 6) {
                                Text("\(settings.retentionMaxItems) 条")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing)
                                Stepper("", value: $settings.retentionMaxItems, in: 50...10000, step: 50)
                                    .labelsHidden()
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("保留天数周期", subtitle: "历史记录默认保留的最大时间窗口") {
                            HStack(spacing: 6) {
                                Text("\(settings.retentionMaxAgeDays) 天")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing)
                                Stepper("", value: $settings.retentionMaxAgeDays, in: 1...365)
                                    .labelsHidden()
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("单条内容容量上限", subtitle: "单次复制体积超出该阈值的内容将自动丢弃，防止内存过载") {
                            HStack(spacing: 6) {
                                Text("\(settings.maxCaptureMB) MB")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing)
                                Stepper("", value: $settings.maxCaptureMB, in: 1...100)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                // 卡片 2: 智能识别与增强
                SettingsCard("智能识别与元数据增强", icon: "sparkle.magnifyingglass", iconColor: .purple) {
                    VStack(spacing: 10) {
                        SettingsRow("智能标题生成 (Smart Title)", subtitle: "自动识别代码签名、SQL、CLI命令、Markdown标题及OCR文本，展示更具辨识度的标题") {
                            Toggle("", isOn: $settings.smartTitleEnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("图片文字识别 (Vision OCR)", subtitle: "复制或截取图片入库时，自动提取图中文本建立索引，图片亦可搜") {
                            Toggle("", isOn: $settings.imageOCREnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("网页链接元数据解析", subtitle: "后台轻量解析复制的 URL 页面标题与图标，列表显示更直观") {
                            Toggle("", isOn: $settings.fetchLinkMetadata)
                                .toggleStyle(.switch)
                        }
                    }
                }


                // 卡片 3: 检索引擎
                SettingsCard("数据库与检索引擎", icon: "cylinder.split.1x2", iconColor: .green) {
                    HStack(spacing: 10) {
                        Image(systemName: store.supportsFullTextSearch ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(store.supportsFullTextSearch ? Color.green : Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.supportsFullTextSearch ? "SQLite FTS5 全文检索引擎已就绪" : "系统 SQLite 不支持 FTS5，已降级为 LIKE 检索")
                                .font(.system(size: 12.5, weight: .medium))
                            Text(store.supportsFullTextSearch
                                 ? "支持中文精准分词、倒排索引与毫秒级高亮检索。"
                                 : "基础模糊查询可用，但海量数据下检索耗时略有增加。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .modernScrollbar()
    }
}

// MARK: - 隐私 Tab

private struct PrivacyTab: View {
    @ObservedObject var settings: AppSettings
    let frontApps: FrontAppTracker
    @State private var newBundleID = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 忽略名单
                SettingsCard("忽略应用名单（黑名单）", icon: "hand.raised.fill", iconColor: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("当以下应用处于前台运行激活状态时，所有复制的内容均不会被记录：")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        if settings.excludedApps.isEmpty {
                            HStack {
                                Spacer()
                                Text("当前未添加任何忽略应用")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(settings.excludedApps, id: \.self) { bundle in
                                    HStack(spacing: 8) {
                                        Image(systemName: "app.dashed")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Text(bundle)
                                            .font(.system(size: 11.5, design: .monospaced))
                                        Spacer()
                                        Button {
                                            settings.excludedApps.removeAll { $0 == bundle }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.system(size: 13))
                                                .foregroundStyle(.red.opacity(0.8))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                                }
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        HStack(spacing: 8) {
                            TextField("输入应用 Bundle ID（如：com.1password.mac）", text: $newBundleID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))

                            Button("添加") {
                                let id = newBundleID.trimmingCharacters(in: .whitespaces)
                                if !id.isEmpty, !settings.excludedApps.contains(id) {
                                    settings.excludedApps.append(id)
                                }
                                newBundleID = ""
                            }
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button("一键添加前台应用") {
                                if let app = frontApps.lastNonSelfApp,
                                   let bundle = app.bundleIdentifier,
                                   !settings.excludedApps.contains(bundle) {
                                    settings.excludedApps.append(bundle)
                                }
                            }
                        }
                    }
                }

                // 卡片 2: 采集与临时状态
                SettingsCard("采集安全与临时暂停", icon: "lock.shield.fill", iconColor: .green) {
                    VStack(spacing: 10) {
                        SettingsRow("临时暂停采集", subtitle: "使用密码管理器或处理高密敏感内容时可临时关闭采集") {
                            Toggle("", isOn: $settings.pauseCapture)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text("系统安全自适应：当检测到密码输入框（NSSecureTextField / Concealed）或屏幕锁定状态时，ClipMate 会全自动静默停止采集，无需手动干预。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .modernScrollbar()
    }
}

// MARK: - AI Tab

private struct AITab: View {
    @ObservedObject var settings: AppSettings
    let ai: AIService
    @State private var apiKeyDraft = ""
    @State private var testResult = ""
    @State private var testing = false
    @State private var newPromptName = ""
    @State private var newPromptTemplate = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 智能特性开关
                SettingsCard("AI 核心特性", icon: "sparkles", iconColor: .purple) {
                    VStack(spacing: 10) {
                        SettingsRow("启用 AI 智能操作", subtitle: "在主面板中选中条目后按 ⌘K 唤起工作台，进行快速润色、总结与问答") {
                            Toggle("", isOn: $settings.aiEnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow("本地语义向量检索", subtitle: "利用 macOS 本地句向量按语义理解检索历史，无网络请求与隐私泄露") {
                            Toggle("", isOn: $settings.semanticSearchEnabled)
                                .toggleStyle(.switch)
                                .disabled(!EmbeddingService.isAvailable)
                        }

                        if !EmbeddingService.isAvailable {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                Text("当前系统未提供句向量资源，语义搜索不可用（不影响关键词检索）")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // 卡片 2: API 与模型配置
                SettingsCard("模型服务与 API 配置", icon: "server.rack", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API 端点（兼容 OpenAI / Ollama / DeepSeek / 本地服务）")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("https://api.openai.com/v1 或 http://localhost:11434/v1", text: $settings.aiEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("模型名称")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("如：gpt-4o-mini / deepseek-chat / qwen2.5:7b", text: $settings.aiModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("API 密钥（安全存储于本地系统钥匙串 Keychain；本地服务可留空）")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                SecureField("sk-…", text: $apiKeyDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                Button("保存密钥") {
                                    settings.aiAPIKey = apiKeyDraft
                                    testResult = "密钥已保存至本地钥匙串"
                                    HapticHelper.feedback()
                                }
                                .disabled(apiKeyDraft.isEmpty)
                            }
                        }

                        HStack(spacing: 8) {
                            Button("测试连接") {
                                testing = true
                                Task { @MainActor in
                                    testResult = await ai.testConnection()
                                    testing = false
                                    HapticHelper.generic()
                                }
                            }
                            if testing { ProgressView().controlSize(.small) }
                            Text(testResult)
                                .font(.system(size: 11))
                                .foregroundStyle(testResult.contains("成功") ? Color.green : Color.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                // 卡片 3: 提示词模板库
                SettingsCard(
                    "自定义提示词模板",
                    icon: "text.badge.plus",
                    iconColor: .indigo,
                    trailing: {
                        Button("恢复精选模板") {
                            settings.customPrompts = PromptTemplate.defaults
                            HapticHelper.feedback()
                        }
                        .font(.system(size: 11))
                    }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("支持在提示词中包含 {content} 变量，执行时将自动替换为剪贴板选中的正文。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 4) {
                            ForEach(settings.customPrompts) { prompt in
                                HStack {
                                    Label(prompt.name, systemImage: prompt.icon)
                                        .font(.system(size: 11.5, weight: .medium))
                                    Spacer()
                                    Text(String(prompt.template.prefix(40)) + "…")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                    Button {
                                        settings.customPrompts.removeAll { $0.id == prompt.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        HStack(spacing: 8) {
                            TextField("模板名（如：代码转TS）", text: $newPromptName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                                .frame(width: 140)
                            TextField("提示词内容（包含 {content} 占位变量）", text: $newPromptTemplate)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button("添加") {
                                let n = newPromptName.trimmingCharacters(in: .whitespaces)
                                let t = newPromptTemplate.trimmingCharacters(in: .whitespaces)
                                guard !n.isEmpty, !t.isEmpty else { return }
                                settings.customPrompts.append(PromptTemplate(name: n, icon: "sparkle", template: t))
                                newPromptName = ""
                                newPromptTemplate = ""
                                HapticHelper.feedback()
                            }
                            .disabled(newPromptName.trimmingCharacters(in: .whitespaces).isEmpty || newPromptTemplate.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .padding(16)
        }
        .modernScrollbar()
        .onAppear { apiKeyDraft = settings.aiAPIKey }
    }
}

// MARK: - 脚本 Tab

private struct ScriptsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 安全规范说明
                SettingsCard("脚本动作规范", icon: "shield.checkered", iconColor: .blue) {
                    Text("自定义脚本将在主面板 ⌘K 智能操作浮层中列出。选中的剪贴板文本经标准输入（stdin）传入命令，命令的标准输出（stdout）作为最终结果。所有脚本均以当前登录用户权限执行，请勿配置未知来源的不可信命令。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                // 卡片 2: 已配置脚本
                SettingsCard("已配置的终端处理脚本", icon: "terminal.fill", iconColor: .green) {
                    VStack(alignment: .leading, spacing: 8) {
                        if settings.customScripts.isEmpty {
                            HStack {
                                Spacer()
                                Text("尚未添加自定义脚本")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(settings.customScripts) { script in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(script.name)
                                                .font(.system(size: 12, weight: .semibold))
                                            Spacer()
                                            Button {
                                                settings.customScripts.removeAll { $0.id == script.id }
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Text(script.command)
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    .padding(8)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                                }
                            }
                        }
                    }
                }

                // 卡片 3: 新增脚本
                SettingsCard("添加新脚本", icon: "plus.circle.fill", iconColor: .purple) {
                    VStack(spacing: 8) {
                        TextField("脚本显示名称，如：提取邮箱 / 格式化JSON", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                        TextField("Shell 命令，如：grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+' | sort -u", text: $newCommand)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        HStack {
                            Spacer()
                            Button("添加脚本") {
                                let name = newName.trimmingCharacters(in: .whitespaces)
                                let command = newCommand.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty, !command.isEmpty else { return }
                                settings.customScripts.append(ScriptAction(name: name, command: command))
                                newName = ""
                                newCommand = ""
                                HapticHelper.feedback()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                      || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
            .padding(16)
        }
        .modernScrollbar()
    }
}

// MARK: - 关于 Tab

private struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 顶部品牌与高清应用图标
                VStack(spacing: 8) {
                    if let icon = NSApp.applicationIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
                    } else {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.accentColor)
                    }

                    Text("ClipMate")
                        .font(.system(size: 22, weight: .bold))

                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")（macOS 原生架构）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // 卡片 1: 核心设计哲学
                SettingsCard("原生设计与极致体验", icon: "cpu", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 8) {
                        featureBullet(title: "100% 纯原生架构", desc: "完全基于 Swift & SwiftUI 原生构筑，零 Electron，极致内存轻量常驻。")
                        featureBullet(title: "毛玻璃与现代视觉", desc: "统一 Liquid Glass 设计语言，自适应 macOS 浅色与深色外观。")
                        featureBullet(title: "本地 SQLite 事务引擎", desc: "采用 SQLite FTS5 倒排索引，海量历史瞬间模糊匹配与高亮。")
                        featureBullet(title: "AI 智能原生融合", desc: "内置本地句向量语义检索与多模型工作台，对话与润色行云流水。")
                    }
                }

                // 卡片 2: 本地安全与隐私保证
                SettingsCard("隐私与数据安全", icon: "lock.fill", iconColor: .green) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text("100% 本地存储：所有剪贴板历史与图片全部保存在本机 SQLite 数据库，绝无任何网络上报。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text("系统安全自适应：密码框（Concealed Type）与锁屏状态下全自动静默停止采集。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text("辅助功能权限：仅用于通过模拟按键完成选中文本的原生自动粘贴回写。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text("Copyright © 2026 ClipMate. Designed for macOS.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 8)
            }
            .padding(16)
        }
        .modernScrollbar()
    }

    private func featureBullet(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

