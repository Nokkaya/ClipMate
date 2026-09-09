import SwiftUI
import AppKit

/// 支持的应用主题风格
public enum AppTheme: String, CaseIterable, Codable, Identifiable {
    case `default` = "default"
    case oneDarkPro = "oneDarkPro"
    case dracula = "dracula"
    case tokyoNight = "tokyoNight"
    case nord = "nord"
    case monokai = "monokai"
    case githubLight = "githubLight"

    public var id: String { rawValue }

    /// 向前兼容别名
    public static let darcula = AppTheme.dracula

    public init?(rawValue: String) {
        switch rawValue {
        case "default": self = .default
        case "oneDarkPro": self = .oneDarkPro
        case "dracula", "darcula": self = .dracula
        case "tokyoNight": self = .tokyoNight
        case "nord": self = .nord
        case "monokai": self = .monokai
        case "githubLight": self = .githubLight
        default: return nil
        }
    }

    /// 主题对应在设置中的本地化显示名称
    public func displayName(lang: AppLanguage = .system) -> String {
        L10n.tr("theme.\(rawValue)", lang: lang)
    }

    /// 主题简介
    public func displayDesc(lang: AppLanguage = .system) -> String {
        L10n.tr("theme.desc.\(rawValue)", lang: lang)
    }

