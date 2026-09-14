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
                .tabItem { Label(L10n.tr("tab.general"), systemImage: "gearshape") }
            SnippetsTab(store: store)
                .tabItem { Label(L10n.tr("tab.snippets"), systemImage: "bookmark") }
            CaptureTab(settings: settings, store: store)
                .tabItem { Label(L10n.tr("tab.capture"), systemImage: "doc.on.doc") }
            PrivacyTab(settings: settings, frontApps: frontApps)
                .tabItem { Label(L10n.tr("tab.privacy"), systemImage: "hand.raised") }
            AITab(settings: settings, ai: ai)
                .tabItem { Label(L10n.tr("tab.ai"), systemImage: "sparkles") }
            ScriptsTab(settings: settings)
                .tabItem { Label(L10n.tr("tab.scripts"), systemImage: "terminal") }
            AboutTab(settings: settings)
                .tabItem { Label(L10n.tr("tab.about"), systemImage: "info.circle") }
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
        savePanel.title = L10n.tr("settings.backup.export_title")
        savePanel.nameFieldStringValue = "ClipMate-Backup-\(Int(Date().timeIntervalSince1970)).json"
        savePanel.allowedContentTypes = [.json]
        savePanel.canCreateDirectories = true
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        do {
            let data = try store.exportJSON()
            try data.write(to: url)
            HapticHelper.generic()
            let alert = NSAlert()
            alert.messageText = L10n.tr("settings.backup.export_success")
            alert.informativeText = L10n.tr("settings.backup.export_success_msg", store.itemCount(), url.lastPathComponent)
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.tr("settings.backup.export_failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    static func importBackup(store: ClipStore) {
        let openPanel = NSOpenPanel()
        openPanel.title = L10n.tr("settings.backup.import_title")
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        guard openPanel.runModal() == .OK, let url = openPanel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let count = try store.importJSON(data)
            HapticHelper.generic()
            let alert = NSAlert()
            alert.messageText = L10n.tr("settings.backup.import_success")
            alert.informativeText = L10n.tr("settings.backup.import_success_msg", count)
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.messageText = L10n.tr("settings.backup.import_failed")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

// MARK: - 主题外观选择卡片

private struct ThemeGallerySection: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        SettingsCard(
            L10n.tr("settings.theme.card_title"),
            icon: "paintpalette.fill",
            iconColor: settings.appTheme.accent,
            trailing: {
                Text(L10n.themeTitle(settings.appTheme, lang: settings.appLanguage))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(settings.appTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(settings.appTheme.accent.opacity(0.12)))
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("settings.theme.desc"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    spacing: 8
                ) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeChip(
                            theme: theme,
                            isSelected: settings.appTheme == theme,
                            currentLang: settings.appLanguage
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                settings.appTheme = theme
                            }
                            HapticHelper.generic()
                        }
                    }
                }
            }
        }
    }
}

/// 紧凑主题芯片：左侧微缩色板 + 名称，悬停显示该主题简介。
private struct ThemeChip: View {
    let theme: AppTheme
    let isSelected: Bool
    let currentLang: AppLanguage
    let onSelect: () -> Void

    @State private var isHovered = false

    /// 微缩色板：底色 + 强调色 + 两个预览色。
    private var swatches: [Color] {
        [theme.previewBackgroundColor, theme.accent] + Array(theme.previewSwatches.prefix(2))
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    }
                }

                Text(L10n.themeTitle(theme, lang: currentLang))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? theme.accent : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected
                          ? theme.accent.opacity(0.12)
                          : (isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isSelected ? theme.accent : Color.primary.opacity(0.08),
                                  lineWidth: isSelected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(L10n.themeDesc(theme, lang: currentLang))
    }
}

// MARK: - 通用 Tab

private struct GeneralTab: View {
    @ObservedObject var settings: AppSettings
    let store: ClipStore

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 0: 界面外观与主题风格
                ThemeGallerySection(settings: settings)

