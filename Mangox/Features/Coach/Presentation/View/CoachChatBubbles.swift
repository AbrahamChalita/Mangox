import SwiftUI

enum CoachSuggestedActionNavigation {
    static func isNavigation(_ type: String) -> Bool {
        let k = type.lowercased()
        return k.hasPrefix("navigate") || k.contains("open_my_plans") || k == "start_workout"
    }
}

// MARK: - Suggested reply chip colors

enum CoachReplyChipPalette {
    case neutral
    case mangoWash
    case cyanWash
    case indigoWash

    static func forAction(_ action: SuggestedAction) -> CoachReplyChipPalette {
        let k = action.type.lowercased()
        if CoachSuggestedActionNavigation.isNavigation(k) { return .indigoWash }
        if k == "escalate_cloud" { return .mangoWash }
        if k == "on_device_followup" { return .cyanWash }
        return .neutral
    }

    func leadingIconTint(isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.22) }
        switch self {
        case .neutral: return AppColor.mango.opacity(0.92)
        case .mangoWash: return AppColor.mango.opacity(0.95)
        case .cyanWash: return Color.cyan.opacity(0.88)
        case .indigoWash: return Color.indigo.opacity(0.85)
        }
    }

    func gradientFill(isEnabled: Bool) -> LinearGradient {
        let top: Color
        let bottom: Color
        switch self {
        case .neutral:
            top = Color.white.opacity(isEnabled ? 0.1 : 0.04)
            bottom = Color.white.opacity(isEnabled ? 0.06 : 0.03)
        case .mangoWash:
            top = AppColor.mango.opacity(isEnabled ? 0.2 : 0.07)
            bottom = Color.white.opacity(isEnabled ? 0.07 : 0.04)
        case .cyanWash:
            top = Color.cyan.opacity(isEnabled ? 0.16 : 0.06)
            bottom = Color.white.opacity(isEnabled ? 0.06 : 0.03)
        case .indigoWash:
            top = Color.indigo.opacity(isEnabled ? 0.22 : 0.08)
            bottom = Color.white.opacity(isEnabled ? 0.07 : 0.04)
        }
        return LinearGradient(
            colors: [top, bottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    func strokeColor(isEnabled: Bool) -> Color {
        switch self {
        case .neutral: return Color.white.opacity(isEnabled ? 0.12 : 0.06)
        case .mangoWash: return AppColor.mango.opacity(isEnabled ? 0.42 : 0.14)
        case .cyanWash: return Color.cyan.opacity(isEnabled ? 0.38 : 0.12)
        case .indigoWash: return Color.indigo.opacity(isEnabled ? 0.4 : 0.14)
        }
    }

    func trailingOrbTint(isEnabled: Bool) -> Color {
        guard isEnabled else { return .white.opacity(0.2) }
        switch self {
        case .neutral: return AppColor.mango.opacity(0.95)
        case .mangoWash: return AppColor.mango.opacity(0.98)
        case .cyanWash: return Color.cyan.opacity(0.92)
        case .indigoWash: return Color.indigo.opacity(0.9)
        }
    }
}

// MARK: - Message row

struct CoachMessageRow: View {
    let message: ChatMessage
    /// Used only to show the model's follow-up prompt under the newest assistant reply.
    let isLatestAssistant: Bool
    let bubbleMaxWidth: CGFloat
    /// When false, suggested-reply chips are visible but disabled (e.g. while a new reply is streaming).
    var suggestionsInteractive: Bool = true
    var sentChipKey: String? = nil
    var showTimestamp: Bool = false
    var onRetry: () -> Void = {}
    var onRetryCloud: () -> Void = {}
    var onFeedback: (Int) -> Void = { _ in }
    var onSuggestedAction: (SuggestedAction) -> Void = { _ in }
    /// When `followUpBlocks.count > 1`, the user answers all cards locally; this sends one combined user message.
    var onFollowUpBatchComplete: (String) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    private var showReplyPanel: Bool {
        guard isLatestAssistant else { return false }
        if !message.followUpBlocks.isEmpty { return true }
        let q = message.followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !q.isEmpty { return true }
        let cat = (message.category ?? "").lowercased()
        if !message.suggestedActions.isEmpty,
            cat == "clarification" || cat.contains("clarif")
        {
            return true
        }
        return message.suggestedActions.contains { $0.type.lowercased() != "ask_followup" }
    }

    private var responseAppearance: CoachResponseAppearance {
        CoachResponseAppearance(messageCategory: message.category)
    }

    private var compactFollowUp: Bool {
        CoachMessagePresentation.shouldUseCompactFollowUp(for: message)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showTimestamp {
                Text(CoachMessageTimestampFormatting.label(for: message.timestamp))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                    .padding(.horizontal, 4)
            }

            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    CoachUserBubble(
                        text: message.content,
                        imageJPEG: message.imageJPEG,
                        imageCacheKey: message.id,
                        bubbleMaxWidth: bubbleMaxWidth
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if message.category == "error" {
                        CoachErrorBubble(
                            text: message.content,
                            failedTier: message.tags.first.flatMap { CoachDeliveryPath(rawValue: $0) },
                            onRetry: onRetry,
                            onRetryCloud: onRetryCloud,
                            bubbleMaxWidth: bubbleMaxWidth
                        )
                    } else {
                        CoachAssistantBubble(
                            message: message,
                            bubbleMaxWidth: bubbleMaxWidth,
                            inlineFollowUp: compactFollowUp && showReplyPanel
                                ? CoachInlineFollowUpModel(
                                    question: message.followUpQuestion,
                                    actions: message.suggestedActions,
                                    isEnabled: suggestionsInteractive,
                                    messageID: message.id,
                                    sentChipKey: sentChipKey,
                                    onSelect: onSuggestedAction
                                )
                                : nil,
                            showsFeedback: isLatestAssistant,
                            onFeedback: isLatestAssistant ? { onFeedback($0) } : nil
                        )
                    }

                    if showReplyPanel, !compactFollowUp {
                        // Multi-card carousel renders its own progress strip; avoid duplicating "Plan setup".
                        if message.followUpBlocks.count <= 1,
                            let progress = CoachPlanIntakeProgress.snapshot(for: message)
                        {
                            CoachPlanIntakeProgressStrip(snapshot: progress)
                                .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                        }

                        if message.followUpBlocks.isEmpty {
                            CoachFollowUpRepliesPanel(
                                followUpQuestion: message.followUpQuestion,
                                actions: message.suggestedActions,
                                bubbleMaxWidth: bubbleMaxWidth,
                                sourceAppearance: responseAppearance,
                                isEnabled: suggestionsInteractive,
                                messageID: message.id,
                                sentChipKey: sentChipKey,
                                onSelect: onSuggestedAction
                            )
                        } else if message.followUpBlocks.count > 1 {
                            CoachFollowUpBlocksCarousel(
                                messageId: message.id,
                                blocks: message.followUpBlocks,
                                bubbleMaxWidth: bubbleMaxWidth,
                                sourceAppearance: responseAppearance,
                                isEnabled: suggestionsInteractive,
                                sentChipKey: sentChipKey,
                                onImmediateAction: onSuggestedAction,
                                onBatchComplete: onFollowUpBatchComplete
                            )
                        } else if let block = message.followUpBlocks.first {
                            CoachFollowUpRepliesPanel(
                                followUpQuestion: block.question,
                                actions: block.suggestedActions,
                                bubbleMaxWidth: bubbleMaxWidth,
                                sourceAppearance: responseAppearance,
                                isEnabled: suggestionsInteractive,
                                messageID: message.id,
                                sentChipKey: sentChipKey,
                                onSelect: onSuggestedAction
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - User

private enum CoachUserBubbleImageCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
        return cache
    }()

    static func image(for data: Data, key: UUID) -> UIImage? {
        let cacheKey = key.uuidString as NSString
        if let cached = cache.object(forKey: cacheKey) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        // Cost roughly tracks decoded pixel buffer size.
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: cacheKey, cost: max(1, cost))
        return image
    }
}

struct CoachUserBubble: View {
    let text: String
    let imageJPEG: Data?
    var imageCacheKey: UUID? = nil
    let bubbleMaxWidth: CGFloat

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let imageJPEG,
                let cacheKey = imageCacheKey,
                let uiImage = CoachUserBubbleImageCache.image(for: imageJPEG, key: cacheKey)
            {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: min(bubbleMaxWidth, 220), maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(AppColor.bg0)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.mango, AppColor.mango.opacity(0.88)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .shadow(color: AppColor.mango.opacity(0.22), radius: 8, y: 3)
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yL10n.yourMessage)
        .accessibilityValue(text.isEmpty ? "Photo message" : text)
        .contextMenu {
            if !text.isEmpty {
                Button {
                    UIPasteboard.general.string = text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

// MARK: - Assistant

struct CoachAssistantBubble: View {
    let message: ChatMessage
    let bubbleMaxWidth: CGFloat
    var inlineFollowUp: CoachInlineFollowUpModel? = nil
    var showsFeedback: Bool = false
    var onFeedback: ((Int) -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var expandedLongBody = false
    @State private var isMetadataVisible = false
    @State private var sourcesExpanded = false

    private var displayText: AttributedString {
        CoachAssistantFormatting.cachedAttributedContent(from: message.content, category: message.category)
    }

    private var responseAppearance: CoachResponseAppearance {
        CoachResponseAppearance(messageCategory: message.category)
    }

    private var headerCategory: String? {
        CoachMessagePresentation.headerCategory(message: message, appearance: responseAppearance)
    }

    private var categoryIcon: String {
        CoachResponseAppearance.headerIcon(category: headerCategory, appearance: responseAppearance)
    }

    private var categoryLabel: String {
        CoachResponseAppearance.headerLabel(category: headerCategory, appearance: responseAppearance)
    }

    private var categoryAccent: Color {
        responseAppearance.accent
    }

    private var stripGradient: LinearGradient {
        responseAppearance.stripGradient
    }

    private var isShortReply: Bool {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < 140
            && !trimmed.contains("\n")
            && message.tags.count <= 1
            && message.references.isEmpty
            && message.thinkingSteps.isEmpty
    }

    private var shouldTruncateBody: Bool {
        message.content.count > 2000
            || message.content.components(separatedBy: "\n").count > 30
    }

    private var visibleTags: [String] {
        CoachMessagePresentation.displayTags(for: message, isShortReply: isShortReply)
    }

    private var showWebSourcesBadge: Bool {
        message.usedWebSearch && message.references.isEmpty
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(stripGradient)
                .frame(width: 3)
                .padding(.vertical, isShortReply ? 10 : 14)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 0) {
                if isShortReply {
                    // Short replies hug their text — the badge rides alongside instead of
                    // a full-width trailing row that would stretch the bubble to max width.
                    HStack(alignment: .top, spacing: 10) {
                        Text(displayText)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.94))
                            .lineSpacing(5)
                        CoachDeliveryBadge(appearance: responseAppearance, compact: true)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(categoryAccent)
                        Text(categoryLabel.uppercased())
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.white.opacity(0.38))
                            .tracking(0.65)
                        Text("·")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.22))
                        Text(responseAppearance.label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(categoryAccent.opacity(0.72))
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    Text(displayText)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.94))
                        .lineSpacing(5)
                        .lineLimit(expandedLongBody || !shouldTruncateBody ? nil : 20)
                        .padding(.horizontal, 16)
                        .padding(.bottom, shouldTruncateBody && !expandedLongBody ? 4 : 10)
                }

                if shouldTruncateBody {
                    Button {
                        withAnimation(MangoxMotion.snappy) { expandedLongBody.toggle() }
                    } label: {
                        Text(expandedLongBody ? "Show less" : "Show more")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(categoryAccent.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                if responseAppearance.showsOnDevicePrivacyFooter, !isShortReply {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.cyan.opacity(0.75))
                        Text("Processed on-device; not sent to Mangox Cloud for this reply.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(A11yL10n.onDeviceAnswer)
                }

                if showWebSourcesBadge {
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
                    .accessibilityLabel(A11yL10n.webSourcesAnswer)
                }

                if !visibleTags.isEmpty, isMetadataVisible {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visibleTags, id: \.self) { tag in
                                let palette = CoachTagPillPalette.forTag(tag)
                                Text(CoachTagPillFormatting.displayLabel(for: tag))
                                    .mangoxFont(.micro)
                                    .foregroundStyle(palette.foreground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(palette.fill)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(palette.stroke, lineWidth: 1)
                                    )
                                    .accessibilityLabel(CoachTagPillFormatting.displayLabel(for: tag))
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !message.thinkingSteps.isEmpty, isMetadataVisible {
                    Divider()
                        .background(Color.white.opacity(0.08))
                        .padding(.horizontal, 14)
                    CoachThinkingDisclosure(steps: message.thinkingSteps)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if !message.references.isEmpty, isMetadataVisible {
                    CoachCollapsedSourcesSection(
                        references: message.references,
                        isExpanded: $sourcesExpanded,
                        accent: categoryAccent
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let inlineFollowUp, isMetadataVisible {
                    CoachInlineFollowUpSection(
                        model: inlineFollowUp,
                        accent: categoryAccent
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if showsFeedback, let onFeedback, isMetadataVisible {
                    CoachMessageFeedbackRow(score: message.feedbackScore, onSubmit: onFeedback)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(responseAppearance.bubbleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(responseAppearance.bubbleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yL10n.coachReplyFormat(categoryLabel, responseAppearance.label))
        .accessibilityValue(message.content)
        .onAppear { beginMetadataReveal() }
        .onChange(of: message.id) { _, _ in beginMetadataReveal() }
        .contextMenu {
            Button {
                UIPasteboard.general.string = message.content
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private func referenceRow(title: String, snippet: String?) -> some View {
        CoachReferenceRow(title: title, snippet: snippet)
    }

    private func beginMetadataReveal() {
        isMetadataVisible = false
        sourcesExpanded = false

        if (message.category ?? "").lowercased() == "plan_intake" {
            isMetadataVisible = true
            return
        }

        let wantsFeedback = showsFeedback && onFeedback != nil
        let hasMetadata =
            !visibleTags.isEmpty
            || !message.thinkingSteps.isEmpty
            || !message.references.isEmpty
            || inlineFollowUp != nil
            || wantsFeedback
        guard hasMetadata else { return }

        if accessibilityReduceMotion || (isShortReply && wantsFeedback) {
            isMetadataVisible = true
            return
        }

        if isShortReply, wantsFeedback, visibleTags.isEmpty,
            message.thinkingSteps.isEmpty, message.references.isEmpty,
            inlineFollowUp == nil
        {
            isMetadataVisible = true
            return
        }

        // Reveal metadata in one smooth step instead of staged sleeps.
        withAnimation(CoachChatMotionSupport.animation(reduceMotion: false, MangoxMotion.smooth)) {
            isMetadataVisible = true
        }
    }
}

private struct CoachReferenceRow: View {
    let title: String
    let snippet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.22))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.mango.opacity(0.75))
            }
            if let snippet, !snippet.isEmpty {
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

private struct CoachCollapsedSourcesSection: View {
    let references: [ChatReference]
    @Binding var isExpanded: Bool
    let accent: Color

    var body: some View {
        Divider()
            .background(Color.white.opacity(0.1))
            .padding(.horizontal, 14)

        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(MangoxMotion.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.85))
                    Text("Sources (\(references.count))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, isExpanded ? 4 : 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse sources" : "Expand sources")

            if isExpanded {
                ForEach(Array(references.enumerated()), id: \.offset) { _, ref in
                    if let urlStr = ref.url, !urlStr.isEmpty,
                       let url = URL(string: urlStr),
                       let scheme = url.scheme?.lowercased(),
                       scheme == "http" || scheme == "https"
                    {
                        Link(destination: url) {
                            CoachReferenceRow(title: ref.title, snippet: ref.snippet)
                        }
                        .accessibilityHint("Opens in Safari")
                    } else {
                        CoachReferenceRow(title: ref.title, snippet: ref.snippet)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}

private struct CoachInlineFollowUpSection: View {
    let model: CoachInlineFollowUpModel
    let accent: Color

    private var trimmedQuestion: String {
        model.question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        Divider()
            .background(Color.white.opacity(0.08))
            .padding(.horizontal, 14)

        VStack(alignment: .leading, spacing: 8) {
            if !trimmedQuestion.isEmpty {
                Text(trimmedQuestion)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            if !model.actions.isEmpty {
                VStack(spacing: 6) {
                    ForEach(model.actions) { action in
                        inlineChipButton(action)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    private func inlineChipButton(_ action: SuggestedAction) -> some View {
        let navigates = CoachSuggestedActionNavigation.isNavigation(action.type)
        let palette = CoachReplyChipPalette.forAction(action)
        let title = CoachChipPresentation.displayTitle(for: action)
        let isSent = {
            guard model.sentChipKey != nil else { return false }
            return model.sentChipKey == CoachChipSentState.key(messageID: model.messageID, action: action)
        }()
        return CoachTallPromptButton(
            title: isSent ? "Sent · \(title)" : title,
            trailingSystemImage: navigates ? "arrow.right.circle.fill" : "arrow.up.circle.fill",
            trailingTint: navigates ? Color.indigo.opacity(0.92) : palette.trailingOrbTint(isEnabled: model.isEnabled),
            chipPalette: palette,
            isEnabled: model.isEnabled,
            isSent: isSent,
            accessibilityLabelOverride: navigates
                ? "\(title), opens elsewhere"
                : "Suggested reply: \(title)",
            action: { model.onSelect(action) }
        )
    }
}

// MARK: - Feedback

struct CoachMessageFeedbackRow: View {
    let score: Int?
    let onSubmit: (Int) -> Void

    private var thumbsUpSelected: Bool { score == 1 }
    private var thumbsDownSelected: Bool { score == -1 }

    var body: some View {
        HStack(spacing: 10) {
            Text("Helpful?")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))

                Button {
                    HapticManager.shared.coachQuickReplyTapped()
                    onSubmit(1)
                } label: {
                    Image(systemName: thumbsUpSelected ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(thumbsUpSelected ? AppColor.mango : .white.opacity(0.42))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Helpful")

                Button {
                    HapticManager.shared.coachQuickReplyTapped()
                    onSubmit(-1)
                } label: {
                    Image(systemName: thumbsDownSelected ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(thumbsDownSelected ? AppColor.red.opacity(0.9) : .white.opacity(0.42))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Not helpful")
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error

struct CoachErrorBubble: View {
    let text: String
    var failedTier: CoachDeliveryPath?
    let onRetry: () -> Void
    var onRetryCloud: () -> Void = {}
    let bubbleMaxWidth: CGFloat

    private var failedTierLabel: String? {
        switch failedTier {
        case .onDeviceNarrow: "On-device coach"
        case .privateCloudCompute: "Private Cloud"
        case .thirdPartyLanguageModel: "Fallback model"
        case .mangoxCloudBackend: "Coach server"
        case nil: nil
        }
    }

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

            if let failedTierLabel {
                Text("Failed at: \(failedTierLabel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Try again")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .mangoxSurface(
                        .flatCustom(fill: AppColor.red.opacity(0.82), border: AppColor.red.opacity(0.28)),
                        shape: .rounded(MangoxRadius.sharp.rawValue)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Try again")

                Button(action: onRetryCloud) {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Retry on cloud server")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44)
                    .mangoxSurface(
                        .flatCustom(fill: Color.indigo.opacity(0.55), border: Color.indigo.opacity(0.28)),
                        shape: .rounded(MangoxRadius.sharp.rawValue)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry on cloud server")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .mangoxSurface(
            .flatCustom(fill: AppColor.red.opacity(0.1), border: AppColor.red.opacity(0.22)),
            shape: .rounded(MangoxRadius.sharp.rawValue)
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
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
                withAnimation(MangoxMotion.exit) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                    Text("Reasoning")
                        .font(.system(size: 11, weight: .semibold))
                    if steps.count > 1 {
                        Text("\(steps.count) steps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.22))
                    }
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
    var style: CoachResponseAppearance = .cloud

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(style.accent.opacity(0.9))
                .scaleEffect(0.88)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mangoxSurface(
            .flatCustom(fill: style.statusFill, border: style.statusStroke),
            shape: .rounded(MangoxRadius.sharp.rawValue)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(A11yL10n.coachStatusFormat(text))
    }
}

/// Smooth sine-wave typing indicator. Updates every 50 ms but interpolates
/// opacity continuously so the wave feels fluid rather than stepped.
private struct CoachTypingDotsIndicator: View {
    let accent: Color
    var spacing: CGFloat = 5

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Group {
            if accessibilityReduceMotion {
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(accent.opacity(0.72))
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 0.05)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { index in
                            let offset = Double(index) * 0.18
                            let opacity = 0.34 + 0.58 * ((sin((t - offset) * 10.0) + 1.0) / 2.0)
                            Circle()
                                .fill(accent.opacity(opacity))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bubble for the pending assistant turn — same chrome as the final card, hugging its content
/// up to `bubbleMaxWidth` so it matches the committed bubble and never jumps width on finalize.
struct CoachPendingReplyBubble: View {
    let streamingText: String
    var bubbleMaxWidth: CGFloat = .infinity
    var delivery: CoachStreamDelivery = .cloud
    var partialTags: [String] = []
    var isSearchingWeb: Bool = false
    var isThinking: Bool = false
    var statusText: String? = nil
    var routeStatus: String? = nil

    private var responseAppearance: CoachResponseAppearance { delivery.appearance }

    private var headerCategory: String? {
        CoachMessagePresentation.semanticCategory(category: nil, tags: partialTags)
    }

    private var headerIcon: String {
        CoachResponseAppearance.headerIcon(category: headerCategory, appearance: responseAppearance)
    }

    private var headerLabel: String {
        CoachResponseAppearance.headerLabel(category: headerCategory, appearance: responseAppearance)
    }

    private var hasVisibleBody: Bool {
        !streamingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var statusLine: String? {
        if let routeStatus, !routeStatus.isEmpty { return routeStatus }
        if let statusText, !statusText.isEmpty { return statusText }
        if isThinking { return "Thinking…" }
        if isSearchingWeb, !hasVisibleBody { return "Searching the web…" }
        return nil
    }

    private var streamPlainText: String {
        CoachAssistantFormatting.plainTextForStreaming(streamingText)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(responseAppearance.stripGradient)
                .frame(width: 3)
                .padding(.vertical, 12)
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: headerIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(responseAppearance.accent)
                    Text(headerLabel.uppercased())
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.38))
                        .tracking(0.65)
                    Text("·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.22))
                    Text(responseAppearance.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(responseAppearance.accent.opacity(0.72))
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

                if hasVisibleBody {
                    Text(streamPlainText)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.identity)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                } else {
                    HStack(spacing: 8) {
                        if isSearchingWeb {
                            Image(systemName: "globe")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(responseAppearance.accent.opacity(0.88))
                                .accessibilityHidden(true)
                        }
                        CoachTypingDotsIndicator(accent: responseAppearance.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                if let statusLine {
                    Text(statusLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }

                if !partialTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(partialTags, id: \.self) { tag in
                                let palette = CoachTagPillPalette.forTag(tag)
                                Text(CoachTagPillFormatting.displayLabel(for: tag))
                                    .mangoxFont(.micro)
                                    .foregroundStyle(palette.foreground)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(Capsule(style: .continuous).fill(palette.fill))
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(palette.stroke, lineWidth: 1)
                                    )
                            }
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.bottom, 10)
                }
            }
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(responseAppearance.bubbleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(responseAppearance.bubbleStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityValue(streamingText.isEmpty ? (statusLine ?? "") : streamingText)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var accessibilityDescription: String {
        switch delivery {
        case .onDevice:
            hasVisibleBody ? "On-device coach is writing a reply" : "On-device coach is preparing a reply"
        case .pcc, .planIntake:
            hasVisibleBody ? "Private Cloud coach is writing a reply" : "Private Cloud coach is preparing a reply"
        case .webSearch:
            isSearchingWeb ? "Coach is searching the web" : "Web coach is writing a reply"
        case .cloud:
            hasVisibleBody ? "Coach is writing a reply" : "Coach is preparing a reply"
        }
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
    /// Tinted fill + stroke for coach quick-reply chips; starters use `.neutral`.
    var chipPalette: CoachReplyChipPalette = .neutral
    var isEnabled: Bool = true
    var isSent: Bool = false
    /// When nil, a default label is derived from `title`.
    var accessibilityLabelOverride: String? = nil
    let action: () -> Void

    private var titleColor: Color {
        if isSent { return AppColor.mango.opacity(0.95) }
        return isEnabled ? .white.opacity(0.92) : .white.opacity(0.35)
    }

    private var minRowHeight: CGFloat {
        (subtitle == nil || subtitle?.isEmpty == true) ? 52 : 58
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        if isSent {
            shape.fill(AppColor.mango.opacity(0.12))
        } else {
            shape.fill(chipPalette.gradientFill(isEnabled: isEnabled))
        }
    }

    @ViewBuilder
    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                isSent
                    ? AppColor.mango.opacity(0.45)
                    : chipPalette.strokeColor(isEnabled: isEnabled),
                lineWidth: 1
            )
    }

    var body: some View {
        Button {
            guard isEnabled, !isSent else { return }
            HapticManager.shared.coachQuickReplyTapped()
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                if let leadingSystemImage {
                    Image(systemName: isSent ? "checkmark.circle.fill" : leadingSystemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(
                            isSent
                                ? AppColor.mango.opacity(0.95)
                                : chipPalette.leadingIconTint(isEnabled: isEnabled)
                        )
                        .frame(width: 26, alignment: .center)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: (subtitle == nil || subtitle?.isEmpty == true) ? 0 : 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(titleColor)
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

                Image(systemName: isSent ? "checkmark" : trailingSystemImage)
                    .font(.system(size: isSent ? 14 : 20, weight: .semibold))
                    .foregroundStyle(
                        isSent
                            ? AppColor.mango.opacity(0.95)
                            : (isEnabled ? trailingTint : .white.opacity(0.2))
                    )
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minHeight: minRowHeight, alignment: .center)
            .background { rowBackground }
            .overlay { rowBorder }
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!isEnabled || isSent)
        .animation(.snappy, value: isSent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            accessibilityLabelOverride
                ?? [title, subtitle].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityAddTraits(.isButton)
    }
}

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

// MARK: - Multi-block follow-up (stepped carousel, one API send at the end)

/// Presents `followUpBlocks` one card at a time; navigation chips still fire immediately.
private struct CoachFollowUpBlocksCarousel: View {
    let messageId: UUID
    let blocks: [CoachFollowUpBlock]
    let bubbleMaxWidth: CGFloat
    let sourceAppearance: CoachResponseAppearance
    var isEnabled: Bool
    var sentChipKey: String? = nil
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
            if hasSubmitted {
                submittedSummary
            } else if let block = currentBlock {
                CoachPlanIntakeProgressStrip(
                    snapshot: CoachPlanIntakeProgress.Snapshot(
                        step: min(step + 1, blocks.count),
                        total: blocks.count,
                        fieldLabel: CoachPlanIntakeProgress.fieldLabel(forQuestion: block.question)
                    )
                )
                .frame(maxWidth: bubbleMaxWidth, alignment: .leading)

                CoachFollowUpRepliesPanel(
                    followUpQuestion: block.question,
                    actions: block.suggestedActions,
                    bubbleMaxWidth: bubbleMaxWidth,
                    sourceAppearance: sourceAppearance,
                    isEnabled: isEnabled,
                    messageID: messageId,
                    sentChipKey: sentChipKey,
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
                    .foregroundStyle(sourceAppearance.accent.opacity(0.9))
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(sourceAppearance.statusStroke, lineWidth: 1)
        )
    }

    private func handleSelect(question: String, _ action: SuggestedAction) {
        guard isEnabled else { return }
        if CoachSuggestedActionNavigation.isNavigation(action.type) {
            onImmediateAction(action)
            return
        }
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = CoachChipPresentation.outgoingText(for: action)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    var sourceAppearance: CoachResponseAppearance = .cloud
    var isEnabled: Bool = true
    var messageID: UUID? = nil
    var sentChipKey: String? = nil
    let onSelect: (SuggestedAction) -> Void

    private var trimmedQuestion: String {
        followUpQuestion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var hasQuestion: Bool { !trimmedQuestion.isEmpty }
    private var hasActions: Bool { !actions.isEmpty }

    private var asksHeader: String {
        switch sourceAppearance {
        case .onDevice: "ON-DEVICE ASKS"
        case .pcc, .webSearch: "PRIVATE CLOUD ASKS"
        case .planIntake: "PLAN SETUP ASKS"
        default: "COACH ASKS"
        }
    }

    private var pickReplyHeader: String {
        switch sourceAppearance {
        case .onDevice: "PICK AN ON-DEVICE REPLY"
        case .pcc, .webSearch, .planIntake: "PICK A REPLY"
        default: "PICK A REPLY"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasQuestion {
                VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                    HStack(spacing: MangoxSpacing.xs.rawValue) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(MangoxFont.micro.value)
                            .foregroundStyle(sourceAppearance.accent)
                        Text(asksHeader)
                            .mangoxFont(.micro)
                            .tracking(1.2)
                            .foregroundStyle(AppColor.fg3)
                    }

                    Text(trimmedQuestion)
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(AppColor.fg0)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(MangoxSpacing.lg.rawValue)
            }

            if hasQuestion && hasActions {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
            }

            if hasActions {
                VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
                    HStack(spacing: MangoxSpacing.xs.rawValue) {
                        Image(systemName: "hand.tap.fill")
                            .font(MangoxFont.micro.value)
                            .foregroundStyle(sourceAppearance.accent.opacity(0.85))
                        Text(pickReplyHeader)
                            .mangoxFont(.micro)
                            .tracking(1.2)
                            .foregroundStyle(AppColor.fg3)
                    }
                    .padding(.horizontal, MangoxSpacing.lg.rawValue)
                    .padding(.top, MangoxSpacing.lg.rawValue)

                    VStack(spacing: MangoxSpacing.sm.rawValue) {
                        ForEach(actions) { action in
                            suggestedReplyButton(action)
                        }
                    }
                    .padding(.horizontal, MangoxSpacing.md.rawValue)
                    .padding(.bottom, MangoxSpacing.md.rawValue)
                }
            }
        }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .mangoxSurface(
            .flatCustom(fill: AppColor.bg2, border: sourceAppearance.accent.opacity(0.28)),
            shape: .rounded(MangoxRadius.sharp.rawValue)
        )
        .accessibilityElement(children: .contain)
    }

    private func suggestedReplyButton(_ action: SuggestedAction) -> some View {
        let navigates = CoachSuggestedActionNavigation.isNavigation(action.type)
        let palette = CoachReplyChipPalette.forAction(action)
        let title = CoachChipPresentation.displayTitle(for: action)
        let isSent = {
            guard let messageID else { return false }
            return sentChipKey == CoachChipSentState.key(messageID: messageID, action: action)
        }()
        return CoachTallPromptButton(
            title: isSent ? "Sent · \(title)" : title,
            trailingSystemImage: navigates ? "arrow.right.circle.fill" : "arrow.up.circle.fill",
            trailingTint: navigates ? Color.indigo.opacity(0.92) : palette.trailingOrbTint(isEnabled: isEnabled),
            chipPalette: palette,
            isEnabled: isEnabled,
            isSent: isSent,
            accessibilityLabelOverride: navigates
                ? "\(title), opens elsewhere"
                : "Suggested reply: \(title)",
            action: { onSelect(action) }
        )
    }

}
