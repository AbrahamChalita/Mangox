import SwiftUI

// MARK: - Settings-internal navigation

private enum SettingsRoute: Hashable {
    case riderProfile
    case powerZones
    case heartRate
    case strava
    case whoop
    case integrations
    case indoorTrainer
    case outdoorRide
    case audioHaptics
    case aiCoach
    case mangoxPro
    case gear
    case dataPrivacyHub
}

// MARK: - SettingsView

struct SettingsView: View {
    @State private var viewModel: ProfileViewModel
    @Binding var navigationPath: NavigationPath
    @State private var riderAvatarRefreshToken = UUID()

    init(navigationPath: Binding<NavigationPath>, viewModel: ProfileViewModel) {
        _navigationPath = navigationPath
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let _ = viewModel.ftpGeneration
        let ftp = viewModel.ftp
        let maxHR = HeartRateZone.maxHR
        let stravaConnected = viewModel.stravaConnected
        let whoopConnected = viewModel.whoopConnected
        let isPro = viewModel.isPro

        ZStack {
            AppColor.bg.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        Color.clear.frame(height: 8)

                        identityHeader(ftp: ftp, isPro: isPro)
                            .padding(.bottom, 24)

                        // MARK: Training
                        sectionLabel("Training")
                        settingsGroup {
                            let prefs = RidePreferences.shared
                            let riderProfileValue: String = {
                                var parts: [String] = []
                                let name = prefs.riderDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !name.isEmpty { parts.append(name) }
                                parts.append(prefs.isImperial
                                    ? String(format: "%.0f lb", prefs.riderWeightKg * 2.20462)
                                    : String(format: "%.0f kg", prefs.riderWeightKg))
                                if let age = prefs.riderAge { parts.append("\(age) yrs") }
                                return parts.joined(separator: " · ")
                            }()
                            navRow(
                                icon: "figure.outdoor.cycle", iconColor: AppColor.blue,
                                title: "Rider Profile",
                                value: riderProfileValue,
                                route: .riderProfile
                            )
                            rowDivider
                            navRow(
                                icon: "bolt.fill", iconColor: AppColor.mango,
                                title: "Power & Zones",
                                value: "\(ftp) W FTP",
                                route: .powerZones
                            )
                            rowDivider
                            navRow(
                                icon: "heart.fill", iconColor: AppColor.heartRate,
                                title: "Heart Rate",
                                value: "Max \(maxHR) bpm",
                                route: .heartRate
                            )
                        }

                        // MARK: Connections
                        sectionLabel("Connections")
                            .padding(.top, 24)
                        settingsGroup {
                            navRow(
                                icon: "arrow.triangle.2.circlepath.circle.fill",
                                iconColor: AppColor.strava,
                                title: "Strava",
                                value: stravaConnected ? "Connected" : "Not connected",
                                valueColor: stravaConnected
                                    ? AppColor.success : .white.opacity(0.3),
                                route: .strava
                            )
                            rowDivider
                            navRow(
                                icon: "waveform.path.ecg",
                                iconColor: AppColor.whoop,
                                title: "WHOOP",
                                value: whoopConnected ? "Connected" : "Not connected",
                                valueColor: whoopConnected
                                    ? AppColor.success : .white.opacity(0.3),
                                route: .whoop
                            )
                            rowDivider
                            navRow(
                                icon: "calendar.badge.clock",
                                iconColor: AppColor.blue,
                                title: "Calendar & File Sharing",
                                value: ".ics export · guides",
                                route: .integrations
                            )
                            rowDivider
                            Button {
                                navigationPath.append(AppRoute.outdoorSensorsSetup)
                            } label: {
                                rowContent(
                                    icon: "antenna.radiowaves.left.and.right",
                                    iconColor: AppColor.blue,
                                    title: "Bluetooth Sensors",
                                    value: ""
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // MARK: Ride Settings
                        sectionLabel("Ride Settings")
                            .padding(.top, 24)
                        settingsGroup {
                            navRow(
                                icon: "figure.indoor.cycle", iconColor: .white.opacity(0.6),
                                title: "Indoor Trainer",
                                value: "",
                                route: .indoorTrainer
                            )
                            rowDivider
                            navRow(
                                icon: "map.fill", iconColor: AppColor.success,
                                title: "Outdoor Ride",
                                value: "",
                                route: .outdoorRide
                            )
                            rowDivider
                            navRow(
                                icon: "bicycle",
                                iconColor: .white.opacity(0.55),
                                title: "Gear Labels",
                                value: "",
                                route: .gear
                            )
                            rowDivider
                            navRow(
                                icon: "speaker.wave.2.fill", iconColor: AppColor.yellow,
                                title: "Audio & Haptics",
                                value: "",
                                route: .audioHaptics
                            )
                        }

                        // MARK: App
                        sectionLabel("App")
                            .padding(.top, 24)
                        settingsGroup {
                            navRow(
                                icon: "brain.head.profile",
                                iconColor: AppColor.blue,
                                title: "AI Coach",
                                value: "Provider & model",
                                route: .aiCoach
                            )
                            rowDivider
                            navRow(
                                icon: "bell.badge.fill",
                                iconColor: AppColor.blue,
                                title: "Data, Privacy & Alerts",
                                value: "Export and notifications",
                                route: .dataPrivacyHub
                            )
                            rowDivider
                            mangoxProSettingsRow(isPro: isPro)

                            rowDivider

                            Button {
                                viewModel.resetOnboarding()
                            } label: {
                                HStack(spacing: 14) {
                                    settingsIconBadge("arrow.clockwise", color: .white.opacity(0.5))
                                    Text("Show Onboarding")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)

                            rowDivider

                            HStack(spacing: 14) {
                                settingsIconBadge("info.circle.fill", color: .white.opacity(0.4))
                                Text("Version")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text(
                                    Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                                        as? String ?? "1.0"
                                )
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.32))
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }

                        // TEMPORARY debug entry — remove after story QA
                        sectionLabel("Debug")
                            .padding(.top, 24)
                        settingsGroup {
                            Button {
                                navigationPath.append(AppRoute.storyCardDebug)
                            } label: {
                                HStack(spacing: 14) {
                                    settingsIconBadge("photo.artframe", color: .orange)
                                    Text("Story Card Debug")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.22))
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer().frame(height: 48)
                    }
                }
                .scrollIndicators(.hidden)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDismissToolbar()
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .riderProfile: RiderProfileSettingsView()
                    case .powerZones: PowerZonesSettingsView(viewModel: viewModel)
                    case .heartRate: HeartRateSettingsView(viewModel: viewModel)
                    case .strava: StravaSettingsView(viewModel: viewModel)
                    case .whoop: WhoopSettingsView(viewModel: viewModel)
                    case .integrations: IntegrationsSettingsView()
                    case .indoorTrainer: IndoorTrainerSettingsView()
                    case .outdoorRide: OutdoorRideSettingsView()
                    case .audioHaptics: AudioHapticsSettingsView()
                    case .aiCoach: AICoachSettingsView()
                    case .mangoxPro: MangoxProSettingsView(viewModel: viewModel)
                    case .gear: GearSettingsView()
                    case .dataPrivacyHub: DataPrivacyNotificationsHubView(viewModel: viewModel)
                    }
                }
        }
        .onReceive(NotificationCenter.default.publisher(for: .mangoxRiderProfileAvatarDidChange)) { _ in
            riderAvatarRefreshToken = UUID()
        }
        .sheet(isPresented: $viewModel.showPaywall) {
            PaywallView(viewModel: viewModel.makePaywallViewModel())
        }
    }

