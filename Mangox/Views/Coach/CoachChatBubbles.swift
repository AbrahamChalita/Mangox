import SwiftUI

fileprivate enum CoachSuggestedActionNavigation {
    static func isNavigation(_ type: String) -> Bool {
        let k = type.lowercased()
        return k.hasPrefix("navigate") || k.contains("open_my_plans")
    }
}

// MARK: - Message row

struct CoachMessageRow: View {
    let message: ChatMessage
    /// Used only to show the model’s follow-up prompt under the newest assistant reply.
    let isLatestAssistant: Bool
    let bubbleMaxWidth: CGFloat
    /// When false, suggested-reply chips are visible but disabled (e.g. while a new reply is streaming).
    var suggestionsInteractive: Bool = true
    var onRetry: () -> Void = {}
    var onSuggestedAction: (SuggestedAction) -> Void = { _ in }
    /// When `followUpBlocks.count > 1`, the user answers all cards locally; this sends one combined user message.
    var onFollowUpBatchComplete: (String) -> Void = { _ in }

    private var showReplyPanel: Bool {
        guard isLatestAssistant else { return false }
        if !message.followUpBlocks.isEmpty { return true }
        let q = message.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !q.isEmpty { return true }
        let cat = (message.category ?? "").lowercased()
        if !message.suggestedActions.isEmpty,
            cat == "clarification" || cat.contains("clarif")
        {
            // Plan-intake recovery: chips without repeating the main bubble as a second “Coach asks” block.
            return true
        }
        // No "Coach asks" line: only show shortcuts (e.g. Open My plans), not orphan ask_followup chips.
        return message.suggestedActions.contains { $0.type.lowercased() != "ask_followup" }
    }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            if message.role == .user {
                CoachUserBubble(text: message.content, bubbleMaxWidth: bubbleMaxWidth)
            } else {
                if message.category == "error" {
                    CoachErrorBubble(text: message.content, onRetry: onRetry, bubbleMaxWidth: bubbleMaxWidth)
                } else {
                    CoachAssistantBubble(message: message, bubbleMaxWidth: bubbleMaxWidth)
                }

                if showReplyPanel {
                    if message.followUpBlocks.isEmpty {
                        CoachFollowUpRepliesPanel(
                            followUpQuestion: message.followUpQuestion,
                            actions: message.suggestedActions,
                            bubbleMaxWidth: bubbleMaxWidth,
                            isEnabled: suggestionsInteractive,
                            onSelect: onSuggestedAction
                        )
                    } else if message.followUpBlocks.count > 1 {
                        CoachFollowUpBlocksCarousel(
                            messageId: message.id,
                            blocks: message.followUpBlocks,
                            bubbleMaxWidth: bubbleMaxWidth,
                            isEnabled: suggestionsInteractive,
                            onImmediateAction: onSuggestedAction,
                            onBatchComplete: onFollowUpBatchComplete
                        )
                    } else if let block = message.followUpBlocks.first {
                        CoachFollowUpRepliesPanel(
                            followUpQuestion: block.question,
                            actions: block.suggestedActions,
                            bubbleMaxWidth: bubbleMaxWidth,
                            isEnabled: suggestionsInteractive,
                            onSelect: onSuggestedAction
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - User

struct CoachUserBubble: View {
    let text: String
    let bubbleMaxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Color.black.opacity(0.88))
            .padding(.horizontal, 17)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.mango,
                                Color(red: 1, green: 0.78, blue: 0.22),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: AppColor.mango.opacity(0.22), radius: 12, y: 4)
            .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Your message")
            .accessibilityValue(text)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
    }
}

// MARK: - Assistant

struct CoachAssistantBubble: View {
    let message: ChatMessage
    let bubbleMaxWidth: CGFloat

    private var displayText: AttributedString {
        CoachAssistantFormatting.attributedContent(from: message.content)
    }

    private var categoryIcon: String {
        switch message.category {
        case "training_advice": "bicycle"
        case "plan_analysis": "chart.bar.fill"
        case "nutrition": "fork.knife"
        case "recovery": "waveform.path.ecg"
        case "equipment": "gearshape.fill"
        case "clarification": "questionmark.circle.fill"
        default: "sparkles"
        }
    }

    private var categoryLabel: String {
        switch message.category {
        case "training_advice": "Training"
        case "plan_analysis": "Plan"
        case "nutrition": "Nutrition"
        case "recovery": "Recovery"
        case "equipment": "Equipment"
        case "clarification": "Clarify"
        default: "Coach"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColor.mango.opacity(0.95), AppColor.mango.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 14)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: categoryIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.mango)
                    Text(categoryLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.38))
                        .tracking(0.65)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                Text(displayText)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(5)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                if message.usedWebSearch {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.mango.opacity(0.85))
                        Text("Answer used live web sources")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Answer used live web sources")
                }

