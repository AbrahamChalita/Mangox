import SwiftUI
import SwiftData

extension Notification.Name {
    static let scrollToBottom = Notification.Name("scrollToBottom")
}

// MARK: - AIChatView

struct AIChatView: View {
    @Environment(AIService.self) private var aiService
    @Environment(PurchasesManager.self) private var purchases
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputText: String = ""
    @State private var showPaywall = false
    @State private var showGeneratePlan = false
    @State private var showHistory = false
    @FocusState private var inputFocused: Bool
    @State private var scrollBottomDebounceTask: Task<Void, Never>?

    /// Cached once — greeting depends only on launch hour, not every render.
    private let greetingText: String = {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning 👋"
        case 12..<17: return "Good afternoon 👋"
        default:     return "Good evening 👋"
        }
    }()

    private let quickPrompts = [
        "How's my training load?",
        "Analyze my last ride",
        "What should I do today?",
        "Generate a training plan"
    ]

    /// Horizontal padding on the message stack is 16 + 16; cap keeps bubbles readable on iPad.
    private static func chatBubbleMaxWidth(containerWidth: CGFloat) -> CGFloat {
        let horizontalPadding: CGFloat = 32
        return min(560, max(0, containerWidth - horizontalPadding))
    }

    /// Computed once per layout pass — avoids O(n²) `lastIndex` work inside every row.
    private var latestAssistantIndex: Int? {
        aiService.messages.lastIndex { $0.role == .assistant }
    }

    var body: some View {
        GeometryReader { geo in
            let bubbleMaxWidth = Self.chatBubbleMaxWidth(containerWidth: geo.size.width)
            ZStack {
                AppColor.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    contextHeader
                    messagesArea(bubbleMaxWidth: bubbleMaxWidth)
                }
                .safeAreaInset(edge: .bottom) {
                    inputBar.padding(.bottom, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onDisappear {
                scrollBottomDebounceTask?.cancel()
            }
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 6) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.fill")
                            .font(.body)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("Chat history")

                    Button {
                        showGeneratePlan = true
                    } label: {
                        Label("Generate Plan", systemImage: "calendar.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .labelStyle(.titleAndIcon)
                            .frame(minHeight: 44)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(AppColor.mango)

                    Button {
                        aiService.createNewSession(modelContext: modelContext)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityLabel("New conversation")
                }
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showGeneratePlan) { PlanGenerationView() }
        .sheet(isPresented: $showHistory) { ChatHistoryView() }
        .task {
            aiService.loadPersistedMessages(modelContext: modelContext)
        }
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                contextChip(icon: "bolt.fill",    label: "FTP",    value: "\(PowerZone.ftp)W",         color: AppColor.yellow)
                contextChip(icon: "heart.fill",   label: "Max HR", value: "\(HeartRateZone.maxHR) bpm", color: AppColor.heartRate)
                if !purchases.isPro {
                    let remaining = max(0, AIService.freeDailyLimit - aiService.todayMessageCount)
                    contextChip(
                        icon: "bubble.left.fill", label: "Today",
                        value: "\(remaining) left",
                        color: remaining > 0 ? .white.opacity(0.5) : AppColor.red
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.03))
        .overlay(Divider().opacity(0.3), alignment: .bottom)
    }

    private func contextChip(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white.opacity(0.38))
                .tracking(0.6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    // MARK: - Messages Area

    private func messagesArea(bubbleMaxWidth: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if aiService.messages.isEmpty && !aiService.isLoading {
                    emptyState
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(aiService.messages.enumerated()), id: \.element.id) { index, message in
                            ChatMessageRow(
                                message: message,
                                isLatestAssistant: message.role == .assistant
                                    && (latestAssistantIndex.map { $0 == index } ?? false),
                                bubbleMaxWidth: bubbleMaxWidth,
                                onActionTap: { label in sendMessage(label) }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        if aiService.isLoading {
                            TypingIndicatorRow(bubbleMaxWidth: bubbleMaxWidth)
                                .id("typing")
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }

                        Color.clear.frame(height: 1).id("CHAT_BOTTOM")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: aiService.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                }
            }
            .onChange(of: aiService.isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .scrollToBottom)) { _ in
                scrollBottomDebounceTask?.cancel()
                scrollBottomDebounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(45))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("CHAT_BOTTOM", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 20)

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColor.mango.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(AppColor.mango)
                }

                VStack(spacing: 6) {
                    Text(greetingText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Ask about your training, get ride analysis,\nor build a structured plan.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.46))
                        .multilineTextAlignment(.center)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(quickPrompts, id: \.self) { prompt in
                    QuickPromptCard(text: prompt) { sendMessage(prompt) }
                }
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                "Ask your coach...",
                text: $inputText,
                prompt: Text("Ask your coach...").foregroundColor(.white.opacity(0.35)),
                axis: .vertical
            )
            .font(.body)
            .foregroundStyle(.white)
            .tint(AppColor.mango)
            .textInputAutocapitalization(.sentences)
            .lineLimit(1...5)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(inputFocused ? 0.18 : 0.08), lineWidth: 1)
            )
            .focused($inputFocused)
            .submitLabel(.send)
            .onSubmit { sendMessage(inputText) }

            sendButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColor.bg.opacity(0.94))
        .overlay(Divider().opacity(0.25), alignment: .top)
    }

    private var sendButton: some View {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSend = !trimmed.isEmpty
            && !aiService.isLoading
            && !aiService.hasReachedFreeLimit(isPro: purchases.isPro)

        return Button {
            sendMessage(inputText)
        } label: {
            ZStack {
                Circle()
                    .fill(canSend ? AppColor.mango : Color.white.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.3))
            }
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!canSend)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: canSend)
        .accessibilityLabel(aiService.isLoading ? "Sending message" : "Send message")
        .accessibilityHintIf(
            !canSend && aiService.hasReachedFreeLimit(isPro: purchases.isPro),
            "Daily message limit reached. Upgrade to Pro to continue."
        )
    }

    // MARK: - Actions

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""
        Task {
            await aiService.sendMessage(trimmed, isPro: purchases.isPro, modelContext: modelContext)
            try? await Task.sleep(for: .milliseconds(100))
            inputFocused = true
        }
    }
}

