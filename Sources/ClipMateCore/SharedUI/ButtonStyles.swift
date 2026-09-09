import SwiftUI
import AppKit

// MARK: - 1. 毛玻璃次要/常规按钮 (ClipMateGlassButtonStyle)

public struct ClipMateGlassButtonStyle: ButtonStyle {
    public var size: ControlSize

    public init(size: ControlSize = .regular) {
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, size: size)
    }

    private struct GlassButtonBody: View {
        let configuration: Configuration
        let size: ControlSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var cornerRadius: CGFloat {
            size == .small ? 6 : 8
        }

        private var horizontalPadding: CGFloat {
            size == .small ? 9 : 14
        }

        private var verticalPadding: CGFloat {
            size == .small ? 4.5 : 6.5
        }

        private var fontSize: CGFloat {
            size == .small ? 11 : 12.5
        }

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(Color.primary.opacity(configuration.isPressed ? 0.65 : (isHovered ? 0.95 : 0.82)))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            Color.primary.opacity(
                                !isEnabled ? 0.03 :
                                (configuration.isPressed ? 0.16 : (isHovered ? 0.10 : 0.05))
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(!isEnabled ? 0.04 : (isHovered ? 0.15 : 0.08)),
                            lineWidth: 0.8
                        )
                }
                .scaleEffect(isEnabled && configuration.isPressed ? 0.98 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

// MARK: - 2. 品牌高亮/强调按钮 (ClipMateAccentButtonStyle)

public struct ClipMateAccentButtonStyle: ButtonStyle {
    public var size: ControlSize
    public var tint: Color

    public init(size: ControlSize = .regular, tint: Color = .accentColor) {
        self.size = size
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        AccentButtonBody(configuration: configuration, size: size, tint: tint)
    }

    private struct AccentButtonBody: View {
        let configuration: Configuration
        let size: ControlSize
        let tint: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var cornerRadius: CGFloat {
            size == .small ? 6 : 8
        }

        private var horizontalPadding: CGFloat {
            size == .small ? 10 : 15
        }

        private var verticalPadding: CGFloat {
            size == .small ? 4.5 : 6.5
        }

        private var fontSize: CGFloat {
            size == .small ? 11 : 12.5
        }

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    tint.opacity(isHovered ? 1.0 : 0.92),
                                    tint.opacity(isHovered ? 0.90 : 0.82)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.8)
                }
                .shadow(
                    color: isEnabled ? tint.opacity(isHovered ? 0.38 : 0.22) : .clear,
                    radius: isHovered ? 5 : 3,
                    x: 0,
                    y: 1.5
                )
                .scaleEffect(isEnabled && configuration.isPressed ? 0.97 : 1.0)
                .opacity(isEnabled ? (configuration.isPressed ? 0.88 : (isHovered ? 1.0 : 0.96)) : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

// MARK: - 3. 危险破坏性操作按钮 (ClipMateDangerButtonStyle)

public struct ClipMateDangerButtonStyle: ButtonStyle {
    public var prominent: Bool
    public var size: ControlSize

    public init(prominent: Bool = false, size: ControlSize = .regular) {
        self.prominent = prominent
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        DangerButtonBody(configuration: configuration, prominent: prominent, size: size)
    }

    private struct DangerButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        let size: ControlSize
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var cornerRadius: CGFloat {
            size == .small ? 6 : 8
        }

        private var horizontalPadding: CGFloat {
            size == .small ? 9 : 14
        }

        private var verticalPadding: CGFloat {
            size == .small ? 4.5 : 6.5
        }

        private var fontSize: CGFloat {
            size == .small ? 11 : 12.5
        }

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: prominent ? .semibold : .medium))
                .foregroundStyle(prominent ? .white : Color.red.opacity(configuration.isPressed ? 0.7 : 0.95))
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            prominent
                                ? Color.red.opacity(isHovered ? 0.95 : 0.86)
                                : Color.red.opacity(configuration.isPressed ? 0.18 : (isHovered ? 0.12 : 0.06))
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            prominent
                                ? Color.white.opacity(0.24)
                                : Color.red.opacity(isHovered ? 0.26 : 0.12),
                            lineWidth: 0.8
                        )
                }
                .shadow(
                    color: (prominent && isEnabled) ? Color.red.opacity(isHovered ? 0.38 : 0.22) : .clear,
                    radius: isHovered ? 5 : 3,
                    x: 0,
                    y: 1.5
                )
                .scaleEffect(isEnabled && configuration.isPressed ? 0.97 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

// MARK: - 4. AI 功能芯片按钮 (ClipMateAIChipButtonStyle)

public struct ClipMateAIChipButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        AIChipButtonBody(configuration: configuration)
    }

    private struct AIChipButtonBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.primary.opacity(!isEnabled ? 0.35 : (configuration.isPressed ? 0.60 : (isHovered ? 0.95 : 0.78))))
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(
                            Color.primary.opacity(
                                !isEnabled ? 0.02 :
                                (configuration.isPressed ? 0.12 : (isHovered ? 0.08 : 0.04))
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(!isEnabled ? 0.03 : (isHovered ? 0.16 : 0.07)),
                            lineWidth: 0.8
                        )
                }
                .scaleEffect(isEnabled && configuration.isPressed ? 0.96 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

// MARK: - 5. 轻量无边框图标按钮 (ClipMateIconButtonStyle)

public struct ClipMateIconButtonStyle: ButtonStyle {
    public var size: CGFloat
    public var tint: Color?

    public init(size: CGFloat = 26, tint: Color? = nil) {
        self.size = size
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, size: size, tint: tint)
    }

    private struct IconButtonBody: View {
        let configuration: Configuration
        let size: CGFloat
        let tint: Color?
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        private var effectiveTint: Color {
            tint ?? .primary
        }

        var body: some View {
            configuration.label
                .font(.system(size: max(10, size * 0.45)))
                .foregroundStyle(
                    effectiveTint.opacity(configuration.isPressed ? 0.65 : (isHovered ? 1.0 : 0.82))
                )
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            effectiveTint.opacity(
                                !isEnabled ? 0.0 :
                                (configuration.isPressed ? 0.16 : (isHovered ? 0.09 : 0.04))
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            effectiveTint.opacity(!isEnabled ? 0.0 : (isHovered ? 0.16 : 0.07)),
                            lineWidth: 0.8
                        )
                }
                .scaleEffect(isEnabled && configuration.isPressed ? 0.94 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.45)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onHover { hovering in
                    guard isEnabled else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovered = hovering
                    }
                }
        }
    }
}

// MARK: - 便捷 View Extensions

public extension View {
    /// ClipMate 次要/常规毛玻璃按钮样式
    func clipMateGlass(size: ControlSize = .regular) -> some View {
        buttonStyle(ClipMateGlassButtonStyle(size: size))
    }

    /// ClipMate 强调/高亮主要按钮样式
    func clipMateAccent(size: ControlSize = .regular, tint: Color = .accentColor) -> some View {
        buttonStyle(ClipMateAccentButtonStyle(size: size, tint: tint))
    }

    /// ClipMate 破坏/危险操作按钮样式
    func clipMateDanger(prominent: Bool = false, size: ControlSize = .regular) -> some View {
        buttonStyle(ClipMateDangerButtonStyle(prominent: prominent, size: size))
    }

    /// ClipMate AI 专属微晶胶囊芯片样式
    func clipMateAIChip() -> some View {
        buttonStyle(ClipMateAIChipButtonStyle())
    }

    /// ClipMate 轻量精致图标按钮样式
    func clipMateIconButton(size: CGFloat = 26, tint: Color? = nil) -> some View {
        buttonStyle(ClipMateIconButtonStyle(size: size, tint: tint))
    }
}
