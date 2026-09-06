import SwiftUI
import AppKit

/// 设置窗口：通用 / 采集 / 隐私 / AI / 关于。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore
    let ai: AIService
    let frontApps: FrontAppTracker

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("通用", systemImage: "gearshape") }
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
        .frame(width: 560, height: 460)
    }
}

// MARK: - 通用

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("全局热键", selection: $settings.hotkeyPresetID) {
                ForEach(AppSettings.hotkeyPresets) { preset in
                    Text(preset.display).tag(preset.id)
                }
            }
            .pickerStyle(.menu)
            Toggle("开机自动启动", isOn: $settings.launchAtLogin)
            Toggle("捕获新内容时播放提示音", isOn: $settings.soundOnCapture)
            Text("面板内快捷键：⏎ 粘贴 · ⌘⏎ 复制 · ⌥⏎ 编辑 · ⌘K AI · ⌘1-9 快贴 · Tab 切分类")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
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
