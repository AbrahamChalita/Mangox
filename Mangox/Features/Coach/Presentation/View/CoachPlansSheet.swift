import SwiftUI

/// “My plans” from chat — wraps `CoachPlansPanel` with a nav bar Done button.
struct CoachPlansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var navigationPath: NavigationPath
    var dismissParentChat: Binding<Bool>? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                CoachPlansPanel(
                    navigationPath: $navigationPath,
                    dismissParentChat: dismissParentChat,
                    showsIntroCopy: true
                )
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .background(AppColor.bg.ignoresSafeArea())
            .navigationTitle("My plans")
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
