import SwiftData
import SwiftUI
import UIKit

enum CoachAuxiliarySheet: String, Identifiable {
    case paywall, plans
    var id: String { rawValue }
}

private enum CoachChatColumnWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 400
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var scrollPosition = ScrollPosition()
    @State private var shouldAutoScrollToBottom = true
    /// Recreates `ScrollView` when the thread first appears (empty → messages) so layout/scroll state does not stick blank until a manual scroll.
    @State private var transcriptScrollSession: Int = 0

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

    private var latestAssistantIndex: Int? {
        coachViewModel.messages.lastIndex { $0.role == .assistant }
    }

    private static func bubbleMaxWidth(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        // Geometry/preference can report 0 briefly; a near-zero max width makes LazyVStack relayout wildly.
        let w = max(containerWidth, 64)
        return min(580, max(120, w - horizontalPadding))
    }

    private var transcriptContentAlignment: Alignment {
        coachViewModel.messages.isEmpty && !coachViewModel.isLoading ? .center : .bottom
    }

    private var startersLoading: Bool {
        coachViewModel.messages.isEmpty
            && !coachViewModel.isLoading
            && coachViewModel.starterContent == nil
    }

    var body: some View {
        ZStack {
            coachBackground
            VStack(spacing: 0) {
                topChrome
                metricsStrip
                messageScroll(maxW: Self.bubbleMaxWidth(containerWidth: chatColumnWidth))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: CoachChatColumnWidthKey.self, value: proxy.size.width)
                }
            }
            .onPreferenceChange(CoachChatColumnWidthKey.self) { chatColumnWidth = $0 }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
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
            }
        }
        .task {
            await coachViewModel.loadPersistedMessagesIfNeeded()
        }
        .task(id: "\(coachViewModel.currentSessionID?.uuidString ?? "none")") {
            await coachViewModel.refreshStarterContentIfNeeded()
        }
    }

    // MARK: Top chrome

    private var topChrome: some View {
        ZStack {
            HStack(spacing: 0) {
                Button {
                    chatSheetPresented = false
                } label: {
                    Text("Close")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close chat")

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    Button {
                        showConversationsList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Conversations")

                    Button {
                        send(Self.planBuilderSeed)
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.mango)
                    .accessibilityLabel("Plan builder")
                    .disabled(coachViewModel.isLoading)

                    Button {
                        coachViewModel.createNewSession()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("New conversation")
                    .disabled(coachViewModel.isLoading)
                }
            }
            .padding(.horizontal, 8)

            Text("Coach")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityAddTraits(.isHeader)
                .allowsHitTesting(false)
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.12)
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
                            icon: "bubble.left.fill",
                            label: "Today",
                            value: "\(left) left",
                            color: left > 0 ? .white.opacity(0.45) : AppColor.red
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .bottom) {
            Divider().opacity(0.15)
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
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.32))
                .tracking(0.6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Messages

    private func messageScroll(maxW: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if coachViewModel.messages.isEmpty && !coachViewModel.isLoading {
                    emptyState(maxW: maxW)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scrollTargetLayout()
                } else {
                    // `VStack` avoids LazyVStack deferring layout until scroll (blank transcript until user drags).
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(coachViewModel.messages.enumerated()), id: \.element.id) {
                            index, message in
                            CoachMessageRow(
                                message: message,
                                isLatestAssistant: message.role == .assistant
                                    && (latestAssistantIndex.map { $0 == index } ?? false),
                                bubbleMaxWidth: maxW,
                                suggestionsInteractive: !coachViewModel.isLoading,
                                onRetry: { send("Try again") },
                                onSuggestedAction: handleSuggestedAction,
                                onFollowUpBatchComplete: { send($0) }
                            )
                        }

                        if coachViewModel.generatingPlan && !coachViewModel.isLoading {
                            CoachStreamStatusRow(
                                text: coachViewModel.planProgress?.message ?? "Building your plan…",
                                style: .cloud
                            )
                            .id("planGen")
                        }

                        CoachStreamingSection()

                        Color.clear
                            .frame(height: coachTranscriptBottomSpacerHeight)
                    }
                    // `LazyVStack` otherwise shrink-wraps to the widest bubble; user rows stay `.trailing` inside
                    // that narrow width, leaving a dead band on the right (your screenshot).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .scrollTargetLayout()
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: max(transcriptViewportHeight, 0),
                alignment: transcriptContentAlignment
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { transcriptViewportHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in
                        transcriptViewportHeight = newValue
                    }
            }
        }
        .id(transcriptScrollSession)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .simultaneousGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    shouldAutoScrollToBottom = false
                }
        )
        .onAppear {
            if !coachViewModel.messages.isEmpty || coachViewModel.isLoading {
                scrollTranscriptToBottom(animated: false)
            }
        }
        .onChange(of: coachViewModel.messages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                transcriptScrollSession += 1
            }
            scrollTranscriptToBottom()
        }
        .onChange(of: coachViewModel.isLoading) { _, _ in
            scrollTranscriptToBottom()
        }
        .onChange(of: coachViewModel.generatingPlan) { _, g in
            if g {
                scrollTranscriptToBottom()
            }
        }

        // Plan confirm / success banners live in the bottom safeAreaInset; when they appear the visible
        // transcript shifts up — nudge scroll so the last message + chips stay above the inset (same idea as keyboard).
        .onChange(of: coachViewModel.planConfirmationDraft?.id) { _, _ in
            scrollTranscriptToBottom()
        }
        .onChange(of: coachViewModel.planSaveCelebration?.planID) { _, _ in
            scrollTranscriptToBottom()
        }
        .onChange(of: coachViewModel.workoutConfirmationDraft?.id) { _, _ in
            scrollTranscriptToBottom()
        }
        .onChange(of: coachViewModel.workoutSaveCelebration?.id) { _, _ in
            scrollTranscriptToBottom()
        }
    }

    @ViewBuilder
    private func emptyState(maxW: CGFloat) -> some View {
        if startersLoading {
            starterLoadingState(maxW: maxW)
        } else {
            let content =
                coachViewModel.starterContent
                ?? CoachEmptyStartersContent(
                    prompts: coachViewModel.contextualQuickPrompts(),
                    topicTags: []
                )

            VStack(spacing: 0) {
                CoachEmptyStartersPanel(
                    bubbleMaxWidth: maxW,
                    greetingTitle: greetingText,
                    headline: "What should we work on?",
                    subhead:
                        "Ask about training, recovery, or build a plan. Starters only appear when Mangox has data to support them.",
                    topicTags: content.topicTags,
                    prompts: content.prompts,
                    onPlanBuilder: { send(Self.planBuilderSeed) },
                    onPrompt: { send($0.text) }
                )
                .frame(maxWidth: maxW)

                if coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro) {
                    dailyLimitCard
                        .padding(.top, 22)
                }

                Color.clear.frame(height: 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 28)
            .padding(.bottom, 16)
        }
    }

    private func starterLoadingState(maxW: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppColor.mango)
                Text("Preparing grounded starters…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 52)
            }
        }
        .frame(maxWidth: maxW, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private var dailyLimitCard: some View {
        VStack(spacing: 12) {
            Text("Daily limit reached")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("Pro unlocks unlimited coach messages.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
            Button {
                auxiliarySheet = .paywall
            } label: {
                Text("Upgrade")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.2), lineWidth: 1)
        )
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
        coachPlanSheetActive ? 12 : 28
    }

    private var inputBar: some View {
        CoachInputBarWrapper(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            showComposerLimitBanner: showComposerLimitBanner,
            sendAction: { send($0) },
            onFocusChanged: { focused in
                if focused && !coachViewModel.messages.isEmpty {
                    shouldAutoScrollToBottom = true
                    scrollTranscriptToBottom()
                }
            }
        )
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.16) : .smooth(duration: 0.32),
            value: showComposerLimitBanner
        )
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shouldAutoScrollToBottom = true
        HapticManager.shared.coachMessageSent()
        Task { @MainActor in
            await coachViewModel.sendMessage(trimmed, isPro: coachViewModel.isPro)
        }
    }

    private func scrollTranscriptToBottom(animated: Bool = true) {
        guard shouldAutoScrollToBottom else { return }
        let action = {
            scrollPosition.scrollTo(edge: .bottom)
        }
        if animated {
            withAnimation(.snappy, action)
        } else {
            action()
        }
    }

    /// Taps on model-provided `suggestedActions` chips (same JSON contract as the Mangox Cloud coach).
    private func handleSuggestedAction(_ action: SuggestedAction) {
        guard !coachViewModel.isLoading else { return }
        let kind = action.type.lowercased()
        guard !coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro) else {
            auxiliarySheet = .paywall
            return
        }
        HapticManager.shared.coachQuickReplyTapped()
        switch kind {
        case "navigate_to_plan":
            auxiliarySheet = .plans
        case "navigate_to_my_plans", "open_my_plans":
            auxiliarySheet = .plans
        case "start_workout":
            guard let celebration = coachViewModel.workoutSaveCelebration else { return }
            navigationPath.append(AppRoute.customWorkoutRide(templateID: celebration.templateID))
            coachViewModel.clearWorkoutSaveCelebration()
            chatSheetPresented = false
        default:
            send(CoachChipPresentation.outgoingText(for: action))
        }
    }
}

