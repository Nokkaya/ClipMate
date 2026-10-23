import AppKit
import SwiftUI

/// 原生轻量浮动 Toast HUD 视图
public struct ToastHUDView: View {
    public let icon: String
    public let title: String
    public let subtitle: String?

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VisualEffectBackground())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.20), radius: 14, y: 5)
    }
}

/// 全局悬浮 Toast HUD 控制器（用于显示粘贴回退、权限缺失提示等）
public final class ToastHUD {
    public static let shared = ToastHUD()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    /// 在屏幕上方居中显示 Toast HUD，duration 秒后自动淡出
    public func show(
        icon: String = "doc.on.clipboard",
        title: String,
        subtitle: String? = nil,
        duration: TimeInterval = 2.5
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dismissWorkItem?.cancel()

            let currentPanel: NSPanel
            if let existing = self.panel {
                currentPanel = existing
            } else {
                let p = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 340, height: 60),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                p.level = .floating
                p.isOpaque = false
                p.backgroundColor = .clear
                p.hasShadow = false
                p.isReleasedWhenClosed = false
                p.hidesOnDeactivate = false
                p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                self.panel = p
                currentPanel = p
            }

            let hostingView = NSHostingView(rootView: ToastHUDView(icon: icon, title: title, subtitle: subtitle))
            currentPanel.contentView = hostingView

            let fitting = hostingView.fittingSize
            let width = max(300, min(440, fitting.width + 20))
            let height = max(54, fitting.height + 10)

            // 定位在鼠标所在屏幕（或主屏幕）的中上方
            let mouseLoc = NSEvent.mouseLocation
            let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
                ?? NSScreen.main
                ?? NSScreen.screens.first

            if let screen = activeScreen {
                let visible = screen.visibleFrame
                let x = visible.midX - width / 2
                let y = visible.maxY - height - 48
                currentPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
            }

            currentPanel.alphaValue = 0.0
            currentPanel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                currentPanel.animator().alphaValue = 1.0
            }

            let workItem = DispatchWorkItem { [weak currentPanel] in
                guard let currentPanel else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.35
                    currentPanel.animator().alphaValue = 0.0
                }, completionHandler: {
                    currentPanel.orderOut(nil)
                })
            }
            self.dismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
        }
    }
}
