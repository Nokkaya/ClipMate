import AppKit
import SwiftUI

/// 现代毛玻璃适配自定义滚动条（NSScroller 子类）。
/// 1. 100% 透明无底槽（绝不调用 super.draw 绘制系统白色/浅灰色底槽与边框）；
/// 2. 细长圆角胶囊药丸滑块（常规 4px，悬停 6px，右边距 3px 防切边）；
/// 3. 自适应深浅外观（微透明白 / 微透明黑），点击拖拽丝滑高亮；
/// 4. 强制 overlay 悬浮渲染，与毛玻璃背景浑然一体。
public final class ModernScroller: NSScroller {
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    public override class var isCompatibleWithOverlayScrollers: Bool {
        true
    }

    public override var isOpaque: Bool {
        false
    }

    public override var wantsUpdateLayer: Bool {
        false
    }

    public override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        12.0
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        scrollerStyle = .overlay
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

    /// 核心：重写主绘制入口，绝不调用 super.draw(dirtyRect)！
    /// 默认 super.draw 会调用系统 CoreUI 强行渲染不透明浅白/灰色的底槽和边框。
    public override func draw(_ dirtyRect: NSRect) {
        // 槽位 100% 透明穿透，仅绘制浮动胶囊药丸滑块
        drawKnob()
    }

    /// 完全禁用默认槽位底色绘制
    public override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // 空实现：绝不绘制任何底槽色块
    }

    /// 绘制现代细长胶囊药丸滑块
    public override func drawKnob() {
        guard knobProportion > 0 && knobProportion < 1.0 else { return }
        let knobRect = rect(for: .knob)
        guard knobRect.width > 0, knobRect.height > 0 else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        let pillWidth: CGFloat = isHovered ? 6.0 : 4.0
        let x = bounds.maxX - pillWidth - 3.0
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
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            if let sv = Self.findScrollView(from: view) {
                Self.configure(sv)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            if let sv = Self.findScrollView(from: nsView) {
                Self.configure(sv)
            }
        }
    }

    /// 递归配置指定视图树下的所有 NSScrollView
    public static func configureAllScrollViews(in root: NSView) {
        if let sv = root as? NSScrollView {
            configure(sv)
        }
        for subview in root.subviews {
            configureAllScrollViews(in: subview)
        }
    }

    /// 在 view 的祖先、同级或后代层级中全方位搜寻关联的 NSScrollView
    public static func findScrollView(from view: NSView) -> NSScrollView? {
        if let sv = view.enclosingScrollView { return sv }
        var current: NSView? = view.superview
        while let parent = current {
            if let sv = parent as? NSScrollView { return sv }
            for subview in parent.subviews {
                if let sv = subview as? NSScrollView { return sv }
                if let sv = findDescendant(of: subview) { return sv }
            }
            current = parent.superview
        }
        return nil
    }

    private static func findDescendant(of view: NSView) -> NSScrollView? {
        if let sv = view as? NSScrollView { return sv }
        for sub in view.subviews {
            if let sv = findDescendant(of: sub) { return sv }
        }
        return nil
    }

    /// 消除 NSScrollView 自身、ClipView 及其底层背景的所有白色实心填充
    public static func configure(_ scrollView: NSScrollView) {
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        scrollView.contentView.drawsBackground = false
        scrollView.contentView.backgroundColor = .clear

        if let doc = scrollView.documentView {
            doc.wantsLayer = true
            doc.layer?.backgroundColor = NSColor.clear.cgColor
        }

        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScroller = nil

        if !(scrollView.verticalScroller is ModernScroller) {
            let scroller = ModernScroller()
            scrollView.verticalScroller = scroller
        }
        scrollView.verticalScroller?.scrollerStyle = .overlay
        scrollView.verticalScroller?.wantsLayer = true
        scrollView.verticalScroller?.layer?.backgroundColor = NSColor.clear.cgColor
        scrollView.verticalScroller?.layer?.isOpaque = false
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