// MARK: - ChatMessageRow

struct ChatMessageRow: View {
    @Environment(AIService.self) private var aiService
    let message: ChatMessage
    /// Only the newest assistant message shows chips & follow-up — avoids cluttering history.
    let isLatestAssistant: Bool
    let bubbleMaxWidth: CGFloat
    let onActionTap: (String) -> Void

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if message.role == .user {
                UserBubble(text: message.content, bubbleMaxWidth: bubbleMaxWidth)
            } else {
                if message.category == "error" {
                    ErrorBubble(text: message.content, onRetry: { onActionTap("Try again") }, bubbleMaxWidth: bubbleMaxWidth)
                } else {
                    if isLatestAssistant && !message.thinkingSteps.isEmpty {
                        ThinkingStepsCard(steps: message.thinkingSteps, autoExpand: true, maxWidth: bubbleMaxWidth)
                    }
                    AIBubble(message: message, bubbleMaxWidth: bubbleMaxWidth)
                }

                if isLatestAssistant {
                    if let followUp = message.followUpQuestion, !followUp.isEmpty {
                        AIQuestionLabel(text: followUp, bubbleMaxWidth: bubbleMaxWidth)
                    }
                    if !message.suggestedActions.isEmpty {
                        ActionChipsRow(actions: message.suggestedActions, onTap: onActionTap)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .padding(.vertical, 6)
    }
}

// MARK: - User Bubble

struct UserBubble: View {
    let text: String
    let bubbleMaxWidth: CGFloat

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColor.mango.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppColor.mango.opacity(0.22), lineWidth: 1)
            )
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
            .onLongPressGesture {
                UIPasteboard.general.string = text
            }
    }
}

// MARK: - AI Bubble

struct AIBubble: View {
    @Environment(AIService.self) private var aiService
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let message: ChatMessage
    let bubbleMaxWidth: CGFloat

    @State private var visibleLength: Int = 0
    @State private var animationDone: Bool = false
    @State private var parsedMarkdown: AttributedString?

    private var shouldRunAnimation: Bool {
        message.shouldAnimate && aiService.shouldAnimateMessage(message.id)
    }

    /// Plain text while typewriting avoids expensive markdown parsing on every character.
    private var displayText: AttributedString {
        if animationDone || !shouldRunAnimation {
            if let cached = parsedMarkdown { return cached }
            return parseMarkdown(message.content)
        }
        let prefix = String(message.content.prefix(visibleLength))
        return AttributedString(prefix)
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
        case "plan_analysis": "Plan Analysis"
        case "nutrition": "Nutrition"
        case "recovery": "Recovery"
        case "equipment": "Equipment"
        case "clarification": "Clarification"
        default: "Coach"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category badge row
            HStack(spacing: 4) {
                Image(systemName: categoryIcon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.8))
                Text(categoryLabel)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(0.5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Content
            Text(displayText)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            // Tags pills
            if !message.tags.isEmpty && animationDone {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(message.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.top, 6)
                .padding(.bottom, 8)
            }

            // References
            if !message.references.isEmpty && animationDone {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sources")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(0.5)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

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
                .padding(.bottom, 8)
            }
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
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
        .onLongPressGesture {
            UIPasteboard.general.string = message.content
        }
        .task(id: message.id) {
            guard shouldRunAnimation, !message.content.isEmpty else {
                finishAnimation()
                return
            }
            if accessibilityReduceMotion {
                finishAnimation()
                return
            }
            let count = message.content.count
            let msPerChar = max(3.0, min(18.0, 1800.0 / Double(count)))
            let nsPer = UInt64(msPerChar * 1_000_000)
            visibleLength = 0
            do {
                for i in 0..<count {
                    visibleLength = i + 1
                    if i % 28 == 0 || i == count - 1 {
                        NotificationCenter.default.post(name: .scrollToBottom, object: nil)
                    }
                    try await Task.sleep(nanoseconds: nsPer)
                }
            } catch { /* cancelled — fall through to finishAnimation */ }
            finishAnimation()
            NotificationCenter.default.post(name: .scrollToBottom, object: nil)
        }
    }

    private func referenceRow(title: String, snippet: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.25))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.mango.opacity(0.7))
            }
            if let snippet = snippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func finishAnimation() {
        visibleLength = message.content.count
        parsedMarkdown = parseMarkdown(message.content)
        animationDone = true
        aiService.markAnimated(message.id)
    }

    private func parseMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Error Bubble

