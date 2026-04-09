import SwiftUI
import SwiftData

/// Coach tab: hub with visible plans + chat in a full-screen cover (cleaner keyboard + no sheet resize fights).
struct CoachTabRootView: View {
    @Binding var navigationPath: NavigationPath
    @State private var showChat = false

    var body: some View {
        CoachHubView(navigationPath: $navigationPath, showChat: $showChat)
            .fullScreenCover(isPresented: $showChat) {
                NavigationStack {
                    CoachConversationView(
                        navigationPath: $navigationPath,
                        chatSheetPresented: $showChat
                    )
                }
            }
    }
}

#Preview {
    NavigationStack {
        CoachTabRootView(navigationPath: .constant(NavigationPath()))
    }
    .modelContainer(for: [TrainingPlanProgress.self, AIGeneratedPlan.self, ChatSession.self, CoachChatMessage.self], inMemory: true)
    .environment(PurchasesManager.shared)
    .environment(AIService())
}
