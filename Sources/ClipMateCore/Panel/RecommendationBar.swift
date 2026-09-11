import SwiftUI
import AppKit

/// 独立智能推荐区：在列表顶部提供最多 3 条快捷候选
/// 普通历史保持原顺序，数字快捷键（⌘1~9）对应的条目不受推荐影响。
struct RecommendationBar: View {
    @ObservedObject var viewModel: PanelViewModel
    @ObservedObject var settings: AppSettings

    init(viewModel: PanelViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        if settings.enableSmartRecommendations && viewModel.query.isEmpty && !viewModel.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(settings.appTheme.accent)
                    Text(L10n.tr("rec.title", lang: settings.appLanguage))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.recommendations) { rec in
                            RecommendationCard(
                                rec: rec,
                                theme: settings.appTheme,
                                language: settings.appLanguage,
                                onPaste: { viewModel.paste(item: rec.item) },
                                onCopy: { viewModel.copy(item: rec.item) },
                                onPasteField: { field in viewModel.pasteField(field, for: rec.item) },
                                onDismiss: { viewModel.dismissRecommendation(id: rec.item.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
            .background(settings.appTheme.accent.opacity(0.03))
        }
    }
}

/// 单个推荐条目卡片
struct RecommendationCard: View {
    let rec: RecommendedItem
    let theme: AppTheme
    let language: AppLanguage
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onPasteField: (ExtractedField) -> Void
    let onDismiss: () -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                // 推荐原因徽标
                HStack(spacing: 2.5) {
                    Image(systemName: rec.reason.systemImage)
                        .font(.system(size: 7.5))
                    Text(rec.reasonText)
                        .font(.system(size: 8.5, weight: .medium))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(theme.accent.opacity(0.16)))
                .foregroundStyle(theme.accent)

                Spacer(minLength: 4)

                // 悬停显示隐藏推荐按钮
                if hovered {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("rec.dismiss", lang: language))
                }
            }

            // 内容文本预览
            Button(action: onPaste) {
                let displayText: String = {
                    if let title = rec.item.title, !title.isEmpty { return title }
                    return rec.item.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
                }()

                Text(displayText)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .buttonStyle(.plain)

            // 若为“同份资料”，直接呈现剩余未取用的快捷字段胶囊
            if !rec.unusedFields.isEmpty {
                HStack(spacing: 3) {
                    ForEach(rec.unusedFields.prefix(2)) { field in
                        Button {
                            onPasteField(field)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: field.kind.systemImage)
                                    .font(.system(size: 7))
                                Text(field.label)
                                    .font(.system(size: 8))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)))
                            .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(field.value)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovered ? theme.hoverBackground : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(hovered ? theme.accent.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovered = $0 }
        .help(rec.item.plainText)
    }
}
