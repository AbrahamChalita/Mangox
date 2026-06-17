import SwiftUI

// MARK: - Empty state starters (same card language as follow-up replies)

struct CoachEmptyStartersPanel: View {
    let bubbleMaxWidth: CGFloat
    let greetingTitle: String
    let headline: String
    let subhead: String
    /// Topic-style tags from `SystemLanguageModel(useCase: .contentTagging)` (Apple Intelligence).
    let topicTags: [String]
    let prompts: [QuickPrompt]
    var startersEnabled: Bool = true
    let onPlanBuilder: () -> Void
    let onPrompt: (QuickPrompt) -> Void

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    /// Matches Apple’s sample spirit (blurReplace) without requiring a specific SDK symbol name.
    private var tagAppearTransition: AnyTransition {
        if accessibilityReduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.96, anchor: .leading))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(AppColor.mango)
                    .frame(width: 2)

                VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                    HStack(spacing: MangoxSpacing.xs.rawValue) {
                        Image(systemName: "sparkles")
                            .font(MangoxFont.micro.value)
                            .foregroundStyle(AppColor.mango)
                        Text("COACH")
                            .mangoxFont(.micro)
                            .tracking(1.4)
                            .foregroundStyle(AppColor.fg3)
                    }
                    .accessibilityHidden(true)

                    Text(greetingTitle)
                        .font(MangoxFont.title.value)
                        .foregroundStyle(AppColor.fg0)
                        .accessibilityLabel(greetingTitle)

                    Text(headline)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg1)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(subhead)
                        .mangoxFont(.body)
                        .foregroundStyle(AppColor.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, MangoxSpacing.md.rawValue)
                .padding(.trailing, MangoxSpacing.lg.rawValue)
                .padding(.vertical, MangoxSpacing.lg.rawValue)
            }

            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
                if !topicTags.isEmpty {
                    VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                        HStack(spacing: MangoxSpacing.xs.rawValue) {
                            Image(systemName: "tag.fill")
                                .font(MangoxFont.micro.value)
                                .foregroundStyle(AppColor.blue.opacity(0.75))
                            Text("GROUNDED TOPICS")
                                .mangoxFont(.micro)
                                .tracking(1.2)
                                .foregroundStyle(AppColor.fg3)
                        }
                        .padding(.horizontal, MangoxSpacing.lg.rawValue)
                        .padding(.top, MangoxSpacing.md.rawValue)

                        Text("Based on the ride, plan, and recovery data Mangox can actually see right now.")
                            .mangoxFont(.caption)
                            .foregroundStyle(AppColor.fg2)
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: MangoxSpacing.xs.rawValue) {
                                ForEach(topicTags, id: \.self) { tag in
                                    Text("#\(CoachTagPillFormatting.displayLabel(for: tag).uppercased())")
                                        .mangoxFont(.micro)
                                        .tracking(1.0)
                                        .foregroundStyle(AppColor.fg2)
                                        .padding(.horizontal, MangoxSpacing.sm.rawValue)
                                        .padding(.vertical, 6)
                                        .mangoxSurface(
                                            .flatCustom(fill: Color.clear, border: AppColor.blue.opacity(0.35)),
                                            shape: .rounded(MangoxRadius.sharp.rawValue)
                                        )
                                        .transition(tagAppearTransition)
                                }
                            }
                            .padding(.horizontal, MangoxSpacing.lg.rawValue)
                            .padding(.bottom, 4)
                        }
                    }
                    .animation(
                        accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.35),
                        value: topicTags
                    )
                }

                HStack(spacing: MangoxSpacing.xs.rawValue) {
                    Image(systemName: "hand.tap.fill")
                        .font(MangoxFont.micro.value)
                        .foregroundStyle(AppColor.mango.opacity(0.85))
                    Text("QUICK STARTERS")
                        .mangoxFont(.micro)
                        .tracking(1.2)
                        .foregroundStyle(AppColor.fg3)
                }
                .padding(.horizontal, MangoxSpacing.lg.rawValue)
                .padding(.top, topicTags.isEmpty ? MangoxSpacing.md.rawValue : MangoxSpacing.xs.rawValue)

                VStack(spacing: MangoxSpacing.sm.rawValue) {
                    CoachTallPromptButton(
                        title: "Build a training plan",
                        subtitle: "Event, target date, weekly hours — guided setup for a full plan.",
                        leadingSystemImage: "map.fill",
                        trailingSystemImage: "arrow.right.circle.fill",
                        trailingTint: AppColor.mango.opacity(0.95),
                        isEnabled: startersEnabled,
                        accessibilityLabelOverride: "Build a training plan, starts guided plan setup",
                        action: onPlanBuilder
                    )

                    ForEach(prompts) { p in
                        CoachTallPromptButton(
                            title: p.text,
                            leadingSystemImage: p.icon,
                            isEnabled: startersEnabled,
                            accessibilityLabelOverride: "Starter: \(p.text)",
                            action: { onPrompt(p) }
                        )
                        .transition(tagAppearTransition)
                    }
                }
                .padding(.horizontal, MangoxSpacing.md.rawValue)
                .padding(.bottom, MangoxSpacing.md.rawValue)
                .animation(
                    accessibilityReduceMotion ? .easeInOut(duration: 0.18) : .smooth(duration: 0.38),
                    value: prompts.map(\.id)
                )
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .mangoxSurface(
            .flatCustom(fill: AppColor.bg2, border: AppColor.mango.opacity(0.28)),
            shape: .rounded(MangoxRadius.sharp.rawValue)
        )
        .accessibilityElement(children: .contain)
    }
}
