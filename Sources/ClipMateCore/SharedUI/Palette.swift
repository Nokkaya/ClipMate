import SwiftUI
import AppKit

/// 配色板。
/// 原则：类型标识色用低饱和、亮暗自适应的定制色调，保证在毛玻璃底上不刺眼、层次清晰；
/// 交互控件（按钮/选中态/焦点）跟随系统强调色，保持 macOS 原生一致性。
enum Palette {
    /// 0xRRGGBB 亮/暗双态自适应颜色。
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }

    /// 文本类型：蓝（比系统蓝柔和一档）
    static let text = adaptive(light: 0x3D7BF0, dark: 0x82AFFF)
    /// 链接类型：青绿
    static let url = adaptive(light: 0x0E9488, dark: 0x45C4B0)
    /// 富文本类型：堇紫
    static let richText = adaptive(light: 0x8B6FD8, dark: 0xB39DEB)
    /// 图片类型：洋红紫
    static let image = adaptive(light: 0xA45DC8, dark: 0xC99BE8)
    /// 文件类型：琥珀
    static let file = adaptive(light: 0xC07A17, dark: 0xE5B05E)
    /// PDF 类型：砖红
    static let pdf = adaptive(light: 0xC24A56, dark: 0xE58A94)

    /// 固定标记。
    static let pin = Color.orange
    /// 破坏性操作。
    static let danger = Color.red

    /// "#RRGGBB" / "RRGGBB" → Color（用于色值条目的色卡展示）。
    static func color(hexString: String) -> Color? {
        var hex = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension NSColor {
    /// 0xRRGGBB → NSColor（sRGB）。
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
