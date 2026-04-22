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
    .cardStyle(cornerRadius: MangoxRadius.sharp.rawValue)
    .padding(.horizontal, MangoxSpacing.page)
}

func settingsSubToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
    Toggle(isOn: isOn) {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MangoxFont.callout.value)
                .foregroundStyle(AppColor.fg1)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Text(subtitle)
                .font(MangoxFont.caption.value)
                .foregroundStyle(AppColor.fg3)
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

// MARK: - Typography (Manrope / Geist Mono — matches Mangox design system)

extension Text {
    /// Card field labels and emphasized one-line titles (~15pt medium).
    func settingsPrimary() -> some View {
        font(MangoxFont.bodyBold.value).foregroundStyle(AppColor.fg1)
    }

    /// Toggle titles, compact row headings (~13pt medium).
    func settingsSecondary() -> some View {
        font(MangoxFont.callout.value).foregroundStyle(AppColor.fg1)
    }

    /// Supporting copy and descriptions (11pt mono).
    func settingsFootnote() -> some View {
        font(MangoxFont.caption.value).foregroundStyle(AppColor.fg2)
    }

    /// Muted footnotes and helper lines.
    func settingsFootnoteMuted() -> some View {
        font(MangoxFont.caption.value).foregroundStyle(AppColor.fg3)
    }

    /// Fine print (9pt mono).
    func settingsMicro() -> some View {
        font(MangoxFont.micro.value).foregroundStyle(AppColor.fg3)
    }

    /// Numeric / monospace data (11pt mono, tabular digits).
    func settingsMonoCaption() -> some View {
        font(MangoxFont.caption.value)
            .foregroundStyle(AppColor.fg3)
            .monospacedDigit()
    }
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
