import SwiftUI

// MARK: - Shared settings chrome (detail screens + root rows)

func settingsIconBadge(_ systemName: String, color: Color) -> some View {
    MangoxIconBadge(systemName: systemName, color: color)
}

func settingsSubCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
        content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .cardStyle(cornerRadius: 16)
    .padding(.horizontal, MangoxSpacing.page)
}

func settingsSubToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.35))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    .tint(AppColor.mango)
}

func settingsSubSectionLabel(_ title: String) -> some View {
    MangoxSectionLabel(title: title)
        .tracking(1.2)
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
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissToolbar()
        .toolbar(.hidden, for: .tabBar)
    }
}