struct CoachStreamingSection: View {
    @Environment(CoachViewModel.self) private var coachViewModel

    var body: some View {
        if coachViewModel.isLoading {
            Group {
                if !coachViewModel.streamDraftText.isEmpty {
                    CoachStreamingBubble(
                        text: coachViewModel.streamDraftText,
                        style: .cloud
                    )
                    .id("streaming")
                } else if coachViewModel.streamIsThinking {
                    CoachStreamStatusRow(
                        text: "Reasoning…",
                        style: .cloud
                    )
                    .id("thinking")
                } else if let status = coachViewModel.streamStatusText, !status.isEmpty {
                    CoachStreamStatusRow(
                        text: status,
                        style: .cloud
                    )
                        .id("status")
                } else {
                    CoachTypingRow(style: .cloud)
                        .id("typing")
                }
            }
            // Same contract as `CoachMessageRow`: occupy the row width, keep stream/typing rows leading-aligned.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CoachInputBarWrapper: View {
    @Binding var navigationPath: NavigationPath
    @Binding var chatSheetPresented: Bool
    @Binding var auxiliarySheet: CoachAuxiliarySheet?
    let showComposerLimitBanner: Bool
    let sendAction: (String) -> Void
    let onFocusChanged: (Bool) -> Void

    @Environment(CoachViewModel.self) private var coachViewModel

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    private var canSendFromKeyboard: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !coachViewModel.isLoading
            && !coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro)
    }

