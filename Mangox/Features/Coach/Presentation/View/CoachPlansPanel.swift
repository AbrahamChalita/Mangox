import SwiftUI
import SwiftData

/// Destructive / irreversible coach plan actions — confirmed with the same full-screen card chrome as ride discard / end workout.
private enum CoachPlansDestructiveAction: Identifiable, Equatable {
    case deleteAIPlan(id: String)
    case resetAIProgress(id: String)

    var id: String {
        switch self {
        case .deleteAIPlan(let id): return "delete-\(id)"
        case .resetAIProgress(let id): return "reset-\(id)"
        }
    }
}

/// Shared plans list for the Coach hub and the "My plans" sheet from chat.
struct CoachPlansPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachViewModel.self) private var coachViewModel
    @Binding var navigationPath: NavigationPath
    /// When set (chat opened as a sheet), navigating to a plan dismisses that chat sheet so the tab stack can show the plan.
    var dismissParentChat: Binding<Bool>? = nil
    var showsIntroCopy: Bool = true
    var showsSectionHeader: Bool = true
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsIntroCopy {
                Text("New AI plans appear here after you generate them in chat.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsSectionHeader {
                sectionHeader("Your plans")
            }
            if aiPlans.isEmpty {
                plansEmptyState
            } else {
                ForEach(aiPlans) { aiPlan in
                    standardPlanCard(plan: aiPlan.plan, originalAIPlan: aiPlan)
                }
            }
        }
        .padding(.bottom, 16)
        .overlay {
            if let action = destructiveAction {
                destructiveConfirmationOverlay(for: action)
                    .zIndex(300)
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: destructiveAction)
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

    @ViewBuilder
    private func destructiveConfirmationOverlay(for action: CoachPlansDestructiveAction) -> some View {
        switch action {
        case .deleteAIPlan(let id):
            MangoxConfirmOverlay(
                title: "Delete this plan?",
                message: "Permanently deletes the plan and its progress. This can't be undone.",
                onDismiss: { destructiveAction = nil }
            ) {
                MangoxConfirmDualButtonRow(
                    cancelTitle: "Cancel",
                    confirmTitle: "Delete plan",
                    trailingStyle: .destructive,
                    onCancel: { destructiveAction = nil },
                    onConfirm: {
                        destructiveAction = nil
                        deleteAIPlan(id: id)
                    }
                )
            }
        case .resetAIProgress(let id):
            MangoxConfirmOverlay(
                title: "Reset plan progress?",
                message: "Clears completed and skipped workouts for this plan.",
                onDismiss: { destructiveAction = nil }
            ) {
                MangoxConfirmDualButtonRow(
                    cancelTitle: "Cancel",
                    confirmTitle: "Reset progress",
                    trailingStyle: .hero,
                    onCancel: { destructiveAction = nil },
                    onConfirm: {
                        destructiveAction = nil
                        resetAIPlanProgress(planID: id)
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var plansEmptyState: some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.lg.rawValue) {
            VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                Text("Plan library")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.4)
                    .textCase(.uppercase)

                Text("No plans yet")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)

                Text("Ask your coach to build a structured training plan — tailored to your goals, target event, and weekly hours.")
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg1)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }

            if let onOpenChat {
                Button(action: onOpenChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Build a plan")
                            .mangoxFont(.callout)
                    }
                    .foregroundStyle(AppColor.bg0)
                    .padding(.horizontal, MangoxSpacing.xl.rawValue)
                    .padding(.vertical, 11)
                    .background(AppColor.mango)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AppColor.mango.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(MangoxPressStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MangoxSpacing.xl.rawValue)
        .padding(.vertical, MangoxSpacing.xxl.rawValue)
        .mangoxSurface(.flatSubtle, shape: .rounded(MangoxRadius.overlay.rawValue))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [AppColor.mango, AppColor.mango.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .mangoxFont(.label)
            .foregroundStyle(AppColor.fg3)
            .tracking(1.4)
    }

    // MARK: - AI Plan Card

    private func standardPlanCard(plan: TrainingPlan?, originalAIPlan: AIGeneratedPlan?) -> some View {
        guard let resolvedPlan = plan, let originalAIPlan else { return AnyView(EmptyView()) }
        let planID = originalAIPlan.id
        let progress = allPlanProgress.first { $0.planID == planID }

        return AnyView(VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                planCardGlyph(systemName: "figure.outdoor.cycle", color: AppColor.mango)

                VStack(alignment: .leading, spacing: 4) {
                    Text("TRAINING PLAN")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.mango)
                        .tracking(1.4)

                    Text(resolvedPlan.name)
                        .font(MangoxFont.value.value)
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
                            .mangoxFont(.caption)
                            .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                            .lineLimit(2)
                        }
                    }

                    Text("Updated \(originalAIPlan.generatedAt.formatted(date: .abbreviated, time: .omitted))")
                        .mangoxFont(.caption)
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                }

                Spacer(minLength: 6)

                Menu {
                    Button {
                        if !coachViewModel.stagePlanRegeneration(
                            from: AIGeneratedPlanDraft(
                                id: originalAIPlan.id,
                                userPrompt: originalAIPlan.userPrompt,
                                regenerationInputsJSON: originalAIPlan.regenerationInputsJSON
                            )
                        ) {
                            showRegenerateInputsMissing = true
                        }
                    } label: {
                        Label("Regenerate similar", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        destructiveAction = .resetAIProgress(id: originalAIPlan.id)
                    } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        destructiveAction = .deleteAIPlan(id: originalAIPlan.id)
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
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
                            .mangoxFont(.label)
                            .foregroundStyle(AppColor.fg3)
                            .tracking(1.2)
                        Spacer()
                        Text("\(Int((pct * 100).rounded()))%")
                            .mangoxFont(.caption)
                            .foregroundStyle(AppColor.mango.opacity(0.9))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(AppColor.hair2)
                                .frame(height: 3)
                            Rectangle()
                                .fill(AppColor.mango)
                                .frame(width: max(6, geo.size.width * pct), height: 3)
                        }
                    }
                    .frame(height: 3)
                }
            }

            Button {
                navigationPath.append(AppRoute.aiPlan(planID: planID))
                dismissParentChatIfNeeded()
            } label: {
                HStack(spacing: 8) {
                    Text((progress?.completedCount ?? 0) > 0 ? "Resume training" : "Open plan")
                        .mangoxFont(.label)
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(AppColor.mango)
                .overlay(Rectangle().stroke(AppColor.mango.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(16)
        .background(AppColor.bg2)
        .overlay(Rectangle().stroke(AppColor.hair2, lineWidth: 1)))
    }

    // MARK: - Card Helpers

    private func planCardGlyph(systemName: String, color: Color) -> some View {
        ZStack {
            Rectangle()
                .fill(AppColor.bg1)
                .frame(width: 42, height: 42)
                .overlay(Rectangle().stroke(color.opacity(0.32), lineWidth: 1))
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }

    private func planStatPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.fg3)
            Text(text)
                .mangoxFont(.caption)
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppColor.bg1)
        .overlay(Rectangle().stroke(AppColor.hair, lineWidth: 1))
    }

    // MARK: - Data Actions

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
