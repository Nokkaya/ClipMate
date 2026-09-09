import SwiftUI
import AppKit

/// 配色板。
/// 原则：类型标识色用低饱和、亮暗自适应的定制色调，保证在毛玻璃底上不刺眼、层次清晰；
/// 交互控件（按钮/选中态/焦点）跟随系统强调色，保持 macOS 原生一致性。
public enum Palette {

    /// 当前全局激活的主题（由 AppSettings 同步更新）
    public static var currentTheme: AppTheme = .default

    /// 0xRRGGBB 亮/暗双态自适应颜色。
    public static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        })
    }

    /// 根据当前主题获取指定条目类型的色彩
    public static func color(for kind: ClipKind) -> Color {
        currentTheme.color(for: kind)
    }

    /// 文本类型
    public static var text: Color { currentTheme.color(for: .text) }
    /// 链接类型
    public static var url: Color { currentTheme.color(for: .url) }
    /// 富文本类型
    public static var richText: Color { currentTheme.color(for: .richText) }
    /// 图片类型
    public static var image: Color { currentTheme.color(for: .image) }
    /// 文件类型
    public static var file: Color { currentTheme.color(for: .file) }
    /// PDF 类型
    public static var pdf: Color { currentTheme.color(for: .pdf) }

    /// 固定标记（金/橙）
    public static var pin: Color { currentTheme.pinColor }
    /// 常用片段标记
    public static var snippet: Color { currentTheme.snippetColor }
    /// AI 特性强调色
    public static var ai: Color { currentTheme.aiColor }
    /// 破坏性操作。
    public static let danger = Color.red

    /// "#RGB" / "#RRGGBB" / "#RRGGBBAA" → Color（用于色值条目的色卡展示）。
    public static func color(hexString: String) -> Color? {

        var hex = hexString.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        if hex.hasPrefix("0x") { hex.removeFirst(2) }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        if hex.count == 6 {
            guard let value = UInt64(hex, radix: 16) else { return nil }
            return Color(
                red: Double((value >> 16) & 0xFF) / 255,
                green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255
            )
        } else if hex.count == 8 {
            guard let value = UInt64(hex, radix: 16) else { return nil }
            return Color(
                red: Double((value >> 24) & 0xFF) / 255,
                green: Double((value >> 16) & 0xFF) / 255,
                blue: Double((value >> 8) & 0xFF) / 255,
                opacity: Double(value & 0xFF) / 255
            )
        }
        return nil
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
