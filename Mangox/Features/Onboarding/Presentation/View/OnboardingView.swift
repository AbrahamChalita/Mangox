import PhotosUI
import SwiftUI
import UIKit

// MARK: - Hero graphic

private enum OnboardingHeroGraphic {
    case sfSymbol(String)
    case brandAsset(String)
}

/// First-launch onboarding with permission screens.
/// Shown once — persisted via `@AppStorage("hasCompletedOnboarding")`.
///
/// Flow: Welcome → Bluetooth → HealthKit → Notifications → Location → Strava → Rider profile → Get Started
struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel: OnboardingViewModel
    @State private var onboardingProfilePhotoItem: PhotosPickerItem?
    @State private var onboardingLocalAvatarToken = UUID()

    private let totalPages = 8

    init(viewModel: OnboardingViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var pageAccent: Color {
        switch viewModel.currentStep {
        case 0: return AppColor.mango
        case 1: return AppColor.blue
        case 2: return AppColor.heartRate
        case 3: return AppColor.orange
        case 4: return AppColor.success
        case 5: return AppColor.strava
        default: return AppColor.mango
        }
    }

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()
            OnboardingAmbientBackground(accent: pageAccent, reduceMotion: reduceMotion)

            VStack(spacing: 0) {
                TabView(selection: binding(\.currentStep)) {
                    welcomePage.tag(0)
                    bluetoothPage.tag(1)
                    healthKitPage.tag(2)
                    notificationsPage.tag(3)
                    locationPage.tag(4)
                    stravaPage.tag(5)
                    riderProfilePage.tag(6)
                    getStartedPage.tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.35), value: viewModel.currentStep)

                Spacer()

                progressSection
                    .padding(.bottom, 20)

                actionButton
                    .padding(.horizontal, 32)

                if viewModel.currentStep < totalPages - 1 {
                    Button(viewModel.isPermissionPage ? "Maybe Later" : "Skip") {
                        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) { viewModel.advance() }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                } else {
                    Spacer().frame(height: 56)
                }
            }
        }
        .onAppear {
            syncWelcomeAppearance()
        }
        .onChange(of: reduceMotion) {
            syncWelcomeAppearance()
        }
        .onChange(of: viewModel.currentStep) { _, new in
            if new == 0 {
                syncWelcomeAppearance()
            }
            if new == 6 {
                viewModel.prepareRiderProfileStep()
            }
            if new == 7 {
                triggerFinishCelebrationIfNeeded()
            }
        }
        .onChange(of: onboardingProfilePhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    try? RiderProfileAvatarStore.saveLocalAvatar(uiImage)
                    await MainActor.run {
                        onboardingLocalAvatarToken = UUID()
                        onboardingProfilePhotoItem = nil
                    }
                }
            }
        }
        .onChange(of: viewModel.blePermissionGranted) { _, new in
            if new, viewModel.currentStep == 1 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: viewModel.healthKitGranted) { _, new in
            if new, viewModel.currentStep == 2 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: viewModel.notificationsGranted) { _, new in
            if new, viewModel.currentStep == 3 { HapticManager.shared.onboardingStepCompleted() }
        }
        .onChange(of: viewModel.locationGranted) { _, new in
            if new, viewModel.currentStep == 4 { HapticManager.shared.onboardingStepCompleted() }
        }
        .task {
            await viewModel.syncInitialPermissionState()
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<OnboardingViewModel, Value>)
        -> Binding<Value>
    {
        Binding(
            get: { viewModel[keyPath: keyPath] },
            set: { viewModel[keyPath: keyPath] = $0 }
        )
    }

    private func syncWelcomeAppearance() {
        viewModel.syncWelcomeAppearance(reduceMotion: reduceMotion)
        if !reduceMotion, viewModel.currentStep == 0 {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    viewModel.welcomeAppeared = true
                }
            }
        }
    }

    private func triggerFinishCelebrationIfNeeded() {
        viewModel.triggerFinishCelebrationIfNeeded(reduceMotion: reduceMotion)
        guard !reduceMotion else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                viewModel.finishCelebration = true
            }
        }
    }

    // MARK: - Progress (page dots only)

    private var progressSection: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == viewModel.currentStep ? AppColor.mango : Color.white.opacity(0.15))
                    .frame(width: index == viewModel.currentStep ? 24 : 8, height: 8)
                    .animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: viewModel.currentStep)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(viewModel.currentStep + 1) of \(totalPages)")
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Button {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.25)) {
                viewModel.handleAction(reduceMotion: reduceMotion)
            }
        } label: {
            Text(viewModel.buttonTitle())
                .font(.body.weight(.bold))
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColor.mango)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(MangoxPressStyle())
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingWelcomePage(
            welcomeAppeared: viewModel.welcomeAppeared,
            reduceMotion: reduceMotion,
            featureRows: {
                VStack(spacing: 8) {
                    featureRow(icon: "antenna.radiowaves.left.and.right", text: "Smart trainers, power, HR, and sensors")
                    featureRow(icon: "map.fill", text: "Outdoor GPS rides with routes and navigation")
                    featureRow(icon: "chart.line.uptrend.xyaxis", text: "PMC, power curve, adaptive plan load")
                    featureRow(icon: "sparkles", text: "AI coach and calendar export (.ics)")
                    featureRow(icon: "paperplane.fill", text: "Optional Strava upload and Apple Health")
                }
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }
        )
    }

    private var bluetoothPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("antenna.radiowaves.left.and.right"),
            title: "Connect Your Gear",
            subtitle: "Mangox uses Bluetooth to connect to your smart trainer, heart rate monitor, and power meter.",
            color: AppColor.blue,
            granted: viewModel.blePermissionGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote("Required for indoor training. Also works outdoors with BLE sensors.")
            }
        )
    }

    private var healthKitPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("heart.text.square.fill"),
            title: "Health Data",
            subtitle: "Read resting HR, max HR, and VO2 Max for zones. You can opt in later to save finished rides to the Fitness app.",
            color: AppColor.heartRate,
            granted: viewModel.healthKitGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote(
                    "Reads are used for zones. Saving rides to Apple Health is optional in Settings → Heart Rate."
                )
            }
        )
    }

    private var locationPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("location.fill"),
            title: "GPS Location",
            subtitle: "Track outdoor rides with live speed, distance, elevation, and route recording right on your phone.",
            color: AppColor.success,
            granted: viewModel.locationGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote("Used only during outdoor rides. Never tracked in the background when not riding.")
            }
        )
    }

    private var notificationsPage: some View {
        OnboardingPageView(
            hero: .sfSymbol("bell.badge.fill"),
            title: "Stay On Track",
            subtitle:
                "You can turn on workout reminders and plan nudges later in Settings → Data, privacy & alerts — and iOS will ask for notification permission only when you opt in there.",
            color: AppColor.orange,
            granted: viewModel.notificationsGranted,
            reduceMotion: reduceMotion,
            extraContent: {
                permissionNote(
                    "We don't request notification access during onboarding so you stay in control.")
            }
        )
    }

    private var stravaPage: some View {
        OnboardingPageView(
            hero: .brandAsset("BrandStrava"),
            title: "Share With Strava",
            subtitle: "One tap to upload your ride after every session. You can connect Strava anytime from your profile.",
            color: AppColor.strava,
            granted: viewModel.stravaConnected,
            reduceMotion: reduceMotion,
            extraContent: {
                VStack(spacing: 12) {
                    if viewModel.stravaConnected {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(AppColor.success)
                            Text("Strava connected")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    if let stravaStatus = viewModel.stravaStatus {
                        Text(stravaStatus)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    permissionNote("Optional — connect from Settings whenever you're ready.")
                }
            }
        )
    }

    private var riderProfilePage: some View {
        let isImperial = RidePreferences.shared.isImperial
        let displayWeight = isImperial
            ? viewModel.onboardingWeightKg * 2.20462
            : viewModel.onboardingWeightKg
        let weightUnit = isImperial ? "lb" : "kg"
        let weightRange: ClosedRange<Double> = isImperial ? 66.0...440.0 : RidePreferences.riderWeightRange
        let weightStep = isImperial ? 1.0 : 0.5

        let nameLine = viewModel.onboardingRiderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameSummary = nameLine.isEmpty ? "Shown in the app & summaries" : nameLine

        return OnboardingPageView(
            hero: .sfSymbol("figure.outdoor.cycle"),
            title: "Your Rider Profile",
            subtitle:
                "Add your name and an optional photo, plus weight and birth date for W/kg, calorie estimates, and coaching.",
            color: AppColor.blue,
            reduceMotion: reduceMotion,
            extraContent: {
                VStack(spacing: MangoxSpacing.lg.rawValue) {
                    onboardingRiderIdentityNameCard(nameSummary: nameSummary)
                    onboardingRiderIdentityPhotoCard

                    riderInputCard(
                        icon: "scalemass.fill",
                        title: "WEIGHT",
                        value: "\(Int(displayWeight.rounded())) \(weightUnit)",
                        accent: AppColor.mango
                    ) {
                        Slider(
                            value: Binding(
                                get: {
                                    isImperial ? viewModel.onboardingWeightKg * 2.20462 : viewModel.onboardingWeightKg
                                },
                                set: { newValue in
                                    viewModel.onboardingWeightKg = isImperial ? (newValue / 2.20462) : newValue
                                }
                            ),
                            in: weightRange,
                            step: weightStep
                        )
                        .tint(AppColor.mango)

                        HStack {
                            Text("\(Int(weightRange.lowerBound)) \(weightUnit)")
                            Spacer()
                            Text("\(Int(weightRange.upperBound)) \(weightUnit)")
                        }
                        .mangoxFont(.caption)
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                    }

                    riderInputCard(
                        icon: "calendar",
                        title: "BIRTH DATE",
                        value: "\(viewModel.onboardingBirthYear)  ·  Age \(onboardingAge)",
                        accent: AppColor.blue
                    ) {
                        DatePicker(
                            "Birth date",
                            selection: onboardingBirthDateBinding,
                            in: onboardingBirthDateRange,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .datePickerStyle(.wheel)
                        .tint(AppColor.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 148)
                        .clipped()
                        .background(Color.white.opacity(AppOpacity.pillBg))
                        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                                .strokeBorder(Color.white.opacity(AppOpacity.divider), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 32)
            }
        )
    }

    private var getStartedPage: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColor.mango.opacity(0.08))
                    .frame(width: 200, height: 200)
                    .scaleEffect(viewModel.finishCelebration ? 1 : 0.92)
                Circle()
                    .fill(AppColor.mango.opacity(0.04))
                    .frame(width: 260, height: 260)
                    .scaleEffect(viewModel.finishCelebration ? 1 : 0.94)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(AppColor.mango)
                    .scaleEffect(viewModel.finishCelebration ? 1 : 0.5)
                    .opacity(viewModel.finishCelebration ? 1 : 0.001)
            }
            .animation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.68), value: viewModel.finishCelebration)

            VStack(spacing: 12) {
                Text("You're All Set")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Connect your trainer for indoor rides, or start an outdoor ride with GPS whenever you're ready.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Rider profile (identity)

    private func onboardingRiderIdentityNameCard(nameSummary: String) -> some View {
        let nameLine = viewModel.onboardingRiderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
            HStack(alignment: .top, spacing: MangoxSpacing.md.rawValue) {
                MangoxIconBadge(systemName: "person.text.rectangle", color: AppColor.mango, size: 34)
                VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                    Text("DISPLAY NAME")
                        .mangoxFont(.label)
                        .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                        .tracking(1.1)
                    if nameLine.isEmpty {
                        Text(nameSummary)
                            .mangoxFont(.caption)
                            .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(nameLine)
                            .font(MangoxFont.compactValue.value)
                            .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                    TextField("Your name", text: $viewModel.onboardingRiderDisplayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .mangoxFont(.bodyBold)
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .padding(.horizontal, MangoxSpacing.md.rawValue)
                        .padding(.vertical, MangoxSpacing.sm.rawValue + 2)
                        .background(Color.white.opacity(AppOpacity.pillBg))
                        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue, style: .continuous)
                                .strokeBorder(Color.white.opacity(AppOpacity.divider), lineWidth: 1)
                        )
                        .onChange(of: viewModel.onboardingRiderDisplayName) { _, new in
                            if new.count > 50 {
                                viewModel.onboardingRiderDisplayName = String(new.prefix(50))
                            }
                        }
                    Text("Used in Settings, ride summaries, and story cards — Strava is optional.")
                        .mangoxFont(.caption)
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(MangoxSpacing.lg.rawValue)
        .cardStyle(cornerRadius: MangoxRadius.card.rawValue)
    }

    private var onboardingRiderIdentityPhotoCard: some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
            HStack(alignment: .center, spacing: MangoxSpacing.lg.rawValue) {
                Group {
                    if let img = RiderProfileAvatarStore.loadLocalAvatar() {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Color.white.opacity(AppOpacity.pillBg)
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 26, weight: .medium))
                                .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                        }
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous)
                        .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
                )
                .id(onboardingLocalAvatarToken)

                VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                    Text("PROFILE PHOTO")
                        .mangoxFont(.label)
                        .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                        .tracking(1.1)
                    Text(
                        RiderProfileAvatarStore.hasLocalAvatar
                            ? "Saved on this device for Settings."
                            : "Optional — add a face for your profile header."
                    )
                    .mangoxFont(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: MangoxSpacing.sm.rawValue) {
                        PhotosPicker(selection: $onboardingProfilePhotoItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                                .mangoxFont(.callout)
                                .foregroundStyle(.black)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, MangoxSpacing.md.rawValue)
                                .padding(.vertical, MangoxSpacing.sm.rawValue)
                                .background(AppColor.mango)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(MangoxPressStyle())

                        if RiderProfileAvatarStore.hasLocalAvatar {
                            Button {
                                RiderProfileAvatarStore.clearLocalAvatar()
                                onboardingLocalAvatarToken = UUID()
                            } label: {
                                Text("Remove")
                                    .mangoxFont(.callout)
                                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                                    .padding(.horizontal, MangoxSpacing.md.rawValue)
                                    .padding(.vertical, MangoxSpacing.sm.rawValue)
                                    .background(Color.white.opacity(AppOpacity.pillBg))
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.white.opacity(AppOpacity.divider), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(MangoxPressStyle())
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(MangoxSpacing.lg.rawValue)
        .cardStyle(cornerRadius: MangoxRadius.card.rawValue)
    }

    // MARK: - Helper Views

    private var onboardingAge: Int {
        max(0, Calendar.current.component(.year, from: .now) - viewModel.onboardingBirthYear)
    }

    private var onboardingBirthDateBinding: Binding<Date> {
        Binding(
            get: { dateFromBirthYear(viewModel.onboardingBirthYear) },
            set: { newDate in
                viewModel.onboardingBirthYear = Calendar.current.component(.year, from: newDate)
            }
        )
    }

    private var onboardingBirthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: .now)
        let minimum = calendar.date(from: DateComponents(year: 1940, month: 1, day: 1)) ?? .distantPast
        let maximum = calendar.date(from: DateComponents(year: currentYear - 16, month: 12, day: 31)) ?? .now
        return minimum...maximum
    }

    private func dateFromBirthYear(_ year: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: 7, day: 1)) ?? .now
    }

    private func riderInputCard<Content: View>(
        icon: String,
        title: String,
        value: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.md.rawValue) {
            HStack(alignment: .top, spacing: MangoxSpacing.md.rawValue) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: MangoxSpacing.xs.rawValue) {
                    Text(title)
                        .mangoxFont(.label)
                        .foregroundStyle(.white.opacity(AppOpacity.textQuaternary))
                        .tracking(1.1)

                    Text(value)
                        .font(MangoxFont.compactValue.value)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                }
            }

            content()
        }
        .padding(MangoxSpacing.lg.rawValue)
        .cardStyle(cornerRadius: MangoxRadius.card.rawValue)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(AppColor.mango.opacity(0.75))
                .frame(width: 24)
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
            Spacer()
        }
    }

    private func permissionNote(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.38))
        }
        .padding(.horizontal, 40)
        .padding(.top, 4)
    }
}

