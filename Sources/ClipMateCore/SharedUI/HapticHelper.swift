import AppKit

/// 原生触控板触觉反馈工具。由 AppSettings 同步开关状态，关闭时不触发任何反馈。
public enum HapticHelper {
    /// 设置项 `hapticFeedbackEnabled` 的镜像，主线程读写。
    public static var isEnabled = true

    /// 触发轻微对齐触觉反馈（适用于切换、选中、小操作）
    public static func alignment() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// 触发标准确认触觉反馈（适用于复制、保存、入队、粘贴）
    public static func feedback() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }

    /// 触发强调/通用触觉反馈（适用于固定、批量操作、清空）
    public static func generic() {
        guard isEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
}
