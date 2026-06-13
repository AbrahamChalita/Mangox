import SwiftData
import PhotosUI
import SwiftUI
import UIKit

enum CoachAuxiliarySheet: String, Identifiable {
    case paywall, plans, workouts
    var id: String { rawValue }
}

private enum CoachChatColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension CoachConversationView: Equatable {
    static func == (lhs: CoachConversationView, rhs: CoachConversationView) -> Bool {
        lhs.navigationPath == rhs.navigationPath
            && lhs.chatSheetPresented == rhs.chatSheetPresented
            && lhs.greetingText == rhs.greetingText
    }
}

/// Primary coach chat surface: streaming replies and plan-builder entry.
/// Avoids a root `GeometryReader` so the system keyboard safe area correctly lifts the transcript.
struct CoachConversationView: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var navigationPath: NavigationPath
    /// When chat is presented from `CoachTabRootView`, toggling this dismisses the cover (e.g. Close, or after opening a plan).
    @Binding var chatSheetPresented: Bool

    @State private var auxiliarySheet: CoachAuxiliarySheet?
    /// Pushed (not `.sheet`) so it isn’t torn down by the paywall/plans `item` sheet or full-screen chat cover.
    @State private var showConversationsList = false
    @State private var chatColumnWidth: CGFloat = 400
    @State private var composerFocusScrollNonce = 0
    @State private var sentChipKey: String?
    @State private var contextBannerDismissed = false

    // MARK: - State Management

    @MainActor
    private func handleChatSheetDismissed() {
        chatSheetPresented = false
    }

    @MainActor
    private func handleConversationsListDismissed() {
        showConversationsList = false
    }

    private static let planBuilderSeed =
        "I want to build a structured training plan for an event. Ask me about my goal, target date, weekly training hours, and experience, then outline next steps."

    private let greetingText: String = {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }()

    private static func bubbleMaxWidth(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        // Geometry/preference can report 0 briefly; a near-zero max width makes LazyVStack relayout wildly.
        let w = max(containerWidth, 64)
        return min(580, max(120, w - horizontalPadding))
    }

    // MARK: - Extracted Components

    @ViewBuilder
    private var coachBackgroundView: some View {
        ZStack {
            AppColor.bg
            OptimizedRadialGradient()
        }
        .ignoresSafeArea()
        .mangoxGridBackground(opacity: 0.35)
    }

    private struct OptimizedRadialGradient: View, Equatable {
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let mangoOpacity = colorScheme == .dark ? 0.08 : 0.07
            let blueOpacity = colorScheme == .dark ? 0.05 : 0.06

            RadialGradient(
                colors: [AppColor.mango.opacity(mangoOpacity), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            .blur(radius: 0.5)

            RadialGradient(
                colors: [Color.blue.opacity(blueOpacity), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
            .blur(radius: 0.5)
        }

        static func == (lhs: OptimizedRadialGradient, rhs: OptimizedRadialGradient) -> Bool {
            lhs.colorScheme == rhs.colorScheme
        }
    }

    // MARK: - Reusable Components

    private struct CoachMetricsStrip: View, Equatable {
        @Environment(CoachViewModel.self) private var coachViewModel
        @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.coachViewModel.isPro == rhs.coachViewModel.isPro }

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    metricCapsule(
                        icon: "bolt.fill", label: "FTP", value: "\(PowerZone.ftp)W",
                        color: AppColor.yellow)
                    metricCapsule(
                        icon: "heart.fill", label: "Max HR", value: "\(HeartRateZone.maxHR)",
                        color: AppColor.heartRate)
                    if !coachViewModel.isPro {
                        if coachViewModel.bypassesDailyLimit {
                            metricCapsule(
                                icon: "person.fill.checkmark",
                                label: "Coach",
                                value: "Staff",
                                color: AppColor.mango.opacity(0.85)
                            )
                        } else {
                            let left = coachViewModel.remainingFreeMessages(isPro: coachViewModel.isPro)
                            metricCapsule(
                                icon: "cloud.fill",
                                label: "Cloud",
                                value: left > 0 ? "\(left) left" : "limit",
                                color: left > 0 ? AppColor.fg2 : AppColor.red
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
            }
        }

        private func metricCapsule(icon: String, label: String, value: String, color: Color)
            -> some View
        {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                Text(label.uppercased())
                    .mangoxFont(.micro)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(0.6)
                Text(value)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
        }
    }

    private struct CoachContextBanner: View, Equatable {
        let currentCount: Int
        let windowSize: Int
        let onStartFresh: () -> Void
        var onDismiss: (() -> Void)? = nil

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.currentCount == rhs.currentCount && lhs.windowSize == rhs.windowSize
        }

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.yellow.opacity(0.9))
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Context \(currentCount)/\(windowSize)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                    Text("Older turns are summarized. Start a new chat for sharper follow-ups.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onStartFresh) {
                        Text("New chat")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppColor.mango)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }

                Spacer(minLength: 0)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(12)
            .mangoxSurface(
                .flatCustom(fill: Color.white.opacity(0.04), border: AppColor.yellow.opacity(0.2)),
                shape: .rounded(MangoxRadius.sharp.rawValue)
            )
        }
    }

    @ViewBuilder
    private var topChromeView: some View {
        ZStack {
            HStack(spacing: 0) {
                Button {
                    chatSheetPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.fg2)
                        .frame(width: 42, height: 42)
                        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yL10n.closeChat)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        showConversationsList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.conversations)

                    Button {
                        coachViewModel.createNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.newConversation)
                    .disabled(coachViewModel.isLoading)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                Text("COACH")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)
                Text(greetingText)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg2)
            }
                .accessibilityAddTraits(.isHeader)
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var metricsStripView: some View {
        CoachMetricsStrip()
    }

    @ViewBuilder
    private var contextBannerView: some View {
        if coachViewModel.suggestsFreshConversation,
            !coachViewModel.isLoading,
            !contextBannerDismissed
        {
            CoachContextWindowBanner(
                currentCount: coachViewModel.currentContextCount,
                windowSize: coachViewModel.contextWindowSize,
                onStartFresh: {
                    coachViewModel.createNewSession()
                    contextBannerDismissed = false
                },
                onDismiss: { contextBannerDismissed = true }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(
                accessibilityReduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .animation(
                accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.24),
                value: coachViewModel.suggestsFreshConversation
            )
        }
    }

    @ViewBuilder
    private var inputBarView: some View {
        CoachInputBarWrapper(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            showComposerLimitBanner: showComposerLimitBanner,
            onPlanBuilder: { send(Self.planBuilderSeed, forcePlanIntake: true) },
            sendAction: { text, image in send(text, image: image) },
            onFocusChanged: { focused in
                if focused && !coachViewModel.messages.isEmpty {
                    composerFocusScrollNonce += 1
                }
            }
        )
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.28),
            value: showComposerLimitBanner
        )
    }

    var body: some View {
        ZStack {
            coachBackgroundView
            VStack(spacing: 0) {
                topChromeView
                metricsStripView
                contextBannerView
                CoachChatTranscriptView(
                    bubbleMaxWidth: Self.bubbleMaxWidth(containerWidth: chatColumnWidth),
                    greetingText: greetingText,
                    bottomSpacerHeight: coachTranscriptBottomSpacerHeight,
                    composerFocusScrollNonce: composerFocusScrollNonce,
                    sentChipKey: sentChipKey,
                    onSend: { send($0) },
                    onPlanBuilder: { send(Self.planBuilderSeed, forcePlanIntake: true) },
                    onPaywall: { auxiliarySheet = .paywall },
                    onSuggestedAction: handleSuggestedAction,
                    onRetry: {
                        HapticManager.shared.coachMessageSent()
                        Task { @MainActor in
                            await coachViewModel.retryLastUserMessage(
                                isPro: coachViewModel.isPro)
                        }
                    },
                    onRetryCloud: {
                        HapticManager.shared.coachMessageSent()
                        Task { @MainActor in
                            await coachViewModel.regenerateLastMessagePreferringCloud(
                                isPro: coachViewModel.isPro)
                        }
                    },
                    onFeedback: { messageID, score in
                        coachViewModel.submitFeedback(for: messageID, score: score)
                    }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CoachChatColumnWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(CoachChatColumnWidthKey.self) { newValue in
                let clampedWidth = max(newValue, 64)
                guard abs(clampedWidth - chatColumnWidth) > 0.5 else { return }
                chatColumnWidth = clampedWidth
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBarView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showConversationsList) {
            CoachSessionsSheet()
        }
        .sheet(item: $auxiliarySheet) { sheet in
            switch sheet {
            case .paywall:
                PaywallView(viewModel: PaywallViewModel(purchasesService: PurchasesManager.shared))
            case .plans:
                CoachPlansSheet(
                    navigationPath: $navigationPath, dismissParentChat: $chatSheetPresented)
            case .workouts:
                CoachWorkoutsSheet(
                    navigationPath: $navigationPath, dismissParentChat: $chatSheetPresented)
            }
        }
        .task {
            OnDeviceCoachEngine.prewarmNarrowCoachIfAvailable()
            OnDeviceCoachEngine.prewarmPCCCoachIfAvailable()
            await coachViewModel.loadPersistedMessagesIfNeeded()
        }
        .task(id: "\(coachViewModel.currentSessionID?.uuidString ?? "none")") {
            await coachViewModel.refreshStarterContentIfNeeded()
        }
        .onChange(of: coachViewModel.isLoading) { _, loading in
            if !loading {
                sentChipKey = nil
            }
        }
        .onChange(of: coachViewModel.error) { _, error in
            if error != nil, !coachViewModel.isLoading {
                sentChipKey = nil
            }
        }
        .onChange(of: coachViewModel.currentSessionID) { _, _ in
            contextBannerDismissed = false
        }
    }

    // MARK: Top chrome

    private var topChrome: some View {
        ZStack {
            HStack(spacing: 0) {
                Button {
                    chatSheetPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColor.fg2)
                        .frame(width: 42, height: 42)
                        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yL10n.closeChat)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button {
                        showConversationsList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.conversations)

                    Button {
                        coachViewModel.createNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 40, height: 40)
                            .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.fg2)
                    .accessibilityLabel(A11yL10n.newConversation)
                    .disabled(coachViewModel.isLoading)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 2) {
                Text("COACH")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.mango)
                    .tracking(1.4)
                Text(greetingText)
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(AppColor.fg2)
            }
                .accessibilityAddTraits(.isHeader)
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
    }

    // MARK: Background

    private var coachBackground: some View {
        ZStack {
            AppColor.bg
            RadialGradient(
                colors: [AppColor.mango.opacity(0.07), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Color.blue.opacity(0.06), Color.clear],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
        .mangoxGridBackground(opacity: 0.35)
    }

    // MARK: Metrics

    private var metricsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                metricCapsule(
                    icon: "bolt.fill", label: "FTP", value: "\(PowerZone.ftp)W",
                    color: AppColor.yellow)
                metricCapsule(
                    icon: "heart.fill", label: "Max HR", value: "\(HeartRateZone.maxHR)",
                    color: AppColor.heartRate)
                if !coachViewModel.isPro {
                    if coachViewModel.bypassesDailyLimit {
                        metricCapsule(
                            icon: "person.fill.checkmark",
                            label: "Coach",
                            value: "Staff",
                            color: AppColor.mango.opacity(0.85)
                        )
                    } else {
                        let left = coachViewModel.remainingFreeMessages(isPro: coachViewModel.isPro)
                        metricCapsule(
                            icon: "cloud.fill",
                            label: "Cloud",
                            value: left > 0 ? "\(left) left" : "limit",
                            color: left > 0 ? AppColor.fg2 : AppColor.red
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)
        }
    }

    private func metricCapsule(icon: String, label: String, value: String, color: Color)
        -> some View
    {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .mangoxFont(.micro)
                .foregroundStyle(AppColor.fg3)
                .tracking(0.6)
            Text(value)
                .font(MangoxFont.caption.value)
                .foregroundStyle(AppColor.fg1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
    }

    // MARK: Context banner (sticky below metrics)

    @ViewBuilder
    private var contextBanner: some View {
        if coachViewModel.suggestsFreshConversation,
            !coachViewModel.isLoading,
            !contextBannerDismissed
        {
            CoachContextWindowBanner(
                currentCount: coachViewModel.currentContextCount,
                windowSize: coachViewModel.contextWindowSize,
                onStartFresh: {
                    coachViewModel.createNewSession()
                    contextBannerDismissed = false
                },
                onDismiss: { contextBannerDismissed = true }
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .transition(
                accessibilityReduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
        }
    }

    // MARK: Input

    private var showComposerLimitBanner: Bool {
        coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro) && !coachViewModel.messages.isEmpty
    }

    private var coachPlanSheetActive: Bool {
        coachViewModel.planConfirmationDraft != nil
            || coachViewModel.planSaveCelebration != nil
            || coachViewModel.workoutConfirmationDraft != nil
            || coachViewModel.workoutSaveCelebration != nil
    }

    /// Extra lift so the last coach bubble clears the plan card; smaller spacer when the inset is tall.
    private var coachTranscriptBottomSpacerHeight: CGFloat {
        if coachPlanSheetActive { return 44 }
        return 28
    }

    // MARK: - Actions

    private func send(_ text: String, forcePlanIntake: Bool = false, image: CoachUserImageAttachment? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil else { return }
        let planIntake = forcePlanIntake || AIService.shouldForcePlanIntake(for: trimmed)
        guard coachViewModel.canSendCoachMessage(
            trimmed,
            isPro: coachViewModel.isPro,
            forcePlanIntake: planIntake,
            hasImage: image != nil
        ) else {
            auxiliarySheet = .paywall
            return
        }
        guard coachViewModel.prepareOutgoingMessage(
            trimmed,
            isPro: coachViewModel.isPro,
            forcePlanIntake: planIntake,
            hasImage: image != nil
        ) else {
            return
        }
        HapticManager.shared.coachMessageSent()
        Task { @MainActor in
            await coachViewModel.sendMessage(
                trimmed,
                isPro: coachViewModel.isPro,
                forcePlanIntake: forcePlanIntake || AIService.shouldForcePlanIntake(for: trimmed),
                image: image
            )
        }
    }

    /// Taps on model-provided `suggestedActions` chips (same JSON contract as the Mangox Cloud coach).
    private func handleSuggestedAction(from messageID: UUID, _ action: SuggestedAction) {
        guard !coachViewModel.isLoading else { return }
        let kind = action.type.lowercased()
        guard coachViewModel.canSendCoachMessage(
            action.label,
            isPro: coachViewModel.isPro,
            forcePlanIntake: AIService.shouldForcePlanIntake(for: action.label)
        ) else {
            auxiliarySheet = .paywall
            return
        }
        HapticManager.shared.coachQuickReplyTapped()
        switch kind {
        case "retry":
            Task { @MainActor in
                await coachViewModel.retryLastUserMessage(isPro: coachViewModel.isPro)
            }
            return
        case "escalate_cloud":
            Task { @MainActor in
                await coachViewModel.regenerateLastMessagePreferringCloud(isPro: coachViewModel.isPro)
            }
            return
        case "navigate_to_plan":
            auxiliarySheet = .plans
        case "navigate_to_my_plans", "open_my_plans":
            auxiliarySheet = .plans
        case "navigate_to_my_workouts", "open_my_workouts":
            auxiliarySheet = .workouts
        case "start_workout":
            guard let celebration = coachViewModel.workoutSaveCelebration else { return }
            navigationPath.append(AppRoute.customWorkoutRide(templateID: celebration.templateID))
            coachViewModel.clearWorkoutSaveCelebration()
            chatSheetPresented = false
        default:
            sentChipKey = CoachChipSentState.key(messageID: messageID, action: action)
            let outgoing = CoachChipPresentation.outgoingText(for: action)
            send(outgoing, forcePlanIntake: AIService.shouldForcePlanIntake(for: outgoing))
        }
    }
}

/// Isolates all per-token stream reads in its own body so token updates re-render
/// only this subtree, never the full transcript.
struct CoachStreamingSection: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    var bubbleMaxWidth: CGFloat = .infinity

    var body: some View {
        if coachViewModel.isLoading {
            CoachPendingReplyBubble(
                streamingText: coachViewModel.streamDraftText,
                bubbleMaxWidth: bubbleMaxWidth,
                delivery: coachViewModel.streamDelivery,
                partialTags: coachViewModel.streamPartialTags,
                isSearchingWeb: coachViewModel.streamIsSearchingWeb,
                isThinking: coachViewModel.streamIsThinking,
                statusText: coachViewModel.streamStatusText,
                routeStatus: coachViewModel.streamRouteStatus
            )
            .id("pending-bubble")
        }
    }
}

struct CoachInputBarWrapper: View {
    @Binding var navigationPath: NavigationPath
    @Binding var chatSheetPresented: Bool
    @Binding var auxiliarySheet: CoachAuxiliarySheet?
    let showComposerLimitBanner: Bool
    let onPlanBuilder: () -> Void
    let sendAction: (String, CoachUserImageAttachment?) -> Void
    let onFocusChanged: (Bool) -> Void

    @Environment(CoachViewModel.self) private var coachViewModel

    @State private var inputText = ""
    @State private var attachedImage: CoachUserImageAttachment?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var hasAttachedPhoto = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        InputBarView(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            inputText: $inputText,
            attachedImage: $attachedImage,
            photoPickerItem: $photoPickerItem,
            hasAttachedPhoto: $hasAttachedPhoto,
            inputFocused: _inputFocused,
            showComposerLimitBanner: showComposerLimitBanner,
            onPlanBuilder: onPlanBuilder,
            sendAction: { text in
                let wasFocused = inputFocused
                let image = attachedImage
                sendAction(text, image)
                inputText = ""
                attachedImage = nil
                photoPickerItem = nil
                hasAttachedPhoto = false
                if wasFocused {
                    inputFocused = true
                }
            }
        )
        // Removed `ToolbarItemGroup(placement: .keyboard)`. The system toolbar adds
        // ~44pt above the keyboard that the ScrollView's safeAreaInset doesn't
        // account for, so the last bubble could hide under it. Send is already
        // inline; long-press on the TextField still surfaces Paste; interactive
        // drag dismisses the keyboard.
        .onChange(of: inputFocused) { _, focused in
            onFocusChanged(focused)
        }
    }
}

struct InputBarView: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var navigationPath: NavigationPath
    @Binding var chatSheetPresented: Bool
    @Binding var auxiliarySheet: CoachAuxiliarySheet?
    @Binding var inputText: String
    @Binding var attachedImage: CoachUserImageAttachment?
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var hasAttachedPhoto: Bool
    @FocusState var inputFocused: Bool
    let showComposerLimitBanner: Bool
    let onPlanBuilder: () -> Void
    let sendAction: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let draft = coachViewModel.planConfirmationDraft {
                CoachPlanConfirmBanner(draft: draft, navigationPath: $navigationPath)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else if let draft = coachViewModel.workoutConfirmationDraft {
                CoachWorkoutConfirmBanner(draft: draft)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else if let celeb = coachViewModel.planSaveCelebration {
                CoachPlanSuccessBanner(
                    celebration: celeb,
                    navigationPath: $navigationPath,
                    dismissChat: { chatSheetPresented = false }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            } else if let celeb = coachViewModel.workoutSaveCelebration {
                CoachWorkoutSuccessBanner(
                    celebration: celeb,
                    navigationPath: $navigationPath,
                    dismissChat: { chatSheetPresented = false }
                )
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            if showComposerLimitBanner {
                Button {
                    auxiliarySheet = .paywall
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Image(systemName: "cloud.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Cloud coach limit reached")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("Upgrade")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(AppColor.mango.opacity(0.95))
                        }
                        Text("On-device stats and Private Cloud still work — cloud web search needs Mangox Cloud.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.42))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(AppColor.mango.opacity(0.92))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColor.mango.opacity(0.08))
                }
                .buttonStyle(.plain)
                .accessibilityHint(A11yL10n.opensSubscriptionHint)
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            if let errorMessage = coachViewModel.error, !errorMessage.isEmpty {
                MangoxErrorBanner(
                    message: errorMessage,
                    severity: .error,
                    layout: .inlineStrip,
                    onDismiss: { coachViewModel.dismissError() }
                )
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            if hasAttachedPhoto {
                HStack(spacing: 10) {
                    if let image = attachedImage?.uiImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Photo attached")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                    Spacer(minLength: 0)
                    Button {
                        attachedImage = nil
                        photoPickerItem = nil
                        hasAttachedPhoto = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove photo")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button(action: onPlanBuilder) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppColor.mango.opacity(0.9))
                        .frame(width: 40, height: 44)
                        .background(AppColor.bg2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(AppColor.mango.opacity(0.28), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(A11yL10n.planBuilder)
                .disabled(coachViewModel.isLoading)

                CoachAttachPhotoPicker(
                    photoPickerItem: $photoPickerItem,
                    attachedImage: $attachedImage,
                    hasAttachedPhoto: $hasAttachedPhoto,
                    isDisabled: coachViewModel.isLoading
                )

                TextField(
                    "Message",
                    text: $inputText,
                    prompt: Text("Message").foregroundColor(AppColor.fg3),
                    axis: .vertical
                )
                .font(.body)
                .foregroundStyle(.white)
                .tint(AppColor.mango)
                .textInputAutocapitalization(.sentences)
                .autocorrectionDisabled(false)
                .keyboardType(.default)
                .textContentType(.none)
                .lineLimit(1...6)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(inputFocused ? AppColor.bg2 : AppColor.bg1)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            inputFocused ? AppColor.mango.opacity(0.35) : AppColor.hair2,
                            lineWidth: 1
                        )
                )
                .focused($inputFocused)
                .submitLabel(.send)
                .accessibilityLabel(A11yL10n.messageInput)
                .onSubmit { sendAction(inputText) }

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AppColor.bg.opacity(0.94))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppColor.hair)
                    .frame(height: 1)
            }
        }
    }

    private var sendButtonHint: String {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !coachViewModel.canSendCoachMessage(
            trimmed,
            isPro: coachViewModel.isPro,
            hasImage: hasAttachedPhoto
        ) {
            return "Cloud coach limit reached. Upgrade for live web search, or keep using on-device stats and Private Cloud."
        }
        if coachViewModel.isLoading {
            return "Coach is replying. Wait for the response to finish."
        }
        if trimmed.isEmpty {
            return "Type a message to enable send."
        }
        return ""
    }

    private var sendButton: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend =
            (!trimmed.isEmpty || hasAttachedPhoto)
            && !coachViewModel.isLoading
            && coachViewModel.canSendCoachMessage(
                trimmed,
                isPro: coachViewModel.isPro,
                hasImage: hasAttachedPhoto
            )

        return Button {
            sendAction(inputText)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canSend ? AppColor.bg0 : AppColor.fg3)
                .frame(width: 44, height: 44)
                .background(canSend ? AppColor.mango : AppColor.bg2)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(canSend ? AppColor.mango.opacity(0.45) : AppColor.hair2, lineWidth: 1)
                )
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!canSend)
        .accessibilityLabel(coachViewModel.isLoading ? "Sending message" : "Send message")
        .accessibilityHintIf(sendButtonHint)
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.22),
            value: canSend
        )
    }
}

private struct CoachPhotoPickerLabel: View {
    let hasAttachedPhoto: Bool

    var body: some View {
        Image(systemName: "photo.on.rectangle")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(AppColor.mango.opacity(hasAttachedPhoto ? 1 : 0.9))
            .frame(width: 40, height: 44)
            .background(AppColor.bg2)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        hasAttachedPhoto
                            ? AppColor.mango.opacity(0.55) : AppColor.mango.opacity(0.28),
                        lineWidth: 1
                    )
            )
    }
}

private struct CoachAttachPhotoPicker: View {
    @Binding var photoPickerItem: PhotosPickerItem?
    @Binding var attachedImage: CoachUserImageAttachment?
    @Binding var hasAttachedPhoto: Bool
    let isDisabled: Bool

    var body: some View {
        let attached = hasAttachedPhoto
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            CoachPhotoPickerLabel(hasAttachedPhoto: attached)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Attach photo")
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                    let uiImage = UIImage(data: data),
                    let attachment = CoachUserImageAttachment.fromUIImage(uiImage)
                else { return }
                await MainActor.run {
                    attachedImage = attachment
                    hasAttachedPhoto = true
                }
            }
        }
    }
}
