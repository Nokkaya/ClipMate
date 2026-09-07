import AppKit
import SwiftUI

/// 现代毛玻璃适配自定义滚动条（NSScroller 子类）。
/// 1. 槽位完全透明（绝不绘制任何浅色/灰色底槽色块，不破坏毛玻璃背景）；
/// 2. 滑块采用精致的细圆角胶囊药丸设计（默认 4px，悬停 6px，右边距 2.5px 防切边）；
/// 3. 自适应系统深色/浅色外观与半透明度，点击拖拽高亮过渡；
/// 4. 完美兼容 overlay 悬浮滚动与外接鼠标模式。
public final class ModernScroller: NSScroller {
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    public override class var isCompatibleWithOverlayScrollers: Bool {
        true
    }

    public override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        12.0
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        needsDisplay = true
    }

    /// 完全禁用默认槽位底色绘制，保持背景 100% 透明穿透
    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // 保持透明，绝不绘制任何系统灰色底槽
    }

    /// 绘制现代细长胶囊药丸滑块
    public override func drawKnob() {
        guard knobProportion > 0 else { return }
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0, knobRect.height > 0 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let pillWidth: CGFloat = isHovered ? 6.0 : 4.0
        let x = bounds.maxX - pillWidth - 2.5
        let y = knobRect.minY + 2.0
        let height = max(knobRect.height - 4.0, 18.0)
        let pillRect = NSRect(x: max(x, 0), y: y, width: pillWidth, height: height)

        let alpha: CGFloat
        if isHighlighted {
            alpha = isDark ? 0.65 : 0.55
        } else if isHovered {
            alpha = isDark ? 0.45 : 0.38
        } else {
            alpha = isDark ? 0.28 : 0.22
        }

        let baseColor = isDark ? NSColor.white : NSColor.black
        let color = baseColor.withAlphaComponent(alpha)

        let path = NSBezierPath(roundedRect: pillRect, xRadius: pillWidth / 2.0, yRadius: pillWidth / 2.0)
        color.setFill()
        path.fill()
    }
}

/// 将 NSScrollView 的滚动条无缝替换为 ModernScroller，并清空背景底色。
public struct ModernScrollViewConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            configure(view?.enclosingScrollView)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            configure(nsView?.enclosingScrollView)
        }
    }

    private func configure(_ scrollView: NSScrollView?) {
        guard let scrollView else { return }
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        if !(scrollView.verticalScroller is ModernScroller) {
            let scroller = ModernScroller()
            scrollView.verticalScroller = scroller
        }
        scrollView.verticalScroller?.scrollerStyle = .overlay
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil
    }
}

public struct ModernScrollbarModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .background(ModernScrollViewConfigurator())
    }
}

public extension View {
    /// 应用现代细长悬浮滚动条，去除不透明底槽色块并适配毛玻璃外观
    func modernScrollbar() -> some View {
        modifier(ModernScrollbarModifier())
    }
}
