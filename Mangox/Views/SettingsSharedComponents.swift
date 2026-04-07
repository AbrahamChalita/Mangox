import SwiftUI

// MARK: - Shared settings chrome (detail screens + root rows)

func settingsIconBadge(_ systemName: String, color: Color) -> some View {
    Image(systemName: systemName)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(color)
        .frame(width: 30, height: 30)
        .background(color.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 7))
}

func settingsSubCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .cardStyle(cornerRadius: 16)
    .padding(.horizontal, 20)
}

func settingsSubToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
    .tint(AppColor.mango)
}

func settingsSubSectionLabel(_ title: String) -> some View {
    Text(title.uppercased())
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(.white.opacity(0.32))
        .tracking(1.2)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
}

struct SettingsSubviewShell<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 4)
                    content()
                    Spacer().frame(height: 40)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
        .toolbar(.hidden, for: .tabBar)
    }
}