    // MARK: - Mangox Pro (root row)

    @ViewBuilder
    private func mangoxProSettingsRow(isPro: Bool) -> some View {
        if isPro {
            Button {
                navigationPath.append(SettingsRoute.mangoxPro)
            } label: {
                mangoxProActiveRowLabel()
            }
            .buttonStyle(.plain)
        } else {
            Button {
                viewModel.presentPaywall()
            } label: {
                rowContent(
                    icon: "crown.fill",
                    iconColor: AppColor.mango,
                    title: "Mangox Pro",
                    value: "Upgrade",
                    valueColor: AppColor.mango
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func mangoxProActiveRowLabel() -> some View {
        let plan = viewModel.storeProPlanKind
        let renewal = viewModel.storeProRenewalDescription
        return HStack(alignment: .center, spacing: 14) {
            settingsIconBadge("crown.fill", color: AppColor.mango)
            VStack(alignment: .leading, spacing: 3) {
                Text("Mangox Pro")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if viewModel.isProDevUnlockOnly {
                    Text("Developer unlock")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.mango.opacity(0.75))
                        .lineLimit(1)
                } else if let renewal {
                    Text(renewal)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                if viewModel.hasStoreSubscription {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.success)
                }
                Text(viewModel.isProDevUnlockOnly ? "Active" : (plan ?? "Active"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.success)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    // MARK: - Identity header

    private func identityHeader(ftp: Int, isPro: Bool) -> some View {
            (HStack(alignment: .center, spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.identityTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    HStack(spacing: 10) {
                        if isPro {
                            Label("Pro", systemImage: "crown.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColor.mango)
                        }
                        Text("\(ftp) W FTP")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20))
    }

    @ViewBuilder
    private var avatarView: some View {
        if RiderProfileAvatarStore.hasLocalAvatar {
            Group {
                if let uiImage = RiderProfileAvatarStore.loadLocalAvatar() {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    avatarPlaceholder
                }
            }
            .id(riderAvatarRefreshToken)
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        } else if let url = viewModel.stravaAvatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarPlaceholder
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        } else {
            avatarPlaceholder
        }
    }

    private var avatarPlaceholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 28))
            .foregroundStyle(.white.opacity(0.35))
            .frame(width: 56, height: 56)
            .background(Color.white.opacity(0.06))
            .clipShape(Circle())
    }

    // MARK: - Row builders

    private func sectionLabel(_ title: String) -> some View {
        MangoxSectionLabel(title: title)
            .mangoxFont(.label)
            .foregroundStyle(.white.opacity(0.32))
            .padding(.bottom, 6)
    }

    private func settingsGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .cardStyle(cornerRadius: 16)
        .padding(.horizontal, MangoxSpacing.page)
    }

    private func navRow(
        icon: String, iconColor: Color,
        title: String,
        value: String,
        valueColor: Color = .white.opacity(0.35),
        route: SettingsRoute
    ) -> some View {
        Button {
            navigationPath.append(route)
        } label: {
            rowContent(
                icon: icon, iconColor: iconColor, title: title, value: value, valueColor: valueColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.isEmpty ? title : "\(title), \(value)")
        .accessibilityHint("Opens \(title) settings")
    }

    private func rowContent(
        icon: String, iconColor: Color,
        title: String,
        value: String,
        valueColor: Color = .white.opacity(0.35)
    ) -> some View {
        HStack(spacing: 14) {
            settingsIconBadge(icon, color: iconColor)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            if !value.isEmpty {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.2))
        }
        .contentShape(Rectangle())
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.white.opacity(0.06))
            .padding(.leading, 60)
    }
}
