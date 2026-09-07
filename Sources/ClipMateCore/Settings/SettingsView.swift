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
        .frame(width: 620, height: 500)
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

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore

    var body: some View {
        Form {
            Section("常规设置") {
                Picker("全局热键", selection: $settings.hotkeyPresetID) {
                    ForEach(AppSettings.hotkeyPresets) { preset in
                        Text(preset.display).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
                Toggle("捕获新内容时播放提示音", isOn: $settings.soundOnCapture)
                Toggle("触控板触觉反馈（关键操作微震动）", isOn: $settings.hapticFeedbackEnabled)
            }

            Section("数据备份与恢复") {
                HStack(spacing: 12) {
                    Button {
                        BackupHelper.exportBackup(store: store)
                    } label: {
                        Label("导出备份 (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        BackupHelper.importBackup(store: store)
                    } label: {
                        Label("从备份恢复 (JSON)", systemImage: "square.and.arrow.down")
                    }
                }
                Text("当前本地已记录历史 \(store.itemCount()) 条，收录片段 \(store.allSnippets().count) 条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("面板快捷键：⏎ 粘贴 · ⌘⏎ 复制 · ⌥⏎ 编辑 · ⌘K AI · ⌘1-9 快贴 · Tab 切换分类")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 片段管理

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

    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索片段…", text: $searchKeyword)
                    .textFieldStyle(.plain)
                if !searchKeyword.isEmpty {
                    Button {
                        searchKeyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    openNew()
                } label: {
                    Label("新建片段", systemImage: "plus")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider()

            // 分组胶囊
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        selectedGroup = nil
                    } label: {
                        Text("全部 (\(snippets.count))")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(selectedGroup == nil ? Color.purple.opacity(0.2) : Color.primary.opacity(0.06)))
                            .foregroundStyle(selectedGroup == nil ? Color.purple : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    ForEach(groups, id: \.self) { g in
                        let count = snippets.filter { $0.snippetGroup == g }.count
                        Button {
                            selectedGroup = g
                        } label: {
                            Text("\(g) (\(count))")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(selectedGroup == g ? Color.purple.opacity(0.2) : Color.primary.opacity(0.06)))
                                .foregroundStyle(selectedGroup == g ? Color.purple : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .modernScrollbar()

            Divider()

            // 片段列表
            if filteredSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bookmark")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(snippets.isEmpty ? "暂无片段，点击右上角新建" : "未找到匹配片段")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredSnippets) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                if let title = item.title, !title.isEmpty {
                                    Text(title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                } else {
                                    Text(item.displayText)
                                        .font(.system(size: 12.5, weight: .medium))
                                        .lineLimit(1)
                                }
                                if let g = item.snippetGroup, !g.isEmpty {
                                    Text("🏷 \(g)")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                                        .foregroundStyle(Color.purple)
                                }
                                if let sc = item.snippetShortcode, !sc.isEmpty {
                                    Text("⚡️ \(sc)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                                        .foregroundStyle(Color.orange)
                                }
                                Spacer()
                                Button {
                                    openEdit(item: item)
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    deleteSnippet(item: item)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            Text(item.plainText)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.inset)
                .modernScrollbar()
            }
        }
        .onAppear { loadData() }
        .sheet(isPresented: $showEditor) {
            editorSheet
        }
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
        VStack(alignment: .leading, spacing: 10) {
            Text(editingID == nil ? "新建片段" : "编辑片段")
                .font(.headline)
            TextField("标题（如：日常开票信息、Git 常用流）", text: $draftTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField("分组（如：开发 / 常用 / 邮件）", text: $draftGroup)
                    .textFieldStyle(.roundedBorder)
                TextField("快捷短码（如：;tax）", text: $draftShortcode)
                    .textFieldStyle(.roundedBorder)
            }
            Text("片段内容")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $draftContent)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .frame(height: 140)
            HStack {
                Button("取消") { showEditor = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
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
                .keyboardShortcut(.defaultAction)
                .disabled(draftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 440, height: 320)
    }
}

// MARK: - 采集

private struct CaptureTab: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore

    var body: some View {
        Form {
            Stepper("最多保留 \(settings.retentionMaxItems) 条", value: $settings.retentionMaxItems, in: 50...10000, step: 50)
            Stepper("保留最近 \(settings.retentionMaxAgeDays) 天", value: $settings.retentionMaxAgeDays, in: 1...365)
            Stepper("单条内容上限 \(settings.maxCaptureMB) MB", value: $settings.maxCaptureMB, in: 1...100)
            Toggle("图片文字识别（OCR 入库，截图内容可搜索）", isOn: $settings.imageOCREnabled)
            Toggle("自动抓取链接标题与图标（后台轻量解析）", isOn: $settings.fetchLinkMetadata)
            HStack(spacing: 6) {
                Image(systemName: store.supportsFullTextSearch ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(store.supportsFullTextSearch ? Color.green : Color.orange)
                Text(store.supportsFullTextSearch
                     ? "全文检索已启用（SQLite FTS5）"
                     : "系统 SQLite 不支持 FTS5，已降级为 LIKE 检索")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - 隐私

private struct PrivacyTab: View {
    @ObservedObject var settings: AppSettings
    let frontApps: FrontAppTracker
    @State private var newBundleID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("以下应用在前台时，复制的内容不会被记录：")
                .font(.callout)
                .foregroundStyle(.secondary)
            List {
                ForEach(settings.excludedApps, id: \.self) { bundle in
                    HStack {
                        Text(bundle)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button {
                            settings.excludedApps.removeAll { $0 == bundle }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .frame(minHeight: 150)
            HStack {
                TextField("com.example.app", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button("添加") {
                    let id = newBundleID.trimmingCharacters(in: .whitespaces)
                    if !id.isEmpty, !settings.excludedApps.contains(id) {
                        settings.excludedApps.append(id)
                    }
                    newBundleID = ""
                }
                .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("添加前台应用") {
                    if let app = frontApps.lastNonSelfApp,
                       let bundle = app.bundleIdentifier,
                       !settings.excludedApps.contains(bundle) {
                        settings.excludedApps.append(bundle)
                    }
                }
            }
            Toggle("暂停采集（密码管理器等场景临时关闭）", isOn: $settings.pauseCapture)
            Text("另外：检测到系统安全输入（密码框）或屏幕锁定时，采集会自动暂停。")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding()
    }
}

// MARK: - AI

private struct AITab: View {
    @ObservedObject var settings: AppSettings
    let ai: AIService
    @State private var apiKeyDraft = ""
    @State private var testResult = ""
    @State private var testing = false

    @State private var newPromptName = ""
    @State private var newPromptTemplate = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("启用 AI 快速操作（面板内 ⌘K）", isOn: $settings.aiEnabled)
            Toggle("语义搜索（本地系统模型按含义匹配历史，无网络请求）",
                   isOn: $settings.semanticSearchEnabled)
                .disabled(!EmbeddingService.isAvailable)
            if !EmbeddingService.isAvailable {
                Text("当前系统未提供可用的句向量资源，语义搜索暂不可用（不影响关键词检索）")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text("端点（任意 OpenAI 兼容 Chat Completions 服务）")
                .font(.callout)
            TextField("https://api.openai.com/v1 或 http://localhost:11434/v1（Ollama）", text: $settings.aiEndpoint)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text("模型")
                .font(.callout)
            TextField("gpt-4o-mini / qwen2.5:7b / glm-4-flash …", text: $settings.aiModel)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
            Text("API Key（仅存本机钥匙串；本地服务可留空）")
                .font(.callout)
            HStack {
                SecureField("sk-…", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button("保存密钥") {
                    settings.aiAPIKey = apiKeyDraft
                    testResult = "密钥已保存到钥匙串"
                }
                .disabled(apiKeyDraft.isEmpty)
            }
            HStack(spacing: 8) {
                Button("测试连接") {
                    testing = true
                    Task { @MainActor in
                        testResult = await ai.testConnection()
                        testing = false
                    }
                }
                if testing { ProgressView().controlSize(.small) }
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // 自定义提示词模板
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("提示词模板（包含 {content} 占位变量）")
                        .font(.callout)
                    Spacer()
                    Button("恢复精选默认模板") {
                        settings.customPrompts = PromptTemplate.defaults
                    }
                    .font(.caption)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(settings.customPrompts) { prompt in
                            HStack {
                                Label(prompt.name, systemImage: prompt.icon)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Text(String(prompt.template.prefix(36)) + "…")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                                Button {
                                    settings.customPrompts.removeAll { $0.id == prompt.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 70)
                .modernScrollbar()

                HStack {
                    TextField("模板名（如：代码转TS）", text: $newPromptName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 140)
                    TextField("提示词内容（包含 {content} 占位）", text: $newPromptTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                    Button("添加") {
                        let n = newPromptName.trimmingCharacters(in: .whitespaces)
                        let t = newPromptTemplate.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, !t.isEmpty else { return }
                        settings.customPrompts.append(PromptTemplate(name: n, icon: "sparkle", template: t))
                        newPromptName = ""
                        newPromptTemplate = ""
                    }
                    .disabled(newPromptName.trimmingCharacters(in: .whitespaces).isEmpty || newPromptTemplate.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Spacer()
            Text("启用后，剪贴板内容会发送到上面配置的端点。隐私敏感场景建议使用本地模型（如 Ollama）。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .onAppear { apiKeyDraft = settings.aiAPIKey }
    }
}

// MARK: - 脚本

private struct ScriptsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var newName = ""
    @State private var newCommand = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("脚本动作显示在 ⌘K 浮层：剪贴板文本经 stdin 传入命令，stdout 作为结果。命令以你的用户权限运行，请勿填入不可信脚本。")
                .font(.caption)
                .foregroundStyle(.secondary)
            List {
                ForEach(settings.customScripts) { script in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(script.name)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button {
                                settings.customScripts.removeAll { $0.id == script.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(script.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .listStyle(.inset)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .frame(minHeight: 150)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("名称，如：提取邮箱", text: $newName)
                        .textFieldStyle(.roundedBorder)
                    TextField("命令，如：grep -oE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+'", text: $newCommand)
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
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                                  || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - 关于

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
            Text("ClipMate")
                .font(.title2).bold()
            Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")（开发版）")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("· 数据全部存储在本机，无任何上报")
                Text("· 密码管理器/安全输入/锁屏时不采集")
                Text("· 粘贴回写需授予辅助功能权限（首次粘贴时系统引导）")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