                if !message.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.52))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Color.white.opacity(0.07))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.bottom, 10)
                }

                if !message.thinkingSteps.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 12)
                    CoachThinkingDisclosure(steps: message.thinkingSteps)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }

                if !message.references.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 12)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sources")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.32))
                            .tracking(0.5)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)

                        ForEach(Array(message.references.enumerated()), id: \.offset) { _, ref in
                            if let urlStr = ref.url, !urlStr.isEmpty,
                               let url = URL(string: urlStr),
                               let scheme = url.scheme?.lowercased(),
                               scheme == "http" || scheme == "https" {
                                Link(destination: url) {
                                    referenceRow(title: ref.title, snippet: ref.snippet)
                                }
                                .accessibilityHint("Opens in Safari")
                            } else {
                                referenceRow(title: ref.title, snippet: ref.snippet)
                            }
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.09),
                            Color.white.opacity(0.045),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.06),
                            AppColor.mango.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, y: 8)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
        .accessibilityValue(message.content)
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private func referenceRow(title: String, snippet: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.22))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.mango.opacity(0.75))
            }
            if let snippet = snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Error

struct CoachErrorBubble: View {
    let text: String
    let onRetry: () -> Void
    let bubbleMaxWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.red.opacity(0.9))
                Text("Couldn’t reach coach")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.red.opacity(0.95))
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onRetry) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Try again")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(AppColor.red.opacity(0.65))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColor.red.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppColor.red.opacity(0.22), lineWidth: 1)
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

// MARK: - Thinking disclosure

struct CoachThinkingDisclosure: View {
    let steps: [String]
    @State private var expanded = false

    private var combinedText: String {
        steps.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                    Text("Reasoning")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.32))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Collapse reasoning" : "Expand reasoning")

            if expanded {
                Text(combinedText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Streaming

struct CoachStreamStatusRow: View {
    let text: String
    let bubbleMaxWidth: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(AppColor.mango.opacity(0.9))
                .scaleEffect(0.88)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Coach status: \(text)")
    }
}

struct CoachStreamingBubble: View {
    let text: String
    let bubbleMaxWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColor.mango.opacity(0.85), AppColor.mango.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.mango)
                    Text("COACH")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.38))
                        .tracking(0.65)
                }
                Text(CoachAssistantFormatting.plainTextForStreaming(text))
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.35), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Coach is writing a reply")
    }
}

// MARK: - Shared prompt row (suggested replies + empty-state starters)

/// Full-width tap target shared by coach suggested replies and conversation starters.
struct CoachTallPromptButton: View {
    let title: String
    var subtitle: String? = nil
    var leadingSystemImage: String? = nil
    var trailingSystemImage: String = "arrow.up.circle.fill"
    var trailingTint: Color = AppColor.mango.opacity(0.95)
    var isEnabled: Bool = true
    /// When nil, a default label is derived from `title`.
    var accessibilityLabelOverride: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let leadingSystemImage {
                    Image(systemName: leadingSystemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isEnabled ? AppColor.mango.opacity(0.92) : .white.opacity(0.22))
                        .frame(width: 26, alignment: .center)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: (subtitle == nil || subtitle?.isEmpty == true) ? 0 : 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isEnabled ? .white.opacity(0.92) : .white.opacity(0.35))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(isEnabled ? 0.44 : 0.28))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: trailingSystemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isEnabled ? trailingTint : .white.opacity(0.2))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: (subtitle == nil || subtitle?.isEmpty == true) ? 52 : 58, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 0.1 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isEnabled ? 0.12 : 0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabelOverride ?? title)
    }
}

// MARK: - Empty state starters (same card language as follow-up replies)