                // 卡片 1: 交互与启动
                SettingsCard(L10n.tr("settings.general.card_interaction"), icon: "gearshape.fill", iconColor: .accentColor) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("settings.hotkey"), subtitle: L10n.tr("settings.hotkey_sub")) {
                            Picker("", selection: $settings.hotkeyPresetID) {
                                ForEach(AppSettings.hotkeyPresets) { preset in
                                    Text(preset.display).tag(preset.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("settings.position"), subtitle: L10n.tr("settings.position_sub")) {
                            Picker("", selection: $settings.panelPositionMode) {
                                ForEach(PanelPositionMode.allCases) { mode in
                                    Text(L10n.positionModeTitle(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("settings.language"), subtitle: L10n.tr("settings.language_sub")) {
                            Picker("", selection: $settings.appLanguage) {
                                ForEach(AppLanguage.allCases) { lang in
                                    Text(L10n.languageTitle(lang)).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 170)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("settings.launch_at_login"), subtitle: L10n.tr("settings.launch_at_login_sub")) {
                            Toggle("", isOn: $settings.launchAtLogin)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("settings.sound"), subtitle: L10n.tr("settings.sound_sub")) {
                            Toggle("", isOn: $settings.soundOnCapture)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("settings.haptic"), subtitle: L10n.tr("settings.haptic_sub")) {
                            Toggle("", isOn: $settings.hapticFeedbackEnabled)
                                .toggleStyle(.switch)
                        }
                    }
                }


                // 卡片 2: 备份与恢复
                SettingsCard(
                    L10n.tr("settings.backup.card_title"),
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .blue,
                    trailing: {
                        Text(L10n.tr("settings.backup.stats", store.itemCount(), store.allSnippets().count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("settings.backup.desc"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                BackupHelper.exportBackup(store: store)
                            } label: {
                                Label(L10n.tr("settings.backup.export"), systemImage: "square.and.arrow.up")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)

                            Button {
                                BackupHelper.importBackup(store: store)
                            } label: {
                                Label(L10n.tr("settings.backup.import"), systemImage: "square.and.arrow.down")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                // 卡片 3: 快捷键指南
                SettingsCard(L10n.tr("settings.shortcuts.card_title"), icon: "keyboard.fill", iconColor: .blue) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        shortcutBadge(key: "⏎", action: L10n.tr("settings.shortcuts.paste"))
                        shortcutBadge(key: "⌘⏎", action: L10n.tr("settings.shortcuts.copy"))
                        shortcutBadge(key: "⌥⏎", action: L10n.tr("settings.shortcuts.edit"))
                        shortcutBadge(key: "⌘K", action: L10n.tr("settings.shortcuts.ai"))
                        shortcutBadge(key: "⌘I", action: L10n.tr("settings.shortcuts.preview"))
                        shortcutBadge(key: "⌘1 ~ 9", action: L10n.tr("settings.shortcuts.quick_paste"))
                        shortcutBadge(key: "⇧↑ / ⇧↓", action: L10n.tr("settings.shortcuts.multiselect"))
                        shortcutBadge(key: "Tab", action: L10n.tr("settings.shortcuts.switch_tab"))
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
                    TextField(L10n.tr("snippets.search_placeholder"), text: $searchKeyword)
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
                    Label(L10n.tr("snippets.new"), systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .clipMateAccent(size: .small, tint: Palette.snippet)
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
                        Text("\(L10n.tr("snippets.all_groups")) (\(snippets.count))")
                            .font(.system(size: 11, weight: selectedGroup == nil ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule().fill(
                                    selectedGroup == nil ? Palette.snippet.opacity(0.18) : Color.primary.opacity(0.05)
                                )
                            )
                            .foregroundStyle(selectedGroup == nil ? Palette.snippet : Color.secondary)
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
                                        isSelected ? Palette.snippet.opacity(0.18) : Color.primary.opacity(0.05)
                                    )
                                )
                                .foregroundStyle(isSelected ? Palette.snippet : Color.secondary)
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
                    Text(snippets.isEmpty ? L10n.tr("snippets.empty") : L10n.tr("snippets.no_match"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(snippets.isEmpty ? L10n.tr("snippets.empty_sub") : L10n.tr("empty.no_match_sub"))
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
                    .foregroundStyle(Palette.snippet)

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
                        .background(Capsule().fill(Palette.snippet.opacity(0.14)))
                        .foregroundStyle(Palette.snippet)
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

                Text(L10n.tr("meta.chars", item.plainText.count))
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
                                Text(L10n.tr("action.copied")).font(.system(size: 10))
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(copiedID == item.id ? Color.green : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("snippets.copy_tip"))

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
                    .help(L10n.tr("snippets.edit_tip"))

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
                    .help(L10n.tr("snippets.delete_tip"))
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
                    .foregroundStyle(Palette.snippet)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.snippet.opacity(0.15)))

                VStack(alignment: .leading, spacing: 1) {
                    Text(editingID == nil ? L10n.tr("snippets.editor_title_new") : L10n.tr("snippets.editor_title_edit"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(L10n.tr("snippets.editor_subtitle"))
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
                    Label(L10n.tr("snippets.title_optional"), systemImage: "textformat")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField(L10n.tr("snippets.title_placeholder"), text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(L10n.tr("snippets.group"), systemImage: "folder.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField(L10n.tr("snippets.group_placeholder"), text: $draftGroup)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label(L10n.tr("snippets.shortcode_optional"), systemImage: "bolt.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        TextField(L10n.tr("snippets.shortcode_placeholder"), text: $draftShortcode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                }

                // 已有分组快速标签
                if !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Text(L10n.tr("snippets.existing_groups"))
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
                        Label(L10n.tr("snippets.content"), systemImage: "doc.text.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.tr("meta.chars", draftContent.count))
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
                Button(L10n.tr("action.cancel")) {
                    showEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L10n.tr("snippets.save")) {
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
                .clipMateAccent(size: .regular, tint: Palette.snippet)
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
    @State private var showClearedAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // 卡片 1: 留存与清理策略
                SettingsCard(L10n.tr("capture.card_retention"), icon: "clock.arrow.circlepath", iconColor: .blue) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("capture.max_items"), subtitle: L10n.tr("capture.max_items_sub")) {
                            HStack(spacing: 6) {
                                Text(L10n.tr("capture.items_unit", settings.retentionMaxItems))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing)
                                Stepper("", value: $settings.retentionMaxItems, in: 50...10000, step: 50)
                                    .labelsHidden()
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("capture.max_days"), subtitle: L10n.tr("capture.max_days_sub")) {
                            HStack(spacing: 6) {
                                Text(L10n.tr("capture.days_unit", settings.retentionMaxAgeDays))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .frame(width: 65, alignment: .trailing)
                                Stepper("", value: $settings.retentionMaxAgeDays, in: 1...365)
                                    .labelsHidden()
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("capture.max_size"), subtitle: L10n.tr("capture.max_size_sub")) {
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
                SettingsCard(L10n.tr("capture.card_smart"), icon: "sparkle.magnifyingglass", iconColor: .teal) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("capture.smart_title"), subtitle: L10n.tr("capture.smart_title_sub")) {
                            Toggle("", isOn: $settings.smartTitleEnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("capture.ocr"), subtitle: L10n.tr("capture.ocr_sub")) {
                            Toggle("", isOn: $settings.imageOCREnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("capture.link_metadata"), subtitle: L10n.tr("capture.link_metadata_sub")) {
                            Toggle("", isOn: $settings.fetchLinkMetadata)
                                .toggleStyle(.switch)
                        }
                    }
                }

                // 卡片 3: 智能情境推荐
                SettingsCard(L10n.tr("settings.recommendations_title"), icon: "sparkles", iconColor: .purple) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("settings.recommendations_title"), subtitle: L10n.tr("settings.recommendations_desc")) {
                            Toggle("", isOn: $settings.enableSmartRecommendations)
                                .toggleStyle(.switch)
                        }

                        if settings.enableSmartRecommendations {
                            Divider().overlay(Color.primary.opacity(0.04))

                            SettingsRow(L10n.tr("settings.clear_rec_learning"), subtitle: nil) {
                                Button(L10n.tr("action.reset")) {
                                    settings.clearRecommendationLearningData()
                                    showClearedAlert = true
                                }
                                .buttonStyle(.bordered)
                                .alert(L10n.tr("settings.clear_rec_learning_done"), isPresented: $showClearedAlert) {
                                    Button("OK", role: .cancel) { }
                                }
                            }
                        }
                    }
                }

                // 内容控件与变焦
                SettingsCard("内容控件与变焦", icon: "slider.horizontal.3", iconColor: .blue) {
                    VStack(spacing: 10) {
                        SettingsRow("启用内容控件", subtitle: "自动识别剪贴板内容中的可调变量、比例缩放、时间与计算联动") {
                            Toggle("", isOn: $settings.enableInteractiveClips)
                                .toggleStyle(.switch)
                        }

                        if settings.enableInteractiveClips {
                            Divider().overlay(Color.primary.opacity(0.04))

                            SettingsRow("仅在本地分析", subtitle: "使用纯本地轻量规则引擎毫秒级识别，无任何网络请求，剪贴板数据完全驻留本机") {
                                Toggle("", isOn: $settings.interactiveClipsLocalOnly)
                                    .toggleStyle(.switch)
                            }

                            Divider().overlay(Color.primary.opacity(0.04))

                            SettingsRow("启用粘贴变焦", subtitle: "允许在预览中即时切换完整、要点、清单或一句话等信息层级") {
                                Toggle("", isOn: $settings.enablePasteZoom)
                                    .toggleStyle(.switch)
                            }
                        }
                    }
                }

                // 卡片 4: 检索引擎
                SettingsCard(L10n.tr("capture.card_db"), icon: "cylinder.split.1x2", iconColor: .green) {
                    HStack(spacing: 10) {
                        Image(systemName: store.supportsFullTextSearch ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(store.supportsFullTextSearch ? Color.green : Color.orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.supportsFullTextSearch ? L10n.tr("capture.fts_ready") : L10n.tr("capture.fts_fallback"))
                                .font(.system(size: 12.5, weight: .medium))
                            Text(store.supportsFullTextSearch
                                 ? L10n.tr("capture.fts_ready_sub")
                                 : L10n.tr("capture.fts_fallback_sub"))
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
                SettingsCard(L10n.tr("privacy.card_blacklist"), icon: "hand.raised.fill", iconColor: .orange) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.tr("privacy.blacklist_desc"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        if settings.excludedApps.isEmpty {
                            HStack {
                                Spacer()
                                Text(L10n.tr("privacy.empty_blacklist"))
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
                            TextField(L10n.tr("privacy.input_placeholder"), text: $newBundleID)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))

                            Button(L10n.tr("action.add")) {
                                let id = newBundleID.trimmingCharacters(in: .whitespaces)
                                if !id.isEmpty, !settings.excludedApps.contains(id) {
                                    settings.excludedApps.append(id)
                                }
                                newBundleID = ""
                            }
                            .disabled(newBundleID.trimmingCharacters(in: .whitespaces).isEmpty)

                            Button(L10n.tr("privacy.add_frontmost")) {
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
                SettingsCard(L10n.tr("privacy.card_security"), icon: "lock.shield.fill", iconColor: .green) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("privacy.pause"), subtitle: L10n.tr("privacy.pause_sub")) {
                            Toggle("", isOn: $settings.pauseCapture)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        HStack(spacing: 8) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text(L10n.tr("privacy.security_note"))
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
                SettingsCard(L10n.tr("ai.card_core"), icon: "sparkles", iconColor: .indigo) {
                    VStack(spacing: 10) {
                        SettingsRow(L10n.tr("ai.enable"), subtitle: L10n.tr("ai.enable_sub")) {
                            Toggle("", isOn: $settings.aiEnabled)
                                .toggleStyle(.switch)
                        }

                        Divider().overlay(Color.primary.opacity(0.04))

                        SettingsRow(L10n.tr("ai.semantic"), subtitle: L10n.tr("ai.semantic_sub")) {
                            Toggle("", isOn: $settings.semanticSearchEnabled)
                                .toggleStyle(.switch)
                                .disabled(!EmbeddingService.isAvailable)
                        }

                        if !EmbeddingService.isAvailable {
                            HStack {
                                Image(systemName: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                                Text(L10n.tr("ai.semantic_unavailable"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // 卡片 2: API 与模型配置
                SettingsCard(L10n.tr("ai.card_model"), icon: "server.rack", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("ai.endpoint"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField(L10n.tr("ai.endpoint_placeholder"), text: $settings.aiEndpoint)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("ai.model_name"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField(L10n.tr("ai.model_placeholder"), text: $settings.aiModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.tr("ai.api_key"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                SecureField("sk-…", text: $apiKeyDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                Button(L10n.tr("ai.save_key")) {
                                    settings.aiAPIKey = apiKeyDraft
                                    testResult = L10n.tr("ai.key_saved")
                                    HapticHelper.feedback()
                                }
                                .disabled(apiKeyDraft.isEmpty)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(L10n.tr("ai.test_connection")) {
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
                    L10n.tr("ai.card_prompts"),
                    icon: "text.badge.plus",
                    iconColor: .indigo,
                    trailing: {
                        Button(L10n.tr("ai.reset_prompts")) {
                            settings.customPrompts = PromptTemplate.defaults
                            HapticHelper.feedback()
                        }
                        .font(.system(size: 11))
                    }
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("ai.prompt_var_note"))
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
                            TextField(L10n.tr("ai.prompt_name_placeholder"), text: $newPromptName)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                                .frame(width: 140)
                            TextField(L10n.tr("ai.prompt_content_placeholder"), text: $newPromptTemplate)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))
                            Button(L10n.tr("action.add")) {
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

private struct PresetItemView: View {
    let preset: ScriptAction
    let isAdded: Bool
    let appLanguage: AppLanguage
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: preset.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isAdded ? Color.secondary : Color.orange)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill((isAdded ? Color.primary : Color.orange).opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.scriptName(preset, lang: appLanguage))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isAdded ? .secondary : .primary)
                    .lineLimit(1)
                Text(L10n.scriptPresetDesc(preset.id, lang: appLanguage))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()

            if isAdded {
                Text(L10n.tr("scripts.preset_added"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            } else {
                Button(action: onAdd) {
                    Text(L10n.tr("scripts.add_preset"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isAdded ? 0.015 : 0.035)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ConfiguredScriptRow: View {
    let script: ScriptAction
    let index: Int
    let totalCount: Int
    let appLanguage: AppLanguage
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: script.type == .shortcut ? "bolt.horizontal.fill" : script.icon)
                .font(.system(size: 12))
                .foregroundStyle(script.type == .shortcut ? Color.purple : Color.teal)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill((script.type == .shortcut ? Color.purple : Color.teal).opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(L10n.scriptName(script, lang: appLanguage))
                        .font(.system(size: 12, weight: .semibold))
                    Text(script.type == .shortcut ? "Shortcuts" : "Shell")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill((script.type == .shortcut ? Color.purple : Color.teal).opacity(0.12)))
                        .foregroundStyle(script.type == .shortcut ? Color.purple : Color.teal)
                }
                Text(script.command)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 2) {
                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(index > 0 ? 0.8 : 0.25))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(index == 0)

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(index < totalCount - 1 ? 0.8 : 0.25))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(index >= totalCount - 1)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
    }
}

private struct ScriptsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var newName = ""
    @State private var newCommand = ""
    @State private var newType: ScriptType = .shell

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                presetLibraryCard
                configuredScriptsCard
                addCustomActionCard
                specExplanationCard
            }
            .padding(16)
        }
        .modernScrollbar()
    }

    private var presetLibraryCard: some View {
        SettingsCard(
            L10n.tr("scripts.card_presets"),
            icon: "sparkles.rectangle.stack.fill",
            iconColor: .orange,
            trailing: {
                HStack(spacing: 8) {
                    Button {
                        for preset in ScriptAction.presetLibrary {
                            if !settings.customScripts.contains(where: { $0.id == preset.id || $0.command == preset.command }) {
                                settings.customScripts.append(preset)
                            }
                        }
                        HapticHelper.feedback()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(L10n.tr("scripts.add_all_presets"))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.orange.opacity(0.12)))
                    .foregroundStyle(Color.orange)

                    Button {
                        settings.customScripts = ScriptAction.defaultPresets
                        HapticHelper.feedback()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text(L10n.tr("scripts.reset_presets"))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .foregroundStyle(.secondary)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.tr("scripts.preset_desc"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ScriptAction.presetLibrary) { preset in
                        let isAdded = settings.customScripts.contains(where: { $0.id == preset.id || $0.command == preset.command })
                        PresetItemView(
                            preset: preset,
                            isAdded: isAdded,
                            appLanguage: settings.appLanguage
                        ) {
                            settings.customScripts.append(preset)
                            HapticHelper.feedback()
                        }
                    }
                }
            }
        }
    }

    private var configuredScriptsCard: some View {
        SettingsCard(L10n.tr("scripts.card_list"), icon: "terminal.fill", iconColor: .teal) {
            VStack(alignment: .leading, spacing: 8) {
                if settings.customScripts.isEmpty {
                    HStack {
                        Spacer()
                        Text(L10n.tr("scripts.empty"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(settings.customScripts.enumerated()), id: \.element.id) { index, script in
                            ConfiguredScriptRow(
                                script: script,
                                index: index,
                                totalCount: settings.customScripts.count,
                                appLanguage: settings.appLanguage,
                                onMoveUp: {
                                    guard index > 0 else { return }
                                    settings.customScripts.swapAt(index, index - 1)
                                    HapticHelper.feedback()
                                },
                                onMoveDown: {
                                    guard index < settings.customScripts.count - 1 else { return }
                                    settings.customScripts.swapAt(index, index + 1)
                                    HapticHelper.feedback()
                                },
                                onDelete: {
                                    settings.customScripts.removeAll { $0.id == script.id }
                                    HapticHelper.feedback()
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var addCustomActionCard: some View {
        SettingsCard(L10n.tr("scripts.card_add"), icon: "plus.circle.fill", iconColor: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(L10n.tr("scripts.type_label"), selection: $newType) {
                    Text(L10n.tr("scripts.type_shell")).tag(ScriptType.shell)
                    Text(L10n.tr("scripts.type_shortcut")).tag(ScriptType.shortcut)
                }
                .pickerStyle(.segmented)

                TextField(L10n.tr("scripts.name_placeholder"), text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                TextField(newType == .shortcut ? L10n.tr("scripts.shortcut_placeholder") : L10n.tr("scripts.command_placeholder"), text: $newCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))

                HStack {
                    Text(newType == .shortcut ? "macOS /usr/bin/shortcuts run <name>" : "/bin/sh -c <command>")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        let command = newCommand.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !command.isEmpty else { return }
                        let icon = (newType == .shortcut) ? "bolt.horizontal.fill" : "terminal"
                        settings.customScripts.append(ScriptAction(name: name, command: command, type: newType, icon: icon))
                        newName = ""
                        newCommand = ""
                        HapticHelper.feedback()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text(L10n.tr("scripts.add_button"))
                        }
                        .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                              || newCommand.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var specExplanationCard: some View {
        SettingsCard(L10n.tr("scripts.card_spec"), icon: "shield.checkered", iconColor: .secondary) {
            Text(L10n.tr("scripts.spec_desc"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 关于 Tab

private struct AboutTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var updateManager = UpdateManager.shared

    private var updateStatusText: String {
        switch updateManager.state {
        case .idle:
            return ""
        case .checking:
            return L10n.tr("update.checking")
        case .upToDate(let version):
            return L10n.tr("update.up_to_date", version)
        case .available(let version, _, _):
            return L10n.tr("update.available", version)
        case .failed:
            return L10n.tr("update.failed")
        }
    }

    private var statusColor: Color {
        switch updateManager.state {
        case .available: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

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

                    Text(L10n.tr("about.version", updateManager.currentVersion))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // 卡片 1: 版本与软件更新
                SettingsCard(L10n.tr("update.card_title"), icon: "arrow.triangle.2.circlepath.circle.fill", iconColor: .blue) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.tr("update.current_version", updateManager.currentVersion, updateManager.currentBuild))
                                    .font(.system(size: 12, weight: .medium))
                                if !updateStatusText.isEmpty {
                                    Text(updateStatusText)
                                        .font(.system(size: 11))
                                        .foregroundStyle(statusColor)
                                }
                            }
                            Spacer()

                            if updateManager.isChecking {
                                ProgressView()
                                    .controlSize(.small)
                            } else if case .available = updateManager.state {
                                Button {
                                    updateManager.openDownloadPage()
                                } label: {
                                    Label(L10n.tr("update.download"), systemImage: "arrow.down.circle.fill")
                                }
                                .clipMateAccent(size: .small)
                            } else {
                                Button {
                                    updateManager.checkForUpdates(settings: settings, manual: true)
                                } label: {
                                    Text(L10n.tr("update.check_now"))
                                }
                                .clipMateGlass(size: .small)
                            }
                        }

                        Divider().overlay(Color.primary.opacity(0.06))

                        Toggle(isOn: $settings.autoCheckUpdates) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.tr("update.auto_check"))
                                    .font(.system(size: 12))
                                Text(L10n.tr("update.auto_check_sub"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                // 卡片 2: 核心设计哲学
                SettingsCard(L10n.tr("about.card_arch"), icon: "cpu", iconColor: .indigo) {
                    VStack(alignment: .leading, spacing: 8) {
                        featureBullet(title: L10n.tr("about.arch_bullet1_title"), desc: L10n.tr("about.arch_bullet1_desc"))
                        featureBullet(title: L10n.tr("about.arch_bullet2_title"), desc: L10n.tr("about.arch_bullet2_desc"))
                        featureBullet(title: L10n.tr("about.arch_bullet3_title"), desc: L10n.tr("about.arch_bullet3_desc"))
                        featureBullet(title: L10n.tr("about.arch_bullet4_title"), desc: L10n.tr("about.arch_bullet4_desc"))
                    }
                }

                // 卡片 3: 本地安全与隐私保证
                SettingsCard(L10n.tr("about.card_privacy"), icon: "lock.fill", iconColor: .green) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text(L10n.tr("about.privacy_bullet1"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text(L10n.tr("about.privacy_bullet2"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text(L10n.tr("about.privacy_bullet3"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(L10n.tr("about.copyright"))
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

