import SwiftUI
import SwiftData

struct CoachHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchasesManager.self) private var purchases
    @Binding var navigationPath: NavigationPath

    @Query(sort: \TrainingPlanProgress.startDate, order: .reverse)
    private var allPlanProgress: [TrainingPlanProgress]

    @Query(sort: \AIGeneratedPlan.generatedAt, order: .reverse)
    private var aiPlans: [AIGeneratedPlan]

    @State private var showChat = false
    @State private var showGeneratePlan = false
    @State private var showPaywall = false
    @State private var showResetBuiltinConfirmation = false
    @State private var showHideBuiltinConfirmation = false
    @State private var resetTargetAIPlanID: String? = nil
    @State private var deleteTargetAIPlanID: String? = nil

    /// Hidden via UserDefaults so the user can restore it later from Settings.
    @State private var builtinPlanHidden: Bool = UserDefaults.standard.bool(forKey: "classicissima_hidden")

    private let bg = AppColor.bg

    private var builtinPlanID: String { CachedPlan.shared.id }

    private var builtinProgress: TrainingPlanProgress? {
        allPlanProgress.first { $0.planID == builtinPlanID }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    bg,
                    Color(red: 0.05, green: 0.06, blue: 0.1),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    chatEntryCard
                    plansSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Reset Classicissima progress?",
            isPresented: $showResetBuiltinConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset progress", role: .destructive) { resetBuiltinProgress() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The Classicissima template stays in Mangox. This only clears your completions and dates.")
        }
        .confirmationDialog(
            "Remove Classicissima?",
            isPresented: $showHideBuiltinConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from list", role: .destructive) { hideBuiltinPlan() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Classicissima from your plans list and clears all progress. It cannot be restored.")
        }
        .confirmationDialog(
            "Reset plan progress?",
            isPresented: Binding(
                get: { resetTargetAIPlanID != nil },
                set: { if !$0 { resetTargetAIPlanID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Reset progress", role: .destructive) {
                if let id = resetTargetAIPlanID { resetAIPlanProgress(planID: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears your completed and skipped workouts for this plan.")
        }
        .confirmationDialog(
            "Delete this plan?",
            isPresented: Binding(
                get: { deleteTargetAIPlanID != nil },
                set: { if !$0 { deleteTargetAIPlanID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete plan", role: .destructive) {
                if let id = deleteTargetAIPlanID { deleteAIPlan(id: id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan and all progress will be permanently deleted.")
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                AIChatView()
            }
        }
        .sheet(isPresented: $showGeneratePlan) {
            PlanGenerationView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coach")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .textCase(.uppercase)
                .tracking(1.2)

            Text("Your training hub")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)

            Text("Chat with your coach, follow structured plans, and track progress toward your goals.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.46))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Chat Entry Card

    private var chatEntryCard: some View {
        Button {
            showChat = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColor.mango.opacity(0.16))
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(AppColor.mango)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Chat with your Coach")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    Text("Training advice · ride analysis · goal planning")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.6))
            }
            .padding(18)
            .background(AppColor.mango.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(AppColor.mango.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(MangoxPressStyle())
    }

    // MARK: - Plans Section

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("MY PLANS")
                Spacer()
                generatePlanButton
            }

            if !aiPlans.isEmpty {
                ForEach(aiPlans) { aiPlan in
                    aiPlanCard(aiPlan)
                }
            }

            if !builtinPlanHidden {
                builtinPlanCard
            }
        }
    }

    private var generatePlanButton: some View {
        Button {
            showGeneratePlan = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("Generate")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(AppColor.mango)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(AppColor.mango.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(MangoxPressStyle())
    }

    // MARK: - AI Plan Card

    private func aiPlanCard(_ aiPlan: AIGeneratedPlan) -> some View {
        let progress = allPlanProgress.first { $0.planID == aiPlan.id }
        let resolvedPlan = aiPlan.plan

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                planIcon(symbol: "sparkles", tint: AppColor.mango)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("AI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(AppColor.mango)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(AppColor.mango.opacity(0.14))
                            .clipShape(Capsule())

                        Text(resolvedPlan?.name ?? aiPlan.userPrompt)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)
                    }

                    Text(aiPlan.generatedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer(minLength: 8)

                Menu {
                    Button {
                        resetTargetAIPlanID = aiPlan.id
                    } label: {
                        Label("Reset Progress", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        deleteTargetAIPlanID = aiPlan.id
                    } label: {
                        Label("Delete Plan", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            if let plan = resolvedPlan {
                HStack(spacing: 10) {
                    planMetaChip("\(plan.totalWeeks) weeks")
                    if !plan.distance.isEmpty { planMetaChip(plan.distance) }
                    if let p = progress, p.completedCount > 0 {
                        planMetaChip("\(p.completedCount) done")
                    }
                }

                if let p = progress, p.completedCount > 0 {
                    let totalWorkouts = plan.allDays
                        .filter { $0.dayType == .workout || $0.dayType == .ftpTest }.count
                    let pct = totalWorkouts > 0 ? Double(p.completedCount) / Double(totalWorkouts) : 0
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(AppColor.mango)
                                .frame(width: geo.size.width * pct, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }

            Button {
                navigationPath.append(AppRoute.aiPlan(planID: aiPlan.id))
            } label: {
                Text(progress?.completedCount ?? 0 > 0 ? "Resume Plan" : "Open Plan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColor.mango)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(18)
        .cardStyle(cornerRadius: 20)
    }

    // MARK: - Built-in Plan Card

    private var builtinPlanCard: some View {
        let progress = builtinProgress
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                planIcon(symbol: "flame.fill", tint: AppColor.yellow)

                VStack(alignment: .leading, spacing: 5) {
                    Text(CachedPlan.shared.eventName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))

                    Text(progress == nil ? "Built-in structured event plan" : "Active classic event plan")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.46))
                }

                Spacer(minLength: 8)
                statusChip(progress == nil ? "Ready" : "Active", tint: progress == nil ? .white.opacity(0.3) : AppColor.success)

                Menu {
                    if progress != nil {
                        Button("Reset Progress", role: .destructive) {
                            showResetBuiltinConfirmation = true
                        }
                    }
                    Button("Remove from List", role: .destructive) {
                        showHideBuiltinConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            HStack(spacing: 10) {
                planMetaChip("8 weeks")
                planMetaChip(CachedPlan.shared.distance)
                if let progress {
                    planMetaChip("\(progress.completedCount) done")
                }
            }

            Button {
                navigationPath.append(AppRoute.trainingPlan)
            } label: {
                Text(progress == nil ? "Open Plan" : "Resume Plan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.78))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(AppColor.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MangoxPressStyle())

            Text("Built-in template — reset progress to start over from week one.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .cardStyle(cornerRadius: 20)
    }

    // MARK: - Actions

    private func resetBuiltinProgress() {
        guard let p = builtinProgress else { return }
        modelContext.delete(p)
        try? modelContext.save()
    }

    private func hideBuiltinPlan() {
        // Clear any progress first
        if let p = builtinProgress {
            modelContext.delete(p)
            try? modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: "classicissima_hidden")
        builtinPlanHidden = true
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

    // MARK: - Subviews

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white.opacity(0.28))
            .tracking(1.4)
    }

    private func planIcon(symbol: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 46, height: 46)
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }

    private func planMetaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.56))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05))
            .clipShape(Capsule())
    }
}

#Preview {
    NavigationStack {
        CoachHubView(navigationPath: .constant(NavigationPath()))
    }
    .modelContainer(for: [TrainingPlanProgress.self, AIGeneratedPlan.self], inMemory: true)
    .environment(PurchasesManager.shared)
}