// MARK: - Ambient background

private struct OnboardingAmbientBackground: View {
    let accent: Color
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(
                    colors: [
                        accent.opacity(0.22),
                        accent.opacity(0.06),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: geo.size.width * 0.95
                )
                RadialGradient(
                    colors: [
                        AppColor.mango.opacity(0.12),
                        Color.clear,
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: geo.size.height * 0.55
                )
            }
            .ignoresSafeArea()
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.7), value: accent)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Welcome page

private struct OnboardingWelcomePage<FeatureRows: View>: View {
    var welcomeAppeared: Bool
    var reduceMotion: Bool
    @ViewBuilder var featureRows: () -> FeatureRows

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.mango.opacity(0.12 - Double(i) * 0.015))
                        .frame(width: 120 - CGFloat(i) * 14, height: 3)
                        .offset(x: CGFloat(i) * 6 + 40, y: CGFloat(i) * 5 - 20)
                        .rotationEffect(.degrees(-18))
                        .opacity(welcomeLineOpacity(index: i))
                        .animation(welcomeAnimation(delay: 0.02 + Double(i) * 0.03), value: welcomeAppeared)
                }

                ZStack {
                    Circle()
                        .fill(AppColor.mango.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .scaleEffect(heroHaloScale)
                    Circle()
                        .fill(AppColor.mango.opacity(0.05))
                        .frame(width: 248, height: 248)
                        .scaleEffect(heroHaloScale * 1.02)

                    Image(systemName: "figure.outdoor.cycle")
                        .font(.system(size: 76, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColor.mango, AppColor.yellow.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: AppColor.mango.opacity(0.35), radius: 18, y: 8)
                        .opacity(welcomeAppeared ? 1 : 0)
                        .offset(y: welcomeAppeared ? 0 : 16)
                        .animation(welcomeAnimation(delay: 0.06), value: welcomeAppeared)
                }
                .animation(welcomeAnimation(delay: 0.04), value: welcomeAppeared)
            }
            .padding(.bottom, 8)

            VStack(spacing: 10) {
                Text("Train smarter")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(welcomeAppeared ? 1 : 0)
                    .offset(y: welcomeAppeared ? 0 : 16)
                    .animation(welcomeAnimation(delay: 0.14), value: welcomeAppeared)

                Text("Indoor ERG, outdoor GPS, and plans — without juggling another bike computer app.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .opacity(welcomeAppeared ? 1 : 0)
                    .offset(y: welcomeAppeared ? 0 : 16)
                    .animation(welcomeAnimation(delay: 0.22), value: welcomeAppeared)
            }

            featureRows()
                .opacity(welcomeAppeared ? 1 : 0)
                .offset(y: welcomeAppeared ? 0 : 14)
                .animation(welcomeAnimation(delay: 0.3), value: welcomeAppeared)

            Spacer()
        }
    }

    private func welcomeAnimation(delay: Double) -> Animation {
        if reduceMotion { return .linear(duration: 0) }
        return .spring(response: 0.52, dampingFraction: 0.84).delay(delay)
    }

    private func welcomeLineOpacity(index: Int) -> Double {
        if reduceMotion { return 0.35 - Double(index) * 0.04 }
        return welcomeAppeared ? (0.35 - Double(index) * 0.04) : 0
    }

    private var heroHaloScale: CGFloat {
        if reduceMotion { return 1 }
        return welcomeAppeared ? 1 : 0.94
    }
}

