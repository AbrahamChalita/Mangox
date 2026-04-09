import SwiftUI
import SwiftData

/// Destructive / irreversible coach plan actions — confirmed with the same full-screen card chrome as ride discard / end workout.
private enum CoachPlansDestructiveAction: Identifiable, Equatable {
    case deleteAIPlan(id: String)
    case resetAIProgress(id: String)
    case resetBuiltinProgress

    var id: String {
        switch self {
        case .deleteAIPlan(let id): return "delete-\(id)"
        case .resetAIProgress(let id): return "reset-\(id)"
        case .resetBuiltinProgress: return "reset-builtin"
        }
    }
}

/// Shared plans list for the Coach hub and the "My plans" sheet from chat.
struct CoachPlansPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AIService.self) private var aiService
    @Binding var navigationPath: NavigationPath
    /// When set (chat opened as a sheet), navigating to a plan dismisses that chat sheet so the tab stack can show the plan.
    var dismissParentChat: Binding<Bool>? = nil
    var showsIntroCopy: Bool = true
    /// Called when the empty-state "Build a plan" CTA is tapped (hub passes `showChat = true`).
    var onOpenChat: (() -> Void)? = nil

    private static let planProgressDescriptor: FetchDescriptor<TrainingPlanProgress> = {
        var d = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    private static let aiPlansDescriptor: FetchDescriptor<AIGeneratedPlan> = {
        var d = FetchDescriptor<AIGeneratedPlan>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)])
        d.fetchLimit = 256
        return d
    }()

    @Query(Self.planProgressDescriptor) private var allPlanProgress: [TrainingPlanProgress]

    @Query(Self.aiPlansDescriptor) private var aiPlans: [AIGeneratedPlan]

    @State private var destructiveAction: CoachPlansDestructiveAction?
    @State private var showRegenerateInputsMissing = false

    private var builtinPlanID: String { CachedPlan.shared.id }

    private var builtinProgress: TrainingPlanProgress? {
        allPlanProgress.first { $0.planID == builtinPlanID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsIntroCopy {
                Text("Open a plan to follow structured workouts. New AI plans appear here after you generate them in chat.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            sectionHeader("Your plans")
            standardPlanCard(plan: CachedPlan.shared, originalAIPlan: nil)
            
            ForEach(aiPlans) { aiPlan in
                standardPlanCard(plan: aiPlan.plan, originalAIPlan: aiPlan)
            }
        }
        .padding(.bottom, 16)
        .fullScreenCover(item: $destructiveAction) { action in
            destructiveActionCover(for: action)
                .presentationBackground(.clear)
        }
        .alert("Can't regenerate", isPresented: $showRegenerateInputsMissing) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This plan was created before saved inputs were available. Start a new plan from chat instead.")
        }
    }

    private func dismissParentChatIfNeeded() {
        dismissParentChat?.wrappedValue = false
    }

    // MARK: - Destructive confirm

    private func destructiveActionCover(for action: CoachPlansDestructiveAction) -> some View {
        switch action {
        case .deleteAIPlan(let id):
            destructiveActionChrome(
                title: "Delete this plan?",
                message: "Permanently deletes the plan and its progress. This can't be undone.",
                confirmTitle: "Delete plan",
                confirmIsRed: true,
                onConfirm: { deleteAIPlan(id: id) }
            )
        case .resetAIProgress(let id):
            destructiveActionChrome(
                title: "Reset plan progress?",
                message: "Clears completed and skipped workouts for this plan.",
                confirmTitle: "Reset progress",
                confirmIsRed: false,
                onConfirm: { resetAIPlanProgress(planID: id) }
            )
        case .resetBuiltinProgress:
            destructiveActionChrome(
                title: "Reset built-in plan progress?",
                message: "Clears completions and dates; the template stays in Mangox.",
                confirmTitle: "Reset progress",
                confirmIsRed: false,
                onConfirm: { resetBuiltinProgress() }
            )

        }
    }

    private func destructiveActionChrome(
        title: String,
        message: String,
        confirmTitle: String,
        confirmIsRed: Bool,
        onConfirm: @escaping () -> Void
    ) -> some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { destructiveAction = nil }

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        destructiveAction = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        destructiveAction = nil
                        onConfirm()
                    } label: {
                        Text(confirmTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(confirmIsRed ? .white : AppColor.bg)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(confirmIsRed ? AppColor.red.opacity(0.95) : AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Empty State

    private var plansEmptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "map")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.white.opacity(0.18))

                Text("No plans yet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))

                Text("Ask your coach to build a structured training plan — tailored to your goals, target event, and weekly hours.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }

            if let onOpenChat {
                Button(action: onOpenChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Build a plan")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(AppColor.bg)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(AppColor.mango)
                    .clipShape(Capsule())
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            .tracking(1.0)
    }

    // MARK: - AI Plan Card

    private func standardPlanCard(plan: TrainingPlan?, originalAIPlan: AIGeneratedPlan?) -> some View {
        guard let resolvedPlan = plan else { return AnyView(EmptyView()) }
        let planID = originalAIPlan?.id ?? resolvedPlan.id
        let progress = allPlanProgress.first { $0.planID == planID }

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                planCardGlyph(systemName: "figure.outdoor.cycle", color: originalAIPlan == nil ? AppColor.yellow : AppColor.mango)

                VStack(alignment: .leading, spacing: 4) {
                    Text(resolvedPlan.name)
                        .font(.headline)
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)

                    if !resolvedPlan.eventDate.isEmpty || !resolvedPlan.eventName.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                            Text(
                                resolvedPlan.eventName.isEmpty
                                    ? resolvedPlan.eventDate
                                    : (resolvedPlan.eventDate.isEmpty ? resolvedPlan.eventName : "\(resolvedPlan.eventName) · \(resolvedPlan.eventDate)")
                            )
                            .font(.caption)
                            .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                            .lineLimit(2)
                        }
                    }

                    if let aip = originalAIPlan {
                        Text("Updated \(aip.generatedAt.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                    } else {
                        Text("Curated Evidence-Based Plan")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                    }
                }

                Spacer(minLength: 6)

                Menu {
                    if let aip = originalAIPlan {
                        Button {
                            if let data = aip.regenerationInputsJSON,
                               let inputs = try? JSONDecoder().decode(PlanInputs.self, from: data) {
                                aiService.planConfirmationDraft = PlanGenerationDraft(
                                    inputs: inputs,
                                    summaryLine: aip.userPrompt
                                )
                            } else {
                                showRegenerateInputsMissing = true
                            }
                        } label: {
                            Label("Regenerate similar", systemImage: "arrow.triangle.2.circlepath")
                        }
                        Button {
                            destructiveAction = .resetAIProgress(id: aip.id)
                        } label: {
                            Label("Reset Progress", systemImage: "arrow.counterclockwise")
                        }
                        Button(role: .destructive) {
                            destructiveAction = .deleteAIPlan(id: aip.id)
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    } else {
                        if progress != nil {
                            Button {
                                destructiveAction = .resetBuiltinProgress
                            } label: {
                                Label("Reset Progress", systemImage: "arrow.counterclockwise")
                            }
                        }

                    }
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                }
            }

            HStack(spacing: 6) {
                planStatPill(icon: "calendar", text: "\(resolvedPlan.totalWeeks) wks")
                if !resolvedPlan.distance.isEmpty {
                    planStatPill(icon: "map.fill", text: resolvedPlan.distance)
                }
                if let p = progress, p.completedCount > 0 {
                    planStatPill(icon: "checkmark.circle.fill", text: "\(p.completedCount) done")
                }
            }

            if let p = progress, p.completedCount > 0 {
                let totalWorkouts = resolvedPlan.allDays
                    .filter { $0.dayType == .workout || $0.dayType == .ftpTest }.count
                let pct = totalWorkouts > 0 ? Double(p.completedCount) / Double(totalWorkouts) : 0
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Progress")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                            .tracking(0.6)
                        Spacer()
                        Text("\(Int((pct * 100).rounded()))%")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.mango.opacity(0.9))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 6)
                            Capsule()
                                .fill(AppColor.mango)
                                .frame(width: max(6, geo.size.width * pct), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }

            Button {
                if originalAIPlan != nil {
                    navigationPath.append(AppRoute.aiPlan(planID: planID))
                } else {
                    navigationPath.append(AppRoute.trainingPlan)
                }
                dismissParentChatIfNeeded()
            } label: {
                HStack(spacing: 8) {
                    Text((progress?.completedCount ?? 0) > 0 ? "Resume training" : "Open plan")
                        .font(.system(size: 15, weight: .bold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(originalAIPlan == nil ? AppColor.yellow : AppColor.mango)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(16)
        .cardStyle(cornerRadius: 14))
    }

    // MARK: - Card Helpers

    private func planCardGlyph(systemName: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 46, height: 46)
            Image(systemName: systemName)
                .font(.title3)
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }

    private func statusOrb(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func planStatPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(AppOpacity.pillBg))
        .clipShape(Capsule())
    }

    // MARK: - Data Actions

    private func resetBuiltinProgress() {
        guard let p = builtinProgress else { return }
        modelContext.delete(p)
        try? modelContext.save()
    }



    private func resetAIPlanProgress(planID: String) {
        guard let p = allPlanProgress.first(where: { $0.planID == planID }) else { return }
        p.completedDayIDs = []
        p.skippedDayIDs = []
        try? modelContext.save()
    }

    private func deleteAIPlan(id: String) {
        if let aiPlan = aiPlans.first(where: { $0.id == id }) {
            if let progress = allPlanProgress.first(where: { $0.planID == id }) {
                modelContext.delete(progress)
            }
            modelContext.delete(aiPlan)
            try? modelContext.save()
        }
    }
}
