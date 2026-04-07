import SwiftData
import SwiftUI

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
    @Environment(AIService.self) private var aiService
    @Environment(PurchasesManager.self) private var purchases
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var navigationPath: NavigationPath
    /// When chat is presented from `CoachTabRootView`, toggling this dismisses the cover (e.g. Close, or after opening a plan).
    @Binding var chatSheetPresented: Bool

    @State private var auxiliarySheet: CoachAuxiliarySheet?
    /// Pushed (not `.sheet`) so it isn’t torn down by the paywall/plans `item` sheet or full-screen chat cover.
    @State private var showConversationsList = false
    @State private var chatColumnWidth: CGFloat = 400
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    /// Recreates `ScrollView` when the thread first appears (empty → messages) so layout/scroll state does not stick blank until a manual scroll.
    @State private var transcriptScrollSession: Int = 0
    @State private var didRequestPersistedLoad = false

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
        aiService.messages.lastIndex { $0.role == .assistant }
    }

    private static func bubbleMaxWidth(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        return min(580, max(0, containerWidth - horizontalPadding))
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
                PaywallView()
            case .plans:
                CoachPlansSheet(
                    navigationPath: $navigationPath, dismissParentChat: $chatSheetPresented)
            }
        }
        .task {
            guard !didRequestPersistedLoad else { return }
            didRequestPersistedLoad = true
            await Task.yield()
            await aiService.loadPersistedMessages(modelContext: modelContext)
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
                }
                .accessibilityLabel("Close chat")

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    Button {
                        showConversationsList = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Conversations")

                    Button {
                        send(Self.planBuilderSeed)
                    } label: {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(AppColor.mango)
                    .accessibilityLabel("Plan builder")
                    .disabled(aiService.isLoading)

                    Button {
                        aiService.createNewSession(modelContext: modelContext)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 44, height: 44)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("New conversation")
                    .disabled(aiService.isLoading)
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
                if !purchases.isPro {
                    if AIService.bypassesDailyCoachMessageLimit {
                        metricCapsule(
                            icon: "person.fill.checkmark",
                            label: "Coach",
                            value: "Staff",
                            color: AppColor.mango.opacity(0.85)
                        )
                    } else {
                        let left = max(0, AIService.freeDailyLimit - aiService.todayMessageCount)
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
            if aiService.messages.isEmpty && !aiService.isLoading {
                emptyState(maxW: maxW)
                    .scrollTargetLayout()
            } else {
                // `VStack` avoids LazyVStack deferring layout until scroll (blank transcript until user drags).
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(aiService.messages.enumerated()), id: \.element.id) {
                        index, message in
                        CoachMessageRow(
                            message: message,
                            isLatestAssistant: message.role == .assistant
                                && (latestAssistantIndex.map { $0 == index } ?? false),
                            bubbleMaxWidth: maxW,
                            suggestionsInteractive: !aiService.isLoading,
                            onRetry: { send("Try again") },
                            onSuggestedAction: handleSuggestedAction,
                            onFollowUpBatchComplete: send
                        )
                    }

                    if aiService.generatingPlan && !aiService.isLoading {
                        CoachStreamStatusRow(
                            text: aiService.planProgress?.message ?? "Building your plan…",
                            bubbleMaxWidth: maxW
                        )
                        .id("planGen")
                    }

                    CoachStreamingSection(
                        maxW: maxW,
                        lastStreamScrollDate: .constant(.distantPast),
                        scheduleScrollToBottom: {
                            withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
                        }
                    )

                    Color.clear
                        .frame(height: coachTranscriptBottomSpacerHeight)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .scrollTargetLayout()
            }
        }
        .id(transcriptScrollSession)
        .defaultScrollAnchor(aiService.messages.isEmpty ? .top : .bottom)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .scrollPosition($scrollPosition)
        .onChange(of: aiService.messages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                transcriptScrollSession += 1
            }
            withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: aiService.isLoading) { _, _ in
            withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: aiService.generatingPlan) { _, g in
            if g {
                withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
            }
        }

        // Plan confirm / success banners live in the bottom safeAreaInset; when they appear the visible
        // transcript shifts up — nudge scroll so the last message + chips stay above the inset (same idea as keyboard).
        .onChange(of: aiService.planConfirmationDraft?.id) { _, _ in
            withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
        }
        .onChange(of: aiService.planSaveCelebration?.planID) { _, _ in
            withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
        }
    }

    private func emptyState(maxW: CGFloat) -> some View {
        let prompts = aiService.contextualQuickPrompts(modelContext: modelContext)

        return VStack(spacing: 0) {
            CoachEmptyStartersPanel(
                bubbleMaxWidth: maxW,
                greetingTitle: greetingText,
                headline: "What should we work on?",
                subhead:
                    "Training, recovery, your last ride, or a full event plan — type below or tap a starter.",
                prompts: prompts,
                onPlanBuilder: { send(Self.planBuilderSeed) },
                onPrompt: { send($0.text) }
            )
            .frame(maxWidth: maxW)

            if aiService.hasReachedFreeLimit(isPro: purchases.isPro) {
                dailyLimitCard
                    .padding(.top, 22)
            }

            Color.clear.frame(height: 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 28)
        .padding(.bottom, 16)
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
        aiService.hasReachedFreeLimit(isPro: purchases.isPro) && !aiService.messages.isEmpty
    }

    private var coachPlanSheetActive: Bool {
        aiService.planConfirmationDraft != nil || aiService.planSaveCelebration != nil
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
            sendAction: send,
            onFocusChanged: { focused in
                if focused && !aiService.messages.isEmpty {
                    withAnimation(.snappy) { scrollPosition.scrollTo(edge: .bottom) }
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
        HapticManager.shared.coachMessageSent()
        Task { @MainActor in
            await aiService.sendMessage(trimmed, isPro: purchases.isPro, modelContext: modelContext)
        }
    }

    /// Taps on model-provided `suggestedActions` chips (same JSON contract as the Mangox Cloud coach).
    private func handleSuggestedAction(_ action: SuggestedAction) {
        guard !aiService.isLoading else { return }
        guard !aiService.hasReachedFreeLimit(isPro: purchases.isPro) else {
            auxiliarySheet = .paywall
            return
        }
        HapticManager.shared.coachQuickReplyTapped()
        let kind = action.type.lowercased()
        switch kind {
        case "navigate_to_plan":
            navigationPath.append(AppRoute.trainingPlan)
        case "navigate_to_my_plans", "open_my_plans":
            auxiliarySheet = .plans
        default:
            send(action.label)
        }
    }
}

struct CoachStreamingSection: View {
    @Environment(AIService.self) private var aiService
    let maxW: CGFloat
    @Binding var lastStreamScrollDate: Date
    let scheduleScrollToBottom: () -> Void

    var body: some View {
        if aiService.isLoading {
            Group {
                if !aiService.streamDraftText.isEmpty {
                    CoachStreamingBubble(
                        text: aiService.streamDraftText,
                        bubbleMaxWidth: maxW
                    )
                    .id("streaming")
                } else if aiService.streamIsThinking {
                    CoachStreamStatusRow(text: "Reasoning…", bubbleMaxWidth: maxW)
                        .id("thinking")
                } else if let status = aiService.streamStatusText, !status.isEmpty {
                    CoachStreamStatusRow(text: status, bubbleMaxWidth: maxW)
                        .id("status")
                } else {
                    CoachTypingRow(bubbleMaxWidth: maxW)
                        .id("typing")
                }
            }
            .onChange(of: aiService.streamDraftText) { _, _ in
                guard aiService.isLoading, !aiService.streamDraftText.isEmpty else { return }
                let now = Date()
                guard now.timeIntervalSince(lastStreamScrollDate) >= 0.22 else { return }
                lastStreamScrollDate = now
                scheduleScrollToBottom()
            }
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

    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

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
                Spacer()
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
    @Environment(AIService.self) private var aiService
    @Environment(PurchasesManager.self) private var purchases
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
            if let draft = aiService.planConfirmationDraft {
                CoachPlanConfirmBanner(draft: draft, navigationPath: $navigationPath)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
            } else if let celeb = aiService.planSaveCelebration {
                CoachPlanSuccessBanner(
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
                    .autocorrectionDisabled()
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
            && !aiService.isLoading
            && !aiService.hasReachedFreeLimit(isPro: purchases.isPro)

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
        .accessibilityLabel(aiService.isLoading ? "Sending message" : "Send message")
        .accessibilityHintIf(
            !canSend && aiService.hasReachedFreeLimit(isPro: purchases.isPro)
                ? "Daily message limit reached. Upgrade to Pro to continue."
                : ""
        )
        .animation(
            accessibilityReduceMotion ? .easeInOut(duration: 0.12) : .smooth(duration: 0.22),
            value: canSend
        )
    }
}