// MARK: - Standard permission / integration page

private struct OnboardingPageView<ExtraContent: View>: View {
    let hero: OnboardingHeroGraphic
    let title: String
    let subtitle: String
    let color: Color
    var granted: Bool = false
    var reduceMotion: Bool
    let extraContent: () -> ExtraContent

    @State private var pulseLarge = false
    @State private var checkPop = false

    init(
        hero: OnboardingHeroGraphic,
        title: String,
        subtitle: String,
        color: Color,
        granted: Bool = false,
        reduceMotion: Bool,
        @ViewBuilder extraContent: @escaping () -> ExtraContent = { EmptyView() }
    ) {
        self.hero = hero
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.granted = granted
        self.reduceMotion = reduceMotion
        self.extraContent = extraContent
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 160, height: 160)
                    .scaleEffect(outerRingScale)
                Circle()
                    .fill(color.opacity(0.05))
                    .frame(width: 200, height: 200)
                    .scaleEffect(innerRingScale)

                heroView
                    .accessibilityHidden(true)

                if granted {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(AppColor.success)
                                .background(
                                    Circle()
                                        .fill(AppColor.bg)
                                        .frame(width: 26, height: 26)
                                )
                                .scaleEffect(checkPop ? 1 : 0.2)
                                .opacity(checkPop ? 1 : 0)
                        }
                        Spacer()
                    }
                    .frame(width: 160, height: 160)
                }
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.52))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            extraContent()

            Spacer()
        }
        .onAppear {
            startPulseIfNeeded()
            syncCheckmark(animated: false)
        }
        .onChange(of: granted) { _, _ in
            syncCheckmark(animated: true)
        }
        .onChange(of: reduceMotion) {
            startPulseIfNeeded()
        }
    }

    @ViewBuilder
    private var heroView: some View {
        switch hero {
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(color)
        case .brandAsset(let name):
            Image(name)
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 88)
                .foregroundStyle(color)
        }
    }

    private var outerRingScale: CGFloat {
        if reduceMotion { return 1 }
        return pulseLarge ? 1.04 : 1
    }

    private var innerRingScale: CGFloat {
        if reduceMotion { return 1 }
        return pulseLarge ? 1.025 : 1
    }

    private func startPulseIfNeeded() {
        guard !reduceMotion else {
            pulseLarge = false
            return
        }
        pulseLarge = false
        withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
            pulseLarge = true
        }
    }

    private func syncCheckmark(animated: Bool) {
        if granted {
            if reduceMotion || !animated {
                checkPop = true
            } else {
                checkPop = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                    checkPop = true
                }
            }
        } else {
            checkPop = false
        }
    }
}

#Preview {
    OnboardingView(viewModel: OnboardingViewModel(
        healthKitService: HealthKitManager(),
        locationService: LocationManager(),
        stravaService: StravaService()
    ))
    .environment(HealthKitManager())
    .environment(LocationManager())
    .environment(StravaService())
    .environment(WhoopService())
}