struct ErrorBubble: View {
    let text: String
    let onRetry: () -> Void
    let bubbleMaxWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppColor.red.opacity(0.9))
                Text("Connection error")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(AppColor.red.opacity(0.9))
            }

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
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
                .background(AppColor.red.opacity(0.7))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Try again")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [AppColor.red.opacity(0.12), AppColor.red.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppColor.red.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
    }
}

// MARK: - Thinking Steps Card

struct ThinkingStepsCard: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let steps: [String]
    /// Auto-expands for the newest message; collapses for history.
    let autoExpand: Bool
    let maxWidth: CGFloat
    @State private var expanded: Bool

    init(steps: [String], autoExpand: Bool = false, maxWidth: CGFloat = 320) {
        self.steps = steps
        self.autoExpand = autoExpand
        self.maxWidth = maxWidth
        _expanded = State(initialValue: autoExpand)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if accessibilityReduceMotion {
                    expanded.toggle()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        expanded.toggle()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.mango.opacity(0.7))

                    Text("Thinking · \(steps.count) step\(steps.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thinking steps, \(expanded ? "expanded" : "collapsed")")
            .accessibilityHint("Shows how the coach reasoned through your question")

            if expanded {
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                                .frame(width: 14)
                                .padding(.top, 1)

                            Text(step)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: maxWidth)
    }
}

// MARK: - Action Chips Row

struct ActionChipsRow: View {
    let actions: [SuggestedAction]
    let onTap: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(actions) { action in
                    Button { onTap(action.label) } label: {
                        Text(action.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }
                    .buttonStyle(MangoxPressStyle())
                    .accessibilityLabel(action.label)
                    .accessibilityHint("Sends this as your next message")
                }
            }
            .padding(.horizontal, 1) // prevent clip on press scale
        }
    }
}

// MARK: - AI Question Label (non-interactive)
// The model's follow-up question — displayed as a label, not a button.
// Users answer via chips below or by typing freely.

struct AIQuestionLabel: View {
    let text: String
    let bubbleMaxWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle()
                    .fill(AppColor.mango.opacity(0.14))
                    .frame(width: 22, height: 22)
                Text("AI")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(AppColor.mango)
            }
            .padding(.top, 1)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColor.mango.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.13), lineWidth: 1)
        )
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Follow-up question")
        .accessibilityValue(text)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorRow: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    let bubbleMaxWidth: CGFloat
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                if accessibilityReduceMotion {
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 7, height: 7)
                        .scaleEffect(dotScale(for: i))
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.15),
                            value: phase
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            if !accessibilityReduceMotion { phase = 1 }
        }
        .onDisappear { phase = 0 }
        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityLabel("Coach is typing")
    }

    private func dotScale(for index: Int) -> Double {
        phase == 0 ? 0.7 : 1.25
    }
}

// MARK: - Quick Prompt Card

struct QuickPromptCard: View {
    let text: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
        }
        .buttonStyle(MangoxPressStyle())
        .accessibilityLabel(text)
        .accessibilityHint("Sends this question to your coach")
    }
}

// MARK: - Free Message Limit Card

struct FreeMessageLimitCard: View {
    @Binding var showPaywall: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundStyle(AppColor.mango)

            VStack(spacing: 5) {
                Text("Daily limit reached")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Upgrade to Pro for unlimited coaching conversations.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Button { showPaywall = true } label: {
                Text("Upgrade to Pro")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(20)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - View helpers

private extension View {
    @ViewBuilder
    func accessibilityHintIf(_ condition: Bool, _ hint: String) -> some View {
        if condition {
            self.accessibilityHint(hint)
        } else {
            self
        }
    }
}