    var body: some View {
        InputBarView(
            navigationPath: $navigationPath,
            chatSheetPresented: $chatSheetPresented,
            auxiliarySheet: $auxiliarySheet,
            inputText: $inputText,
            inputFocused: _inputFocused,
            showComposerLimitBanner: showComposerLimitBanner,
            sendAction: { text in
                sendAction(text)
                inputText = ""
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    inputFocused = true
                }
            }
        )
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Button {
                    if let s = UIPasteboard.general.string {
                        inputText += s
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .accessibilityLabel("Paste from clipboard")

                Spacer()

                Button("Send") {
                    guard canSendFromKeyboard else { return }
                    let t = inputText
                    sendAction(t)
                    inputText = ""
                }
                .font(.system(size: 17, weight: .semibold))
                .disabled(!canSendFromKeyboard)
                .accessibilityLabel("Send message")

                Button("Done") { inputFocused = false }
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityLabel("Dismiss keyboard")
            }
        }
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
    @FocusState var inputFocused: Bool
    let showComposerLimitBanner: Bool
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
                    HStack {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                        Text("Daily limit — tap to upgrade")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(AppColor.mango)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColor.mango.opacity(0.1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens subscription options.")
                .transition(
                    accessibilityReduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }

            GlassEffectContainer(spacing: 12) {
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(
                        "Message",
                        text: $inputText,
                        prompt: Text("Message").foregroundColor(.white.opacity(0.35)),
                        axis: .vertical
                    )
                    .font(.body)
                    .foregroundStyle(.white)
                    .tint(AppColor.mango)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(1...6)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(inputFocused ? 0.11 : 0.065))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                Color.white.opacity(inputFocused ? 0.22 : 0.08), lineWidth: 1)
                    )
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .accessibilityLabel("Message")
                    .onSubmit { sendAction(inputText) }

                    sendButton
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(AppColor.bg.opacity(0.94))
            .overlay(alignment: .top) { Divider().opacity(0.18) }
        }
    }

    private var sendButton: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend =
            !trimmed.isEmpty
            && !coachViewModel.isLoading
            && !coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro)

        return Button {
            sendAction(inputText)
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canSend ? .black : .white.opacity(0.35))
                .frame(width: 44, height: 44)
                .glassEffect(
                    canSend ? .regular.tint(AppColor.mango).interactive() : .regular.interactive(),
                    in: .circle
                )
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!canSend)
        .accessibilityLabel(coachViewModel.isLoading ? "Sending message" : "Send message")
        .accessibilityHintIf(
            !canSend && coachViewModel.hasReachedFreeLimit(isPro: coachViewModel.isPro)
                ? "Daily message limit reached. Upgrade to Pro to continue."
                : ""
        )
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.22),
            value: canSend
        )
    }
}
