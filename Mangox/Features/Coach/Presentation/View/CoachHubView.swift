import SwiftUI
import SwiftData

/// Coach tab landing: plans on the page + entry into full-screen chat.
struct CoachHubView: View {
    @Binding var navigationPath: NavigationPath
    @Binding var showChat: Bool
    @Environment(CoachViewModel.self) private var coachViewModel
    @State private var chatOpenFeedbackTick = 0

    // MARK: - Design System

    private var mango: Color { AppColor.mango }
    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    var body: some View {
        ZStack {
            AppColor.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                minimalTopBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(spacing: 16) {
                        plansSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }

            if !showChat {
                VStack {
                    Spacer()
                    if let draft = coachViewModel.planConfirmationDraft {
                        CoachPlanConfirmBanner(draft: draft, navigationPath: $navigationPath)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 28)
                    } else if let celeb = coachViewModel.planSaveCelebration {
                        CoachPlanSuccessBanner(
                            celebration: celeb,
                            navigationPath: $navigationPath,
                            dismissChat: nil
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.smooth(duration: 0.28), value: coachViewModel.planConfirmationDraft?.id)
                .animation(.smooth(duration: 0.28), value: coachViewModel.planSaveCelebration?.planID)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Top Bar

    private var minimalTopBar: some View {
        HStack(spacing: 8) {
            Text("Coach")
                .font(.title2.weight(.bold))
                .foregroundStyle(textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                chatOpenFeedbackTick += 1
                showChat = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Chat")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppColor.bg)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(mango)
                .clipShape(Capsule())
            }
            .buttonStyle(MangoxPressStyle())
            .sensoryFeedback(.impact(weight: .light, intensity: 0.85), trigger: chatOpenFeedbackTick)
            .accessibilityLabel("Chat with your coach")
            .accessibilityHint("Opens full-screen coach conversation.")
        }
    }

    // MARK: - Plans

    private var plansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MY PLANS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(textTertiary)
                    .tracking(1.0)
                Spacer()
            }
            .padding(.horizontal, 4)

            CoachPlansPanel(
                navigationPath: $navigationPath,
                dismissParentChat: nil,
                showsIntroCopy: false,
                showsSectionHeader: false,
                onOpenChat: { showChat = true }
            )
        }
    }
}

#Preview {
    NavigationStack {
        CoachHubView(navigationPath: .constant(NavigationPath()), showChat: .constant(false))
    }
    .modelContainer(for: [TrainingPlanProgress.self, AIGeneratedPlan.self], inMemory: true)
    .environment(CoachViewModel(coach: AIService(), purchasesService: PurchasesManager.shared))
}
