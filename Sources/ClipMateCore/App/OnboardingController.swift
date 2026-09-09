import AppKit
import SwiftUI

/// 首次启动引导：定位说明 + 快捷键 + 隐私承诺 + 辅助功能权限引导。
final class OnboardingController {
    private var window: NSWindow?
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasOnboarded") else { return }
        show()
    }

    private func show() {
        if window == nil {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            newWindow.title = L10n.tr("onboarding.window_title")
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            newWindow.contentView = NSHostingView(
                rootView: OnboardingView(
                    hotkeyDisplay: settings.currentPreset.display,
                    onFinish: { [weak self] in
                        UserDefaults.standard.set(true, forKey: "hasOnboarded")
                        // 顺势引导辅助功能授权（粘贴回写需要）
                        _ = PasteBack.promptAccessibility()
                        self?.window?.close()
                    }
                )
            )
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingView: View {
    let hotkeyDisplay: String
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
            VStack(spacing: 4) {
                Text(L10n.tr("onboarding.title"))
                    .font(.system(size: 20, weight: .bold))
                Text(L10n.tr("onboarding.subtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                featureCard(icon: "keyboard", tint: Palette.text,
                            title: L10n.tr("onboarding.card1_title", hotkeyDisplay),
                            desc: L10n.tr("onboarding.card1_desc"))
                featureCard(icon: "lock.shield", tint: Palette.url,
                            title: L10n.tr("onboarding.card2_title"),
                            desc: L10n.tr("onboarding.card2_desc"))
                featureCard(icon: "sparkles", tint: Palette.richText,
                            title: L10n.tr("onboarding.card3_title"),
                            desc: L10n.tr("onboarding.card3_desc"))
            }
            Text(L10n.tr("onboarding.accessibility_notice"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button(L10n.tr("onboarding.start")) { onFinish() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 500, height: 380)
    }

    private func featureCard(icon: String, tint: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(desc)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}