struct CoachEmptyStartersPanel: View {
    let bubbleMaxWidth: CGFloat
    let greetingTitle: String
    let headline: String
    let subhead: String
    let prompts: [AIService.QuickPrompt]
    let onPlanBuilder: () -> Void
    let onPrompt: (AIService.QuickPrompt) -> Void

    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.mango.opacity(0.95), AppColor.mango.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3)
                    .padding(.vertical, 16)
                    .padding(.leading, 14)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                        Text("COACH")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(textTertiary)
                            .tracking(0.65)
                    }
                    .accessibilityHidden(true)

                    Text(greetingTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(textPrimary)
                        .accessibilityLabel(greetingTitle)

                    Text(headline)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    Text(subhead)
                        .font(.caption)
                        .foregroundStyle(textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 16)
            }

            Rectangle()
                .fill(Color.white.opacity(AppOpacity.divider))
                .frame(height: 1)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.mango.opacity(0.85))
                    Text("QUICK STARTERS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(textTertiary)
                        .tracking(0.65)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                VStack(spacing: 8) {
                    CoachTallPromptButton(
                        title: "Build a training plan",
                        subtitle: "Event, target date, weekly hours — your coach structures the weeks.",
                        leadingSystemImage: "map.fill",
                        trailingSystemImage: "arrow.right.circle.fill",
                        trailingTint: AppColor.mango.opacity(0.95),
                        accessibilityLabelOverride: "Build a training plan, starts guided plan setup",
                        action: onPlanBuilder
                    )

                    ForEach(prompts) { p in
                        CoachTallPromptButton(
                            title: p.text,
                            leadingSystemImage: p.icon,
                            accessibilityLabelOverride: "Starter: \(p.text)",
                            action: { onPrompt(p) }
                        )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Multi-block follow-up (stepped carousel, one API send at the end)

/// Presents `followUpBlocks` one card at a time; navigation chips still fire immediately.
private struct CoachFollowUpBlocksCarousel: View {
    let messageId: UUID
    let blocks: [CoachFollowUpBlock]
    let bubbleMaxWidth: CGFloat
    var isEnabled: Bool
    let onImmediateAction: (SuggestedAction) -> Void
    let onBatchComplete: (String) -> Void

    @State private var step = 0
    @State private var collected: [(String, String)] = []
    @State private var hasSubmitted = false

    private var currentBlock: CoachFollowUpBlock? {
        guard step < blocks.count else { return nil }
        return blocks[step]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if blocks.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0 ..< blocks.count, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? AppColor.mango : Color.white.opacity(0.14))
                            .frame(width: i == step ? 18 : 7, height: 7)
                            .animation(.easeOut(duration: 0.2), value: step)
                    }
                    Spacer(minLength: 0)
                    Text("Step \(min(step + 1, blocks.count)) of \(blocks.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Question \(min(step + 1, blocks.count)) of \(blocks.count)")
            }

            if hasSubmitted {
                submittedSummary
            } else if let block = currentBlock {
                CoachFollowUpRepliesPanel(
                    followUpQuestion: block.question,
                    actions: block.suggestedActions,
                    bubbleMaxWidth: bubbleMaxWidth,
                    isEnabled: isEnabled,
                    onSelect: { handleSelect(question: block.question, $0) }
                )
            }
        }
        .onChange(of: messageId) { _, _ in
            step = 0
            collected = []
            hasSubmitted = false
        }
    }

    private var submittedSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.9))
                Text("Sent your answers")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            ForEach(Array(collected.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.25))
                    VStack(alignment: .leading, spacing: 2) {
                        if !pair.0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(pair.0)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                        Text(pair.1)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.22), lineWidth: 1)
        )
    }

    private func handleSelect(question: String, _ action: SuggestedAction) {
        guard isEnabled else { return }
        if CoachSuggestedActionNavigation.isNavigation(action.type) {
            onImmediateAction(action)
            return
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = action.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = (q, answer)
        if step >= blocks.count - 1 {
            let all = collected + [row]
            collected = all
            hasSubmitted = true
            onBatchComplete(Self.formatBatchMessage(all))
        } else {
            collected.append(row)
            step += 1
        }
    }

    private static func formatBatchMessage(_ rows: [(String, String)]) -> String {
        let lines = rows.map { q, a in
            if q.isEmpty { return "• \(a)" }
            return "• \(q) — \(a)"
        }
        return "Here are my answers:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - Follow-up question + suggested replies (unified vertical card)

/// Single card so the coach question and quick replies read as one step, with full-width vertical tap targets.
struct CoachFollowUpRepliesPanel: View {
    let followUpQuestion: String?
    let actions: [SuggestedAction]
    let bubbleMaxWidth: CGFloat
    var isEnabled: Bool = true
    let onSelect: (SuggestedAction) -> Void

    private var trimmedQuestion: String {
        followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var hasQuestion: Bool { !trimmedQuestion.isEmpty }
    private var hasActions: Bool { !actions.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasQuestion {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                        Text("Coach asks")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))
                            .tracking(0.4)
                    }

                    Text(trimmedQuestion)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(16)
            }

            if hasQuestion && hasActions {
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 14)
            }

            if hasActions {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.mango.opacity(0.85))
                        Text("Pick a reply")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.42))
                            .tracking(0.4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, hasQuestion ? 14 : 16)

                    VStack(spacing: 8) {
                        ForEach(actions) { action in
                            suggestedReplyButton(action)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            AppColor.mango.opacity(0.1),
                            Color.white.opacity(0.045),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppColor.mango.opacity(0.35),
                            Color.white.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
    }

    private func suggestedReplyButton(_ action: SuggestedAction) -> some View {
        let navigates = CoachSuggestedActionNavigation.isNavigation(action.type)
        return CoachTallPromptButton(
            title: action.label,
            trailingSystemImage: navigates ? "arrow.right.circle.fill" : "arrow.up.circle.fill",
            trailingTint: navigates ? AppColor.blue.opacity(0.9) : AppColor.mango.opacity(0.95),
            isEnabled: isEnabled,
            accessibilityLabelOverride: navigates
                ? "\(action.label), opens elsewhere"
                : "Suggested reply: \(action.label)",
            action: { onSelect(action) }
        )
    }

}

// MARK: - Typing

struct CoachTypingRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let bubbleMaxWidth: CGFloat
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white.opacity(0.4))
                    .frame(width: 7, height: 7)
                    .scaleEffect(accessibilityReduceMotion ? 1 : (phase == 0 ? 0.72 : 1.2))
                    .animation(
                        .easeInOut(duration: 0.38)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .onAppear {
            if !accessibilityReduceMotion { phase = 1 }
        }
        .onDisappear { phase = 0 }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityLabel("Coach is typing")
    }
}

