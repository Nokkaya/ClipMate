import SwiftUI

/// 自适应换行流式布局（macOS 13+ 原生 Layout 协议）。
/// 当子视图总宽度超出容器可用宽度时，自动按行折行排列，避免单行水平溢出被截断。
public struct FlowLayout: Layout {
    public var spacing: CGFloat
    public var rowSpacing: CGFloat

    public init(spacing: CGFloat = 6, rowSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        guard maxWidth > 0, maxWidth != .infinity else {
            var totalW: CGFloat = 0
            var maxH: CGFloat = 0
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                totalW += size.width + spacing
                maxH = max(maxH, size.height)
            }
            if !subviews.isEmpty { totalW -= spacing }
            return CGSize(width: totalW, height: maxH)
        }

        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                maxRowWidth = max(maxRowWidth, currentX - spacing)
                currentX = 0
                currentY += lineHeight + rowSpacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, currentX > 0 ? currentX - spacing : 0)

        let totalHeight = currentY + lineHeight
        return CGSize(width: min(maxWidth, maxRowWidth), height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.minX + maxWidth, currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + rowSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
