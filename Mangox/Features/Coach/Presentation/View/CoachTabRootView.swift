import SwiftUI
import SwiftData

/// Coach tab: hub with visible plans + chat in a full-screen cover (cleaner keyboard + no sheet resize fights).
struct CoachTabRootView: View {
    @Binding var navigationPath: NavigationPath
    @State private var viewModel: CoachViewModel
    @State private var showChat = false

    init(navigationPath: Binding<NavigationPath>, viewModel: CoachViewModel) {
        self._navigationPath = navigationPath
        self._viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        CoachHubView(navigationPath: $navigationPath, showChat: $showChat)
            .environment(viewModel)
            .fullScreenCover(isPresented: $showChat) {
                NavigationStack {
                    CoachConversationView(
                        navigationPath: $navigationPath,
                        chatSheetPresented: $showChat
                    )
                }
                .environment(viewModel)
            }
    }
}

#Preview {
    NavigationStack {
        CoachTabRootView(
            navigationPath: .constant(NavigationPath()),
            viewModel: CoachViewModel(coach: AIService(), purchasesService: PurchasesManager.shared)
        )
    }
    .modelContainer(for: [TrainingPlanProgress.self, AIGeneratedPlan.self, ChatSession.self, CoachChatMessage.self], inMemory: true)
    .environment(PurchasesManager.shared)
}
