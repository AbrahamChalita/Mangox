import SwiftUI

/// “My workouts” from chat — wraps `CoachWorkoutsPanel` with a nav bar Done button.
struct CoachWorkoutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigationPath: NavigationPath
    var dismissParentChat: Binding<Bool>? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                CoachWorkoutsPanel(
                    navigationPath: $navigationPath,
                    dismissParentChat: dismissParentChat,
                    showsIntroCopy: true
                )
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.bg.ignoresSafeArea())
            .navigationTitle("My workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.mango)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
