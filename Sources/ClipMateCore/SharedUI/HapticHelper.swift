import AppKit

/// 原生触控板触觉反馈工具。
public enum HapticHelper {
    /// 触发轻微对齐触觉反馈（适用于切换、选中、小操作）
    public static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
    }

    /// 触发标准确认触觉反馈（适用于复制、保存、入队、粘贴）
    public static func feedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
    }

    /// 触发强调/通用触觉反馈（适用于固定、批量操作、清空）
    public static func generic() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
}