    /// 窗口强制深浅模式外观（nil 表示跟随系统外观）
    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .default:
            return nil
        case .oneDarkPro, .dracula, .tokyoNight, .nord, .monokai:
            return .dark
        case .githubLight:
            return .light
        }
    }

    /// 叠加在毛玻璃背景之上的半透明亚克力底色（nil 则保持原生毛玻璃通透材质）
    public var backgroundTint: Color? {
        switch self {
        case .default:
            return nil
        case .oneDarkPro:
            return Color(hex: 0x282C34, opacity: 0.88)
        case .dracula:
            return Color(hex: 0x282A36, opacity: 0.90)
        case .tokyoNight:
            return Color(hex: 0x1A1B26, opacity: 0.88)
        case .nord:
            return Color(hex: 0x2E3440, opacity: 0.88)
        case .monokai:
            return Color(hex: 0x272822, opacity: 0.90)
        case .githubLight:
            return Color(hex: 0xFFFFFF, opacity: 0.92)
        }
    }

    /// 模拟缩略预览时使用的不透明底色（供设置面板色卡展示）
    public var previewBackgroundColor: Color {
        switch self {
        case .default:
            return Color(nsColor: .windowBackgroundColor)
        case .oneDarkPro:
            return Color(hex: 0x282C34)
        case .dracula:
            return Color(hex: 0x282A36)
        case .tokyoNight:
            return Color(hex: 0x1A1B26)
        case .nord:
            return Color(hex: 0x2E3440)
        case .monokai:
            return Color(hex: 0x272822)
        case .githubLight:
            return Color(hex: 0xFFFFFF)
        }
    }

    /// 搜索栏与输入栏背景
    public var searchBarBackground: Color {
        switch self {
        case .default:
            return Color.primary.opacity(0.04)
        case .oneDarkPro:
            return Color(hex: 0x21252B)
        case .dracula:
            return Color(hex: 0x21222C)
        case .tokyoNight:
            return Color(hex: 0x16161E)
        case .nord:
            return Color(hex: 0x242933)
        case .monokai:
            return Color(hex: 0x1E1F1C)
        case .githubLight:
            return Color(hex: 0xF6F8FA)
        }
    }

    /// 悬浮主面板与浮层的精致外边框
    public var borderColor: Color {
        switch self {
        case .default:
            return Color.primary.opacity(0.12)
        case .oneDarkPro:
            return Color(hex: 0x3E4451)
        case .dracula:
            return Color(hex: 0x6272A4, opacity: 0.6)
        case .tokyoNight:
            return Color(hex: 0x292E42)
        case .nord:
            return Color(hex: 0x434C5E)
        case .monokai:
            return Color(hex: 0x3E3D32)
        case .githubLight:
            return Color(hex: 0xD0D7DE)
        }
    }

    /// 主题专属核心强调色
    public var accent: Color {
        switch self {
        case .default:
            return Color.accentColor
        case .oneDarkPro:
            return Color(hex: 0x56B6C2)
        case .dracula:
            return Color(hex: 0xBD93F9)
        case .tokyoNight:
            return Color(hex: 0x7DCFFF)
        case .nord:
            return Color(hex: 0x88C0D0)
        case .monokai:
            return Color(hex: 0xFFD866)
        case .githubLight:
            return Color(hex: 0x0969DA)
        }
    }

    /// 选中列表行底色
    public var selectionBackground: Color {
        switch self {
        case .default:
            return Color.accentColor.opacity(0.16)
        case .oneDarkPro:
            return Color(hex: 0x3E4451, opacity: 0.75)
        case .dracula:
            return Color(hex: 0x44475A, opacity: 0.85)
        case .tokyoNight:
            return Color(hex: 0x283457, opacity: 0.75)
        case .nord:
            return Color(hex: 0x434C5E, opacity: 0.75)
        case .monokai:
            return Color(hex: 0x49483E, opacity: 0.80)
        case .githubLight:
            return Color(hex: 0xDDF4FF, opacity: 0.90)
        }
    }

    /// 悬停列表行底色
    public var hoverBackground: Color {
        switch self {
        case .default:
            return Color.primary.opacity(0.05)
        case .oneDarkPro:
            return Color(hex: 0x2C313A, opacity: 0.6)
        case .dracula:
            return Color(hex: 0x44475A, opacity: 0.50)
        case .tokyoNight:
            return Color(hex: 0x1F2335, opacity: 0.7)
        case .nord:
            return Color(hex: 0x3B4252, opacity: 0.6)
        case .monokai:
            return Color(hex: 0x3E3D32, opacity: 0.6)
        case .githubLight:
            return Color(hex: 0xF3F4F6, opacity: 0.7)
        }
    }

    /// 剪贴板条目各类型对应的高光色彩
    public func color(for kind: ClipKind) -> Color {
        switch self {
        case .default:
            switch kind {
            case .text: return Palette.adaptive(light: 0x3D7BF0, dark: 0x82AFFF)
            case .url: return Palette.adaptive(light: 0x0E9488, dark: 0x45C4B0)
            case .richText: return Palette.adaptive(light: 0x6366F1, dark: 0x818CF8)
            case .image: return Palette.adaptive(light: 0x0284C7, dark: 0x38BDF8)
            case .file: return Palette.adaptive(light: 0xC07A17, dark: 0xE5B05E)
            case .pdf: return Palette.adaptive(light: 0xC24A56, dark: 0xE58A94)
            }
        case .oneDarkPro:
            switch kind {
            case .text: return Color(hex: 0xABB2BF)
            case .url: return Color(hex: 0x61AFEF)
            case .richText: return Color(hex: 0xC678DD)
            case .image: return Color(hex: 0x98C379)
            case .file: return Color(hex: 0xE5C07B)
            case .pdf: return Color(hex: 0xE06C75)
            }
        case .dracula:
            switch kind {
            case .text: return Color(hex: 0xF8F8F2)
            case .url: return Color(hex: 0x8BE9FD)
            case .richText: return Color(hex: 0xBD93F9)
            case .image: return Color(hex: 0x50FA7B)
            case .file: return Color(hex: 0xFFB86C)
            case .pdf: return Color(hex: 0xFF5555)
            }
        case .tokyoNight:
            switch kind {
            case .text: return Color(hex: 0xC0CAF5)
            case .url: return Color(hex: 0x7AA2F7)
            case .richText: return Color(hex: 0xBB9AF7)
            case .image: return Color(hex: 0x9ECE6A)
            case .file: return Color(hex: 0xE0AF68)
            case .pdf: return Color(hex: 0xF7768E)
            }
        case .nord:
            switch kind {
            case .text: return Color(hex: 0xD8DEE9)
            case .url: return Color(hex: 0x81A1C1)
            case .richText: return Color(hex: 0xB48EAD)
            case .image: return Color(hex: 0xA3BE8C)
            case .file: return Color(hex: 0xEBCB8B)
            case .pdf: return Color(hex: 0xBF616A)
            }
        case .monokai:
            switch kind {
            case .text: return Color(hex: 0xF8F8F2)
            case .url: return Color(hex: 0x78DCE8)
            case .richText: return Color(hex: 0xAB9DF2)
            case .image: return Color(hex: 0xA9DC76)
            case .file: return Color(hex: 0xFC9867)
            case .pdf: return Color(hex: 0xFF6188)
            }
        case .githubLight:
            switch kind {
            case .text: return Color(hex: 0x24292F)
            case .url: return Color(hex: 0x0969DA)
            case .richText: return Color(hex: 0x8250DF)
            case .image: return Color(hex: 0x1A7F37)
            case .file: return Color(hex: 0x9A6700)
            case .pdf: return Color(hex: 0xCF222E)
            }
        }
    }

    /// 常用片段高亮色
    public var snippetColor: Color {
        switch self {
        case .default:
            return Palette.adaptive(light: 0xC26D00, dark: 0xF59E0B)
        case .oneDarkPro:
            return Color(hex: 0xD19A66)
        case .dracula:
            return Color(hex: 0xF1FA8C)
        case .tokyoNight:
            return Color(hex: 0xFF9E64)
        case .nord:
            return Color(hex: 0xD08770)
        case .monokai:
            return Color(hex: 0xFFD866)
        case .githubLight:
            return Color(hex: 0xBC4C00)
        }
    }

    /// 固定标记色
    public var pinColor: Color {
        switch self {
        case .default:
            return Color.orange
        case .oneDarkPro:
            return Color(hex: 0xE5C07B)
        case .dracula:
            return Color(hex: 0xFFB86C)
        case .tokyoNight:
            return Color(hex: 0xE0AF68)
        case .nord:
            return Color(hex: 0xEBCB8B)
        case .monokai:
            return Color(hex: 0xFFD866)
        case .githubLight:
            return Color(hex: 0x9A6700)
        }
    }

    /// AI 提示与强调色
    public var aiColor: Color {
        switch self {
        case .default:
            return Palette.adaptive(light: 0x4F46E5, dark: 0x818CF8)
        case .oneDarkPro:
            return Color(hex: 0xC678DD)
        case .dracula:
            return Color(hex: 0xFF79C6)
        case .tokyoNight:
            return Color(hex: 0xBB9AF7)
        case .nord:
            return Color(hex: 0xB48EAD)
        case .monokai:
            return Color(hex: 0xAB9DF2)
        case .githubLight:
            return Color(hex: 0x8250DF)
        }
    }

    /// 预览色卡（供设置面板画廊卡片呈现 4 个特征色点）
    public var previewSwatches: [Color] {
        switch self {
        case .default:
            return [Color(hex: 0x3D7BF0), Color(hex: 0x0E9488), Color(hex: 0x6366F1), Color(hex: 0xC07A17)]
        case .oneDarkPro:
            return [Color(hex: 0x61AFEF), Color(hex: 0x98C379), Color(hex: 0xE5C07B), Color(hex: 0xC678DD)]
        case .dracula:
            return [Color(hex: 0xBD93F9), Color(hex: 0xFF79C6), Color(hex: 0x8BE9FD), Color(hex: 0x50FA7B)]
        case .tokyoNight:
            return [Color(hex: 0x7DCFFF), Color(hex: 0xBB9AF7), Color(hex: 0x9ECE6A), Color(hex: 0x7AA2F7)]
        case .nord:
            return [Color(hex: 0x88C0D0), Color(hex: 0x81A1C1), Color(hex: 0xA3BE8C), Color(hex: 0xEBCB8B)]
        case .monokai:
            return [Color(hex: 0x78DCE8), Color(hex: 0xA9DC76), Color(hex: 0xFFD866), Color(hex: 0xFF6188)]
        case .githubLight:
            return [Color(hex: 0x0969DA), Color(hex: 0x1A7F37), Color(hex: 0x9A6700), Color(hex: 0x8250DF)]
        }
    }
}

extension Color {
    /// 0xRRGGBB 初始化颜色
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
