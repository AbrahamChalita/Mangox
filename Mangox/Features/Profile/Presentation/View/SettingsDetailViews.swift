import PhotosUI
import SwiftUI
import UIKit
import UserNotifications

struct AICoachSettingsView: View {
    @AppStorage(ChatProviderDefaultsKey.baseURL) private var providerBaseURL = ""

    @State private var baseURLDraft: String
    @State private var connectionPersistTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        _baseURLDraft = State(initialValue: d.string(forKey: ChatProviderDefaultsKey.baseURL) ?? "")
    }

    var body: some View {
        SettingsSubviewShell(title: "AI Coach") {
            MangoxSectionLabel(title: "Provider")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColor.mango.opacity(0.15))
                                .frame(width: 34, height: 34)
                            Image(systemName: "sparkles")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppColor.mango)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(ChatProviderKind.mangoxBackend.displayName)
                                .settingsPrimary()
                            Text("Always on")
                                .settingsFootnoteMuted()
                        }

                        Spacer()
                    }

                    Text(ChatProviderKind.mangoxBackend.detail)
                        .settingsFootnote()
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ChatProviderKind.mangoxBackend.capabilities.badges, id: \.self) { badge in
                                Text(badge)
                                    .font(MangoxFont.label.value)
                                    .foregroundStyle(AppColor.mango)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(AppColor.mango.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }

            // Connection fields
            MangoxSectionLabel(title: "Connection")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 0) {
                    settingsField(
                        title: "Backend URL",
                        text: $baseURLDraft,
                        placeholder: "https://mangox-backend-production.up.railway.app",
                        textContentType: .URL,
                        keyboard: .URL
                    )
                }
                .onChange(of: baseURLDraft) { _, _ in schedulePersistConnectionDrafts() }
            }

            // Reset
            settingsSubCard {
                HStack(spacing: 12) {
                    Button {
                        connectionPersistTask?.cancel()
                        providerBaseURL = ""
                        syncDraftsFromAppStorage()
                    } label: {
                        Text("Reset to Defaults")
                            .font(MangoxFont.callout.value)
                            .foregroundStyle(AppColor.bg0)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColor.mango)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text("Changes apply to the next message you send.")
                        .settingsFootnoteMuted()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { syncDraftsFromAppStorage() }
        .onDisappear { flushConnectionDraftsToAppStorage() }
    }

    private func syncDraftsFromAppStorage() {
        baseURLDraft = providerBaseURL
    }

    private func flushConnectionDraftsToAppStorage() {
        connectionPersistTask?.cancel()
        providerBaseURL = baseURLDraft
    }

    private func schedulePersistConnectionDrafts() {
        connectionPersistTask?.cancel()
        connectionPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }
            providerBaseURL = baseURLDraft
        }
    }

    private func settingsField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        textContentType: UITextContentType?,
        secure: Bool = false,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(MangoxFont.caption.value)
                .foregroundStyle(AppColor.fg2)

            Group {
                if secure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .lineLimit(1)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textContentType(textContentType)
            .keyboardType(keyboard)
            .mangoxFont(.body)
            .foregroundStyle(AppColor.fg1)
            .accessibilityLabel(title)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AppColor.bg3)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )
        }
    }
}

// MARK: - Power & Zones

struct PowerZonesSettingsView: View {
    let viewModel: ProfileViewModel

    @State private var ftpDraft: Int = PowerZone.ftp
    @State private var showFTPHistory = false

    @Bindable private var prefs = RidePreferences.shared

    private var hasFTPChanges: Bool { ftpDraft != PowerZone.ftp }

    var body: some View {
        FTPRefreshScope {
            SettingsSubviewShell(title: "Power & Zones") {
                // FTP hero — 2×2 action grid so buttons never squeeze on narrow phones
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Threshold power")
                            .mangoxFont(.caption)
                            .foregroundStyle(AppColor.mango)

                        Text("Functional Threshold Power")
                            .font(MangoxFont.title.value)
                            .foregroundStyle(AppColor.fg1)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(ftpDraft)")
                                    .font(MangoxFont.largeValue.value)
                                    .monospacedDigit()
                                    .foregroundStyle(AppColor.fg0)
                                Text("W")
                                    .font(MangoxFont.bodyBold.value)
                                    .foregroundStyle(AppColor.fg3)
                            }
                            Spacer(minLength: 8)
                            Stepper("", value: $ftpDraft, in: 100...500, step: 5)
                                .labelsHidden()
                                .tint(AppColor.mango)
                        }

                        if hasFTPChanges {
                            Text("Saved on device: \(PowerZone.ftp) W")
                                .settingsFootnoteMuted()
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 8),
                                GridItem(.flexible(), spacing: 8),
                            ],
                            spacing: 8
                        ) {
                            Button {
                                PowerZone.setFTP(ftpDraft)
                                FitnessSettingsSnapshotRecorder.recordFromCurrentSettings(
                                    source: "ftp_settings")
                            } label: {
                                Text("Apply")
                                    .font(MangoxFont.callout.value)
                                    .foregroundStyle(AppColor.bg0)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .background(
                                        hasFTPChanges
                                            ? AppColor.success : AppColor.success.opacity(0.35)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                            }
                            .disabled(!hasFTPChanges)

                            NavigationLink(value: AppRoute.ftpSetup) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bolt.heart.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Take test")
                                        .font(MangoxFont.callout.value)
                                }
                                .foregroundStyle(AppColor.bg0)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(AppColor.mango)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                            }

                            Button {
                                showFTPHistory = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("History")
                                        .font(MangoxFont.callout.value)
                                }
                                .foregroundStyle(AppColor.fg1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(AppColor.bg2)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous)
                                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                FitnessThresholdTimelineView()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.rectangle")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Log")
                                        .font(MangoxFont.callout.value)
                                }
                                .foregroundStyle(AppColor.fg1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(AppColor.bg2)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous)
                                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Zone table
                MangoxSectionLabel(title: "Power Zones")
                settingsSubCard {
                    VStack(spacing: 6) {
                        ForEach(PowerZone.zones) { zone in
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(zone.color)
                                    .frame(width: 4, height: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Z\(zone.id) \(zone.name)")
                                        .settingsSecondary()
                                    Text(
                                        "\(zone.wattRange.lowerBound)–\(zone.wattRange.upperBound) W"
                                    )
                                    .settingsMonoCaption()
                                }
                                Spacer()
                                Text(
                                    zone.pctHigh >= 1.5
                                        ? ">\(Int(zone.pctLow * 100))%"
                                        : "\(Int(zone.pctLow * 100))–\(Int(zone.pctHigh * 100))%"
                                )
                                .settingsMonoCaption()
                            }
                        }
                    }
                }

                // Power display mode
                MangoxSectionLabel(title: "Display")
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indoor power readout")
                            .settingsPrimary()
                        Text(
                            "Smoothing applied to the live power number and zone indicator. Recorded samples and NP are always per-second averages."
                        )
                        .settingsFootnoteMuted()
                        Picker("Indoor main power", selection: $prefs.indoorPowerHeroMode) {
                            ForEach(IndoorPowerHeroMode.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
        }
        .onChange(of: viewModel.ftpGeneration) { _, _ in
            ftpDraft = PowerZone.ftp
        }
        .sheet(isPresented: $showFTPHistory) {
            FTPHistoryView()
        }
    }
}

// MARK: - Heart Rate

struct HeartRateSettingsView: View {
    let viewModel: ProfileViewModel
    @State private var manualMaxHRInput = ""
    @State private var manualRestingHRInput = ""
    @State private var statusMessage: String?

    private var hasChanges: Bool {
        let savedMax = HeartRateZone.hasManualMaxHROverride ? "\(HeartRateZone.maxHR)" : ""
        let savedResting =
            HeartRateZone.hasManualRestingHROverride ? "\(HeartRateZone.restingHR)" : ""
        return manualMaxHRInput.trimmingCharacters(in: .whitespacesAndNewlines) != savedMax
            || manualRestingHRInput.trimmingCharacters(in: .whitespacesAndNewlines) != savedResting
    }

    var body: some View {
        SettingsSubviewShell(title: "Heart Rate") {
            // Current values
            settingsSubCard {
                HStack(alignment: .top, spacing: 16) {
                    hrMetric(
                        label: "Max HR",
                        value: "\(HeartRateZone.maxHR)",
                        unit: "bpm",
                        source: maxHRBaselineSource
                    )
                    hrMetric(
                        label: "Resting HR",
                        value: HeartRateZone.hasRestingHR ? "\(HeartRateZone.restingHR)" : "—",
                        unit: HeartRateZone.hasRestingHR ? "bpm" : "",
                        source: restingHRBaselineSource
                    )
                    if let vo2 = viewModel.healthKitVo2Max {
                        hrMetric(
                            label: "VO₂ Max",
                            value: String(format: "%.1f", vo2),
                            unit: "",
                            source: "Health"
                        )
                    } else if viewModel.whoopConnected {
                        hrMetric(
                            label: "VO₂ Max",
                            value: "—",
                            unit: "",
                            source: "WHOOP API has no VO₂"
                        )
                    }
                    Spacer()
                }

                if HeartRateZone.hasRestingHR {
                    Text("HR zones use Karvonen (heart rate reserve) method.")
                        .settingsMicro()
                        .padding(.top, 4)
                }
            }

            if viewModel.whoopIsConfigured {
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColor.whoop)
                            Text(viewModel.whoopConnected ? "WHOOP connected" : "WHOOP not connected")
                                .settingsSecondary()
                        }
                        if viewModel.whoopConnected {
                            Toggle(isOn: Binding(
                                get: { viewModel.whoopSyncHeartBaselinesFromWhoop },
                                set: { viewModel.whoopSyncHeartBaselinesFromWhoop = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use WHOOP for max & resting HR")
                                        .settingsSecondary()
                                    Text(
                                        "Max HR from WHOOP body profile; resting HR from latest recovery. Skipped if you set manual overrides below. Turn off to prefer Apple Health when both are available."
                                    )
                                    .settingsMicro()
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(AppColor.whoop)
                            .onChange(of: viewModel.whoopSyncHeartBaselinesFromWhoop) { _, on in
                                if on {
                                    viewModel.applyHeartBaselinesFromLatestWhoopData()
                                } else {
                                    syncHealthKit()
                                }
                            }

                            NavigationLink {
                                WhoopSettingsView(viewModel: viewModel)
                            } label: {
                                Label("Open WHOOP details", systemImage: "chevron.right.circle")
                                    .font(MangoxFont.caption.value)
                                    .foregroundStyle(AppColor.whoop)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Connect WHOOP in Connections to sync baselines.")
                                .settingsFootnoteMuted()
                        }
                    }
                }
            }

            // HealthKit
            if !viewModel.healthKitIsAuthorized {
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.text.square.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(AppColor.heartRate)
                            Text("Apple Health")
                                .settingsSecondary()
                        }
                        Text(
                            "Enable Apple Health to sync max and resting heart rate from Apple Watch or other Health-connected devices."
                        )
                        .settingsFootnoteMuted()
                        Button {
                            Task { await viewModel.requestHealthKitAuthorization() }
                        } label: {
                            Text("Enable Apple Health")
                                .font(MangoxFont.callout.value)
                                .foregroundStyle(AppColor.success)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(AppColor.success.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColor.success)
                            Text("Apple Health connected")
                                .font(MangoxFont.callout.value)
                                .foregroundStyle(AppColor.fg2)
                        }
                        Toggle(isOn: Binding(
                            get: { viewModel.healthKitSyncWorkoutsToAppleHealth },
                            set: { on in
                                viewModel.healthKitSyncWorkoutsToAppleHealth = on
                                if on {
                                    Task { await viewModel.requestHealthKitAuthorization() }
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save rides to Apple Health")
                                    .settingsSecondary()
                                Text("Counts toward Activity rings. Skips duplicates if a matching workout already exists.")
                                    .settingsMicro()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(AppColor.mango)

                        Text(
                            "Plan to calendar (.ics) options live in Data, Privacy & Alerts. Ride file export (FIT/GPX) is on Ride Summary; Zwift (.zwo) import is in Indoor Ride Setup."
                        )
                        .settingsMicro()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    }
                }
            }

            settingsSubCard {
                NavigationLink {
                    FitnessThresholdTimelineView()
                } label: {
                    Label("FTP + heart rate change log", systemImage: "list.bullet.rectangle")
                        .font(MangoxFont.body.value)
                        .foregroundStyle(AppColor.fg1)
                }
            }

            // Manual overrides
            MangoxSectionLabel(title: "Manual Overrides")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Enter values below to override what's synced from Health. Leave a field empty to use the Health or estimated value."
                    )
                        .settingsFootnoteMuted()

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max HR")
                                .settingsMicro()
                            TextField("100–240", text: $manualMaxHRInput)
                                .keyboardType(.numberPad)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Max heart rate")
                                .mangoxFont(.compactValue)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.fg1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(AppColor.bg3)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.badge.rawValue), style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.badge.rawValue), style: .continuous)
                                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                                )
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resting HR")
                                .settingsMicro()
                            TextField("30–120", text: $manualRestingHRInput)
                                .keyboardType(.numberPad)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Resting heart rate")
                                .mangoxFont(.compactValue)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.fg1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(AppColor.bg3)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.badge.rawValue), style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.badge.rawValue), style: .continuous)
                                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                                )
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            applyOverrides()
                        } label: {
                            Text("Apply")
                                .font(MangoxFont.callout.value)
                                .foregroundStyle(AppColor.bg0)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    hasChanges ? AppColor.success : AppColor.success.opacity(0.3)
                                )
                                .clipShape(Capsule())
                        }
                        .disabled(!hasChanges)

                        Button {
                            clearOverrides()
                        } label: {
                            Text("Use Health / Defaults")
                                .font(MangoxFont.callout.value)
                                .foregroundStyle(AppColor.fg2)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .settingsFootnoteMuted()
                    }
                }
            }
        }
        .task { loadInputs() }
    }

    private var maxHRBaselineSource: String {
        if HeartRateZone.hasManualMaxHROverride { return "Manual" }
        if viewModel.whoopSyncHeartBaselinesFromWhoop, viewModel.whoopConnected, viewModel.whoopLatestMaxHeartRateFromProfile != nil {
            return "WHOOP"
        }
        if viewModel.healthKitMaxHeartRate != nil { return "Health" }
        return "Estimated"
    }

    private var restingHRBaselineSource: String {
        if HeartRateZone.hasManualRestingHROverride { return "Manual" }
        if viewModel.whoopSyncHeartBaselinesFromWhoop, viewModel.whoopConnected, viewModel.whoopLatestRecoveryRestingHR != nil {
            return "WHOOP"
        }
        if viewModel.healthKitRestingHeartRate != nil { return "Health" }
        return HeartRateZone.hasRestingHR ? "Default" : "Not set"
    }

    private func hrMetric(label: String, value: String, unit: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(MangoxFont.micro.value)
                .foregroundStyle(AppColor.fg3)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(MangoxFont.value.value)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.fg0)
                if !unit.isEmpty {
                    Text(unit)
                        .font(MangoxFont.caption.value)
                        .foregroundStyle(AppColor.fg3)
                }
            }
            Text(source)
                .font(MangoxFont.micro.value)
                .foregroundStyle(AppColor.fg4)
        }
    }

    private func loadInputs() {
        manualMaxHRInput = HeartRateZone.hasManualMaxHROverride ? "\(HeartRateZone.maxHR)" : ""
        manualRestingHRInput =
            HeartRateZone.hasManualRestingHROverride ? "\(HeartRateZone.restingHR)" : ""
    }

    private func applyOverrides() {
        let trimMax = manualMaxHRInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimResting = manualRestingHRInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimMax.isEmpty {
            HeartRateZone.clearManualMaxHROverride()
        } else if let v = Int(trimMax), (100...240).contains(v) {
            HeartRateZone.setManualMaxHR(v)
        } else {
            statusMessage = "Max HR must be 100–240 bpm."
            return
        }

        if trimResting.isEmpty {
            HeartRateZone.clearManualRestingHROverride()
        } else if let v = Int(trimResting), (30...120).contains(v) {
            HeartRateZone.setManualRestingHR(v)
        } else {
            statusMessage = "Resting HR must be 30–120 bpm."
            return
        }

        syncHealthKit()
        loadInputs()
        statusMessage = "HR overrides saved."
        FitnessSettingsSnapshotRecorder.recordFromCurrentSettings(source: "hr_settings")
    }

    private func clearOverrides() {
        HeartRateZone.clearManualMaxHROverride()
        HeartRateZone.clearManualRestingHROverride()
        syncHealthKit()
        loadInputs()
        statusMessage = "Using Health / estimated values."
    }

    private func syncHealthKit() {
        viewModel.syncHealthKitToZones()
    }
}

// MARK: - Strava

struct StravaSettingsView: View {
    let viewModel: ProfileViewModel
    @State private var statusMessage: String?

    var body: some View {
        SettingsSubviewShell(title: "Strava") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.strava)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Strava")
                                .settingsPrimary()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(
                                        viewModel.stravaConnected
                                            ? AppColor.success : .white.opacity(0.2)
                                    )
                                    .frame(width: 6, height: 6)
                                Text(viewModel.stravaConnected ? "Connected" : "Not connected")
                                    .font(MangoxFont.caption.value)
                                    .foregroundStyle(
                                        viewModel.stravaConnected
                                            ? AppColor.success : AppColor.fg3)
                            }
                        }
                        Spacer()
                    }

                    if !viewModel.stravaIsConfigured {
                        Text("Strava credentials are not set up in this build.")
                            .settingsFootnoteMuted()
                    } else {
                        Button {
                            if viewModel.stravaConnected { disconnect() } else { connect() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(
                                    systemName: viewModel.stravaConnected
                                        ? "link.circle" : "link.badge.plus"
                                )
                                .font(.system(size: 13))
                                Text(
                                    viewModel.stravaConnected
                                        ? "Disconnect Strava" : "Connect Strava"
                                )
                                .font(MangoxFont.callout.value)
                            }
                            .foregroundStyle(AppColor.fg0)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppColor.strava.opacity(0.22))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(AppColor.strava.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.stravaIsBusy)

                        Text(
                            "Connecting allows Mangox to auto-upload rides. Ride upload details are managed per-activity in the summary screen."
                        )
                        .settingsFootnoteMuted()
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .settingsFootnoteMuted()
                    }
                    if let err = viewModel.stravaLastError, !err.isEmpty {
                        Text(err)
                            .font(MangoxFont.caption.value)
                            .foregroundStyle(AppColor.orange)
                    }
                }
            }
        }
    }

    private func connect() {
        Task {
            do {
                try await viewModel.connectStrava()
                statusMessage =
                    "Connected as \(viewModel.stravaDisplayName ?? "Strava athlete")."
            } catch {
                statusMessage =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func disconnect() {
        viewModel.disconnectStrava()
        statusMessage = "Strava disconnected."
    }
}

// MARK: - WHOOP

struct WhoopSettingsView: View {
    let viewModel: ProfileViewModel
    @State private var statusMessage: String?

    var body: some View {
        SettingsSubviewShell(title: "WHOOP") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 20))
                            .foregroundStyle(AppColor.whoop)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WHOOP")
                                .settingsPrimary()
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(
                                        viewModel.whoopConnected
                                            ? AppColor.success : .white.opacity(0.2)
                                    )
                                    .frame(width: 6, height: 6)
                                Text(viewModel.whoopConnected ? "Connected" : "Not connected")
                                    .font(MangoxFont.caption.value)
                                    .foregroundStyle(
                                        viewModel.whoopConnected
                                            ? AppColor.success : AppColor.fg3)
                            }
                        }
                        Spacer()
                    }

                    if !viewModel.whoopIsConfigured {
                        Text("WHOOP credentials are not set up in this build.")
                            .settingsFootnoteMuted()
                    } else {
                        if viewModel.whoopConnected {
                            VStack(alignment: .leading, spacing: 6) {
                                if let score = viewModel.recoveryScore {
                                    Text(
                                        String(
                                            format: "Latest recovery: %.0f%%",
                                            score
                                        )
                                    )
                                    .font(MangoxFont.callout.value)
                                    .foregroundStyle(AppColor.fg1)
                                }
                                if let rhr = viewModel.whoopLatestRecoveryRestingHR {
                                    Text("Resting HR (recovery): \(rhr) bpm")
                                        .settingsFootnoteMuted()
                                }
                                if let hrv = viewModel.whoopLatestRecoveryHRV {
                                    Text("HRV (RMSSD): \(hrv) ms")
                                        .settingsFootnoteMuted()
                                }
                                if let maxHR = viewModel.whoopLatestMaxHeartRateFromProfile {
                                    Text("Max HR (WHOOP profile): \(maxHR) bpm")
                                        .settingsFootnoteMuted()
                                }
                            }
                            .padding(.bottom, 4)

                            Toggle(isOn: Binding(
                                get: { viewModel.whoopSyncHeartBaselinesFromWhoop },
                                set: { viewModel.whoopSyncHeartBaselinesFromWhoop = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Sync max & resting HR into zones")
                                        .settingsSecondary()
                                    Text(
                                        "Writes WHOOP profile max HR and recovery resting HR into Mangox heart-rate zones when you don't use manual overrides. You can also manage this in Settings > Heart Rate."
                                    )
                                    .settingsMicro()
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .tint(AppColor.whoop)
                            .onChange(of: viewModel.whoopSyncHeartBaselinesFromWhoop) { _, on in
                                if on {
                                    viewModel.applyHeartBaselinesFromLatestWhoopData()
                                }
                            }

                            Button {
                                Task { await refresh() }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 13))
                                    Text("Refresh WHOOP data")
                                        .font(MangoxFont.callout.value)
                                }
                                .foregroundStyle(AppColor.fg0)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(AppColor.whoop.opacity(0.18))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().strokeBorder(AppColor.whoop.opacity(0.35), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.whoopIsBusy)
                        }

                        Button {
                            Task {
                                if viewModel.whoopConnected {
                                    await disconnect()
                                } else {
                                    await connect()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(
                                    systemName: viewModel.whoopConnected
                                        ? "link.circle" : "link.badge.plus"
                                )
                                .font(.system(size: 13))
                                Text(
                                    viewModel.whoopConnected
                                        ? "Disconnect WHOOP" : "Connect WHOOP"
                                )
                                .font(MangoxFont.callout.value)
                            }
                            .foregroundStyle(AppColor.fg0)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(AppColor.whoop.opacity(0.22))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().strokeBorder(AppColor.whoop.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.whoopIsBusy)

                        Text(
                            "Read-only: recovery, sleep, workouts, and strain context from WHOOP. Mangox cannot upload activities to WHOOP via their API - turn on \"Save rides to Apple Health\" in Heart Rate settings if you want WHOOP to import indoor rides through Apple Health."
                        )
                        .settingsFootnoteMuted()
                        .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "VO₂ max is not available from WHOOP's developer API. Enable Apple Health in Mangox to show VO₂ from Apple Watch or other Health sources."
                        )
                        .font(MangoxFont.micro.value)
                        .foregroundStyle(AppColor.fg4)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .settingsFootnoteMuted()
                    }
                    if let err = viewModel.whoopLastError, !err.isEmpty {
                        Text(err)
                            .font(MangoxFont.caption.value)
                            .foregroundStyle(AppColor.orange)
                    }
                }
            }
        }
        .task {
            if viewModel.whoopConnected, viewModel.whoopIsConfigured {
                await refresh()
            }
        }
    }

    private func connect() async {
        await viewModel.connectWhoop()
        if let err = viewModel.whoopLastError, !err.isEmpty {
            statusMessage = err
        } else {
            statusMessage =
                "Connected as \(viewModel.whoopDisplayName ?? "WHOOP member")."
        }
    }

    private func disconnect() async {
        await viewModel.disconnectWhoop()
        statusMessage = "WHOOP disconnected."
    }

    private func refresh() async {
        guard viewModel.whoopConnected else { return }
        await viewModel.refreshWhoop()
        if let err = viewModel.whoopLastError, !err.isEmpty {
            statusMessage = err
        } else {
            statusMessage = "WHOOP data updated."
        }
    }
}

// MARK: - Indoor Trainer

struct IndoorTrainerSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared

    private var speedPreviewText: String {
        let p = 200.0  // watts
        let m = prefs.riderWeightKg + prefs.bikeWeightKg
        let cda = prefs.riderCda
        let crr = 0.004
        let rho = 1.225
        let g = 9.81

        // Solve P = v * (m*g*crr + 0.5*rho*cda*v^2) for v (m/s)
        var v = 8.0
        for _ in 0..<10 {
            let f = v * (m * g * crr + 0.5 * rho * cda * v * v) - p
            let df = m * g * crr + 1.5 * rho * cda * v * v
            v = v - f / df
        }

        let kmh = max(0, v * 3.6)
        return String(format: "%.1f km/h", kmh)
    }

    var body: some View {
        SettingsSubviewShell(title: "Indoor Trainer") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed source")
                        .settingsPrimary()
                    Text(
                        "Trainer-reported uses your trainer's internal model. Computed derives speed from power using physics."
                    )
                        .settingsFootnoteMuted()
                    Picker("Speed source", selection: $prefs.indoorSpeedSource) {
                        ForEach(IndoorSpeedSource.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if prefs.indoorSpeedSource == .computed {
                MangoxSectionLabel(title: "Physics Model")
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 14) {
                        weightRow(label: "Rider weight", value: "\(Int(prefs.riderWeightKg)) kg") {
                            Slider(
                                value: $prefs.riderWeightKg,
                                in: RidePreferences.riderWeightRange, step: 1
                            )
                            .tint(AppColor.mango)
                        }
                        Divider().background(Color.white.opacity(0.06))
                        weightRow(
                            label: "Bike weight",
                            value: "\(String(format: "%.1f", prefs.bikeWeightKg)) kg"
                        ) {
                            Slider(
                                value: $prefs.bikeWeightKg,
                                in: RidePreferences.bikeWeightRange, step: 0.5
                            )
                            .tint(AppColor.mango)
                        }
                        Divider().background(Color.white.opacity(0.06))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Aerodynamic drag (CdA)")
                                    
                        .settingsPrimary()
                                Spacer()
                                Text(String(format: "%.2f m²", prefs.riderCda))
                                    .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.mango)
                            }
                            Text("Drops ≈ 0.28 · Hoods ≈ 0.32 · Upright ≈ 0.35")
                        .settingsFootnoteMuted()
                            Slider(
                                value: $prefs.riderCda,
                                in: RidePreferences.cdaRange, step: 0.01
                            )
                            .tint(AppColor.mango)

                            Text(
                                "At 200W on a flat road, your virtual speed will be \(speedPreviewText)."
                            )
                            
                        .settingsFootnoteMuted()
                        }
                    }
                }
            }

            MangoxSectionLabel(title: "Live Activity")
            settingsSubCard {
                settingsSubToggle(
                    title: "Indoor ride status",
                    subtitle: "Lock Screen and Dynamic Island status during indoor rides.",
                    isOn: $prefs.indoorLiveActivityEnabled
                )
            }

            MangoxSectionLabel(title: "Display")
            settingsSubCard {
                settingsSubToggle(
                    title: "Show Laps",
                    subtitle: "Display lap counter during rides",
                    isOn: $prefs.showLaps
                )
            }
        }
    }

    private func weightRow<Slider: View>(
        label: String, value: String, @ViewBuilder slider: () -> Slider
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                        .settingsPrimary()
                Spacer()
                Text(value)
                    .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.mango)
            }
            slider()
        }
    }
}

// MARK: - Outdoor Ride

struct OutdoorRideSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared

    var body: some View {
        SettingsSubviewShell(title: "Outdoor Ride") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GPS auto-lap")
                        .settingsPrimary()
                    Text("Outdoor rides are split automatically by distance along your path.")
                        .settingsFootnoteMuted()
                    Picker("Interval", selection: $prefs.outdoorAutoLapIntervalMeters) {
                        Text("Off").tag(0.0)
                        Text("500 m").tag(500.0)
                        Text("1 km").tag(1_000.0)
                        Text("2 km").tag(2_000.0)
                        Text("5 km").tag(5_000.0)
                        Text("10 km").tag(10_000.0)
                    }
                    .pickerStyle(.menu)
                    .tint(AppColor.mango)
                }
            }

            settingsSubCard {
                settingsSubToggle(
                    title: "Prioritize navigation",
                    subtitle:
                        "Keeps next turn and route context near the top when the map is hidden on iPhone.",
                    isOn: $prefs.prioritizeNavigationInMaplessBikeComputer
                )
            }

            MangoxSectionLabel(title: "Live Activity")
            settingsSubCard {
                settingsSubToggle(
                    title: "Lock Screen ride status",
                    subtitle:
                        "Lock Screen and Dynamic Island status while recording. Requires Live Activities enabled in Settings › Mangox.",
                    isOn: $prefs.outdoorLiveActivityEnabled
                )
            }

            MangoxSectionLabel(title: "GPX export privacy")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "When you export GPX from Ride Summary, trim the start and end of the GPS track so home, work, or parking stays off the shared file. FIT and TCX exports are unchanged."
                    )
                        .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trim start")
                        .settingsSecondary()
                            Spacer()
                            Text("\(Int(prefs.gpxPrivacyTrimStartMeters)) m")
                                .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.mango)
                        }
                        Slider(value: $prefs.gpxPrivacyTrimStartMeters, in: 0...2000, step: 50)
                            .tint(AppColor.mango)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trim end")
                        .settingsSecondary()
                            Spacer()
                            Text("\(Int(prefs.gpxPrivacyTrimEndMeters)) m")
                                .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.mango)
                        }
                        Slider(value: $prefs.gpxPrivacyTrimEndMeters, in: 0...2000, step: 50)
                            .tint(AppColor.mango)
                    }
                }
            }

            MangoxSectionLabel(title: "Sensors")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Speed sensor wheel size")
                        .settingsPrimary()
                    Text(
                        "Rolling circumference for Bluetooth speed/cadence sensors. Match your tire size (printed on the sidewall)."
                    )
                    
                        .settingsFootnoteMuted()
                    Slider(
                        value: $prefs.cscWheelCircumferenceMeters,
                        in: RidePreferences.cscWheelCircumferenceRange, step: 0.001
                    )
                    .tint(AppColor.mango)
                    HStack {
                        Text("Circumference")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                        Spacer()
                        Text("\(Int(prefs.cscWheelCircumferenceMeters * 1000)) mm")
                            .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.mango)
                    }
                }
            }
        }
    }
}

// MARK: - Audio & Haptics

struct AudioHapticsSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared

    var body: some View {
        SettingsSubviewShell(title: "Audio & Haptics") {
            settingsSubCard {
                VStack(spacing: 12) {
                    settingsSubToggle(
                        title: "Audio Cues",
                        subtitle: "Spoken zone changes and interval cues during guided sessions",
                        isOn: $prefs.stepAudioCueEnabled
                    )
                    Divider().background(Color.white.opacity(0.06))
                    settingsSubToggle(
                        title: "Outdoor Turn Cues",
                        subtitle: "Haptic prompts for navigation and GPX route bends",
                        isOn: $prefs.navigationTurnCuesEnabled
                    )
                }
            }

            MangoxSectionLabel(title: "Cadence")
            settingsSubCard {
                VStack(spacing: 12) {
                    settingsSubToggle(
                        title: "Low Cadence Warning",
                        subtitle:
                            "Nudge when cadence drops below threshold for more than 30 seconds",
                        isOn: $prefs.lowCadenceWarningEnabled
                    )
                    if prefs.lowCadenceWarningEnabled {
                        Divider().background(Color.white.opacity(0.06))
                        HStack {
                            Text("Threshold")
                                .font(MangoxFont.body.value)
                                .foregroundStyle(AppColor.fg2)
                            Spacer()
                            Stepper(
                                "\(prefs.lowCadenceThreshold) rpm",
                                value: Binding(
                                    get: { prefs.lowCadenceThreshold },
                                    set: { prefs.lowCadenceThreshold = max(30, min(120, $0)) }
                                ),
                                in: 30...120, step: 5
                            )
                            .frame(width: 160)
                        }
                    }
                }
            }

            MangoxSectionLabel(title: "Ride tips")
            settingsSubCard {
                VStack(spacing: 12) {
                    settingsSubToggle(
                        title: "Training tips",
                        subtitle:
                            "Occasional cadence, fueling, and posture nudges while you ride (indoor).",
                        isOn: $prefs.rideTipsEnabled
                    )
                    if prefs.rideTipsEnabled {
                        Divider().background(Color.white.opacity(0.06))
                        HStack {
                            Text("Tip categories")
                                .font(MangoxFont.body.value)
                                .foregroundStyle(AppColor.fg2)
                            Spacer()
                            Button {
                                prefs.applyRideTipsEssentialsPreset()
                            } label: {
                                Text("Use Essentials")
                                    .font(MangoxFont.caption.value)
                                    .foregroundStyle(AppColor.mango)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(RideNudgeCategory.allCases, id: \.self) { category in
                            Divider().background(Color.white.opacity(0.06))
                            settingsSubToggle(
                                title: category.label,
                                subtitle: category == .fueling
                                    ? "Fuel and hydration timing reminders"
                                    : category == .cadence
                                    ? "Low-rpm torque relief nudges"
                                    : category == .posture
                                    ? "Upper-body relaxation and form cues"
                                    : category == .recovery
                                    ? "Easy-step guidance during guided recoveries"
                                    : "Extra indoor fluid reminders for warm setups",
                                isOn: Binding(
                                    get: { prefs.rideTipCategoryEnabled(category) },
                                    set: { prefs.setRideTipCategory(category, isEnabled: $0) }
                                )
                            )
                        }
                        Divider().background(Color.white.opacity(0.06))
                        settingsSubToggle(
                            title: "Spoken tips",
                            subtitle: "Hear short versions of tips through the speaker or headphones",
                            isOn: $prefs.rideTipsAudioEnabled
                        )
                        Divider().background(Color.white.opacity(0.06))
                        HStack {
                            Text("How often")
                                .font(MangoxFont.body.value)
                                .foregroundStyle(AppColor.fg2)
                            Spacer()
                            Picker("", selection: $prefs.rideTipsSpacing) {
                                ForEach(RideNudgeSpacing.allCases, id: \.self) { s in
                                    Text(s.label).tag(s)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(AppColor.mango)
                        }
                        Divider().background(Color.white.opacity(0.06))
                        settingsSubToggle(
                            title: "Indoor heat awareness",
                            subtitle: "Extra fluid reminders for hot trainer rooms",
                            isOn: $prefs.rideTipsIndoorHeatAwareness
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Mangox Pro (subscriber status)

struct MangoxProSettingsView: View {
    let viewModel: ProfileViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsSubviewShell(title: "Mangox Pro") {
            settingsSubCard {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColor.success)
                    Text("Mangox Pro is active")
                        .font(MangoxFont.title.value)
                        .foregroundStyle(AppColor.fg1)
                    Text(statusDetail)
                        .font(MangoxFont.body.value)
                        .foregroundStyle(AppColor.fg3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            }

            if viewModel.isProDevUnlockOnly {
                settingsSubCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColor.mango)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Development unlock")
                        .settingsPrimary()
                            Text(
                                "Pro is enabled on this debug build (scheme env or UserDefaults). App Store billing is unchanged."
                            )
                            .settingsFootnote()
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if viewModel.hasStoreSubscription, let url = viewModel.subscriptionManagementURL {
                MangoxSectionLabel(title: "Subscription")
                settingsSubCard {
                    Button {
                        openURL(url)
                    } label: {
                        HStack {
                            Text("Manage in App Store")
                        .settingsPrimary()
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            MangoxSectionLabel(title: "Included with Pro")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 14) {
                    proBenefitLine(icon: "calendar.badge.checkmark", title: "Training plans", subtitle: "Structured and AI-built plans")
                    proBenefitLine(
                        icon: "sparkles",
                        title: "AI Coach",
                        subtitle: "Chat with full ride and plan context; higher limits than the free daily cap"
                    )
                    proBenefitLine(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "Training load",
                        subtitle: "PMC (CTL, ATL, TSB) from your rides—computed on device, not by AI"
                    )
                }
            }
        }
        .task {
            await viewModel.syncPurchases()
        }
    }

    private var statusDetail: String {
        if viewModel.isProDevUnlockOnly {
            return "Full Pro features for development and testing."
        }
        if let plan = viewModel.storeProPlanKind, let renewal = viewModel.storeProRenewalDescription {
            return "\(plan) plan · \(renewal)"
        }
        if let renewal = viewModel.storeProRenewalDescription {
            return renewal
        }
        if let plan = viewModel.storeProPlanKind {
            return "\(plan) plan"
        }
        return "Thank you for supporting Mangox."
    }

    private func proBenefitLine(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(AppColor.success)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .settingsPrimary()
                Text(subtitle)
                    .settingsFootnoteMuted()
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Gear labels

struct GearSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared

    var body: some View {
        SettingsSubviewShell(title: "Gear Labels") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "Labels for your own reference. Strava bike/gear is still chosen when you upload from Ride Summary."
                    )
                        .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Outdoor bike")
                        .settingsMicro()
                        TextField("e.g. Road / Race bike", text: $prefs.primaryOutdoorBikeName)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Outdoor bike label")
                            .mangoxFont(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppColor.bg3)
                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous)
                                    .strokeBorder(AppColor.hair2, lineWidth: 1)
                            )
                            .foregroundStyle(AppColor.fg1)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Indoor / trainer")
                        .settingsMicro()
                        TextField("e.g. Wahoo KICKR", text: $prefs.primaryIndoorBikeName)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Indoor trainer label")
                            .mangoxFont(.body)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(AppColor.bg3)
                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.overlay.rawValue), style: .continuous)
                                    .strokeBorder(AppColor.hair2, lineWidth: 1)
                            )
                            .foregroundStyle(AppColor.fg1)
                    }
                }
            }
        }
    }
}

// MARK: - Data, privacy & alerts

struct DataPrivacyNotificationsHubView: View {
    let viewModel: ProfileViewModel

    @State private var notifyTomorrow = TrainingNotificationsPreferences.tomorrowSessionReminder
    @State private var notifyHour = TrainingNotificationsPreferences.tomorrowReminderHour
    @State private var notifyMissed = TrainingNotificationsPreferences.missedKeyWorkoutNudge
    @State private var notifyFtp = TrainingNotificationsPreferences.ftpTestReminder
    @State private var icsStartHour = PlanICSPreferences.defaultStartHour
    @State private var icsValarm = PlanICSPreferences.includeWorkoutReminder
    @State private var authStatusText = "Loading..."
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var exportError: String?

    var body: some View {
        SettingsSubviewShell(title: "Data, Privacy & Alerts") {
            MangoxSectionLabel(title: "Where rides go")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 10) {
                    rowStatus(
                        title: "Strava",
                        value: viewModel.stravaConnected ? "Connected" : "Not connected",
                        ok: viewModel.stravaConnected
                    )
                    rowStatus(
                        title: "WHOOP",
                        value: viewModel.whoopConnected ? "Connected" : "Not connected",
                        ok: viewModel.whoopConnected
                    )
                    rowStatus(
                        title: "Apple Health",
                        value: viewModel.healthKitSyncWorkoutsToAppleHealth
                            ? "Save rides on"
                            : "Save rides off",
                        ok: viewModel.healthKitSyncWorkoutsToAppleHealth
                    )
                    Text(
                        "Ride files: Ride Summary > Share for FIT, GPX, or TCX."
                    )
                        .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iOS Settings for Mangox")
                            .font(MangoxFont.callout.value)
                            .foregroundStyle(AppColor.mango)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColor.mango.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
                    }
                    .buttonStyle(.plain)
                }
            }

            MangoxSectionLabel(title: "Plan to calendar")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        "From your active plan, open the menu and choose Export Calendar (.ics), then import into Apple Calendar, Google Calendar, or Outlook."
                    )
                    
                        .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Default workout start (local hour)")
                            
                        .settingsFootnote()
                        Spacer()
                        Stepper(
                            value: $icsStartHour,
                            in: 0...23,
                            step: 1
                        ) {
                            Text(String(format: "%02d:00", icsStartHour))
                                .font(MangoxFont.compactValue.value)
                                .monospacedDigit()
                                .foregroundStyle(AppColor.fg1)
                                .frame(minWidth: 52, alignment: .trailing)
                        }
                        .onChange(of: icsStartHour) { _, v in
                            PlanICSPreferences.defaultStartHour = v
                        }
                    }

                    Toggle(isOn: $icsValarm) {
                        Text("15-minute reminder before each timed workout")
                        .settingsFootnote()
                    }
                    .tint(AppColor.mango)
                    .onChange(of: icsValarm) { _, v in
                        PlanICSPreferences.includeWorkoutReminder = v
                    }
                }
            }

            MangoxSectionLabel(title: "Training alerts")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: authStatusIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(authStatusColor)
                        Text("Notifications permission: \(authStatusText)")
                            
                        .settingsSecondary()
                    }
                    Text("Turn on reminders to get evening previews, missed-key nudges, and FTP test prompts.")
                        .settingsMicro()
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle(isOn: Binding(
                        get: { MangoxFeatureFlags.allowsTrainingNotifications },
                        set: { enabled in
                            MangoxFeatureFlags.allowsTrainingNotifications = enabled
                            if enabled {
                                TrainingNotificationsScheduler.refreshDeferredSchedules()
                            } else {
                                TrainingNotificationsScheduler.cancelPendingTrainingReminders()
                            }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scheduled training reminders")
                        .settingsSecondary()
                            Text("Master switch for evening previews, missed-key nudges, and FTP reminders.")
                        .settingsMicro()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AppColor.mango)

                    Toggle(isOn: $notifyTomorrow) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Evening preview for tomorrow")
                        .settingsSecondary()
                            Text("One reminder with your next plan day after you leave the app.")
                        .settingsMicro()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AppColor.mango)
                    .disabled(!MangoxFeatureFlags.allowsTrainingNotifications)
                    .opacity(MangoxFeatureFlags.allowsTrainingNotifications ? 1 : 0.45)
                    .onChange(of: notifyTomorrow) { _, v in
                        TrainingNotificationsPreferences.tomorrowSessionReminder = v
                    }

                    if notifyTomorrow {
                        Stepper(
                            "Local hour: \(String(format: "%02d:00", notifyHour))",
                            value: $notifyHour,
                            in: 0...23,
                            step: 1
                        )
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.fg2)
                        .disabled(!MangoxFeatureFlags.allowsTrainingNotifications)
                        .opacity(MangoxFeatureFlags.allowsTrainingNotifications ? 1 : 0.45)
                        .onChange(of: notifyHour) { _, v in
                            TrainingNotificationsPreferences.tomorrowReminderHour = v
                        }
                    }

                    Toggle(isOn: $notifyMissed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Missed key workout")
                        .settingsSecondary()
                            Text("When you open the app after a priority day was missed.")
                        .settingsMicro()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AppColor.mango)
                    .disabled(!MangoxFeatureFlags.allowsTrainingNotifications)
                    .opacity(MangoxFeatureFlags.allowsTrainingNotifications ? 1 : 0.45)
                    .onChange(of: notifyMissed) { _, v in
                        TrainingNotificationsPreferences.missedKeyWorkoutNudge = v
                    }

                    Toggle(isOn: $notifyFtp) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FTP test reminder")
                        .settingsSecondary()
                            Text("Nudge if no FTP test in about 90 days.")
                        .settingsMicro()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AppColor.mango)
                    .disabled(!MangoxFeatureFlags.allowsTrainingNotifications)
                    .opacity(MangoxFeatureFlags.allowsTrainingNotifications ? 1 : 0.45)
                    .onChange(of: notifyFtp) { _, v in
                        TrainingNotificationsPreferences.ftpTestReminder = v
                    }

                    Button {
                        TrainingNotificationsScheduler.requestAuthorizationIfNeeded()
                    } label: {
                        Text("Request notification permission")
                            .font(MangoxFont.caption.value)
                            .foregroundStyle(AppColor.fg2)
                    }
                    .buttonStyle(.plain)

                    if authStatusText == "Denied in Settings" {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open iOS notification settings")
                                .font(MangoxFont.caption.value)
                                .foregroundStyle(AppColor.mango)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            MangoxSectionLabel(title: "Data export")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Download JSON with ride summaries (no per-second samples) and your threshold change log."
                    )
                    
                        .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Extended export adds sample counts, max power, elevation, and completion status per ride.")
                        .settingsMicro()
                        .fixedSize(horizontal: false, vertical: true)

                    if let exportError {
                        Text(exportError)
                            .font(MangoxFont.caption.value)
                            .foregroundStyle(AppColor.orange)
                    }

                    Button {
                        exportError = nil
                        do {
                            exportURL = try UserDataExportService.buildExportBundle(tier: .standard)
                            showExportShare = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Text("Export JSON...")
                            .font(MangoxFont.callout.value)
                                .foregroundStyle(AppColor.bg0)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
                    }
                    .buttonStyle(.plain)

                    Button {
                        exportError = nil
                        do {
                            exportURL = try UserDataExportService.buildExportBundle(tier: .extended)
                            showExportShare = true
                        } catch {
                            exportError = error.localizedDescription
                        }
                    } label: {
                        Text("Export extended JSON...")
                        .settingsSecondary()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task { await refreshAuthLabel() }
        .sheet(isPresented: $showExportShare) {
            if let exportURL {
                ShareSheet(activityItems: [exportURL])
            }
        }
    }

    private func rowStatus(title: String, value: String, ok: Bool) -> some View {
        HStack {
            Text(title)
                .settingsSecondary()
            Spacer()
            Text(value)
                .font(MangoxFont.caption.value)
                .foregroundStyle(ok ? AppColor.success : AppColor.fg3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var authStatusColor: Color {
        switch authStatusText {
        case "Allowed", "Provisional", "Ephemeral":
            return AppColor.success
        case "Denied in Settings":
            return AppColor.orange
        default:
            return .white.opacity(0.45)
        }
    }

    private var authStatusIcon: String {
        switch authStatusText {
        case "Allowed", "Provisional", "Ephemeral":
            return "checkmark.circle.fill"
        case "Denied in Settings":
            return "xmark.circle.fill"
        default:
            return "bell.badge"
        }
    }

    private func refreshAuthLabel() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            switch s.authorizationStatus {
            case .authorized: authStatusText = "Allowed"
            case .denied: authStatusText = "Denied in Settings"
            case .notDetermined: authStatusText = "Not asked yet"
            case .provisional: authStatusText = "Provisional"
            case .ephemeral: authStatusText = "Ephemeral"
            @unknown default: authStatusText = "Unknown"
            }
        }
    }
}

// MARK: - Rider Profile

/// Rider display identity, body weight, and birth year — used in the app UI, W/kg, AI coaching, and indoor speed.
struct RiderProfileSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared
    @State private var riderProfilePhotoItem: PhotosPickerItem?
    @State private var riderProfileAvatarToken = UUID()
    /// Year-only control — avoids `DatePicker` + optional-year sync fighting the wheel (and the July 1 anchor).
    @State private var draftBirthYear: Int = RiderProfileSettingsView.initialDraftBirthYear()
    /// Defers `onChange(of: draftBirthYear)` until after the first load from `RidePreferences` (avoids writing on appear).
    @State private var birthYearDraftReady = false
    /// When birth year is unset, the wheel still shows a default year — do not persist until the rider moves it.
    @State private var userDidEditBirthYearPicker = false
    @State private var isWeightMasked = true

    var body: some View {
        SettingsSubviewShell(title: "Rider Profile") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Identity")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.mango)

                    HStack(alignment: .top, spacing: 16) {
                        riderAvatarPreview
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(AppColor.hair2, lineWidth: 1))
                            .id(riderProfileAvatarToken)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Display name")
                                .font(MangoxFont.label.value)
                                .foregroundStyle(AppColor.fg3)
                                .tracking(1.2)
                                .textCase(.uppercase)

                            TextField("Your name", text: $prefs.riderDisplayName)
                                .textContentType(.name)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .mangoxFont(.bodyBold)
                                .foregroundStyle(AppColor.fg1)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .background(AppColor.bg3)
                                .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous)
                                        .strokeBorder(AppColor.hair2, lineWidth: 1)
                                )

                            HStack(spacing: 8) {
                                PhotosPicker(selection: $riderProfilePhotoItem, matching: .images) {
                                    Label("Photo", systemImage: "photo")
                                        .font(MangoxFont.callout.value)
                                        .foregroundStyle(AppColor.bg0)
                                        .labelStyle(.titleAndIcon)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(AppColor.mango)
                                        .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                                }
                                .buttonStyle(MangoxPressStyle())

                                if RiderProfileAvatarStore.hasLocalAvatar {
                                    Button {
                                        RiderProfileAvatarStore.clearLocalAvatar()
                                        riderProfileAvatarToken = UUID()
                                    } label: {
                                        Text("Remove")
                                            .font(MangoxFont.callout.value)
                                            .foregroundStyle(AppColor.fg2)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(AppColor.bg2)
                                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous)
                                                    .strokeBorder(AppColor.hair2, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(MangoxPressStyle())
                                }
                            }
                        }
                    }

                    Text("Shown on Home, ride summaries, and share cards. Strava can still override when you connect.")
                        .settingsFootnoteMuted()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsSubCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Body & age")
                        .mangoxFont(.caption)
                        .foregroundStyle(AppColor.mango)

                    riderWeightBlock

                    Rectangle()
                        .fill(AppColor.hair)
                        .frame(height: 1)

                    riderBirthBlock
                }
            }
        }
        .onAppear {
            birthYearDraftReady = false
            applyBirthYearDraftFromPreferences()
            Task { @MainActor in
                await Task.yield()
                birthYearDraftReady = true
            }
        }
        .onChange(of: draftBirthYear) { _, newYear in
            guard birthYearDraftReady else { return }
            let defaultYear = Calendar.current.component(.year, from: Date()) - 30
            if prefs.riderBirthYear == nil, !userDidEditBirthYearPicker, newYear == defaultYear { return }
            userDidEditBirthYearPicker = true
            if prefs.riderBirthYear != newYear {
                prefs.riderBirthYear = newYear
            }
        }
        .onChange(of: riderProfilePhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    try? RiderProfileAvatarStore.saveLocalAvatar(uiImage)
                    await MainActor.run {
                        riderProfileAvatarToken = UUID()
                        riderProfilePhotoItem = nil
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var riderAvatarPreview: some View {
        if let img = RiderProfileAvatarStore.loadLocalAvatar() {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                AppColor.bg3
                Image(systemName: "person.fill")
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(AppColor.fg3)
            }
        }
    }

    private var riderWeightBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Body weight")
                    .font(MangoxFont.label.value)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.2)
                    .textCase(.uppercase)
                Spacer()
                Button {
                    isWeightMasked.toggle()
                } label: {
                    Image(systemName: isWeightMasked ? "eye.slash" : "eye")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColor.fg3)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weightDisplayString)
                    .font(MangoxFont.largeValue.value)
                    .monospacedDigit()
                    .foregroundStyle(AppColor.fg0)
                Text(prefs.isImperial ? "lb" : "kg")
                    .font(MangoxFont.bodyBold.value)
                    .foregroundStyle(AppColor.fg3)
            }

            Slider(value: weightBinding, in: weightRange, step: weightStep)
                .tint(AppColor.mango)

            HStack {
                Text("\(Int(weightRange.lowerBound)) \(prefs.isImperial ? "lb" : "kg")")
                Spacer()
                Text("\(Int(weightRange.upperBound)) \(prefs.isImperial ? "lb" : "kg")")
            }
            .font(MangoxFont.caption.value)
            .foregroundStyle(AppColor.fg3)

            if PowerZone.ftp > 0 {
                Text(
                    String(
                        format: "%.2f W/kg · %d W FTP",
                        Double(PowerZone.ftp) / prefs.riderWeightKg,
                        PowerZone.ftp
                    )
                )
                .font(MangoxFont.caption.value)
                .monospacedDigit()
                .foregroundStyle(AppColor.mango)
            }

            Text("Used for W/kg, coaching context, and indoor speed from power.")
                .settingsFootnoteMuted()
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var riderBirthBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Birth year")
                .font(MangoxFont.label.value)
                .foregroundStyle(AppColor.fg3)
                .tracking(1.2)
                .textCase(.uppercase)

            Text(birthDateSummary)
                .font(MangoxFont.compactValue.value)
                .foregroundStyle(AppColor.fg1)

            Picker("Birth year", selection: $draftBirthYear) {
                ForEach(birthYearPickerValues, id: \.self) { y in
                    Text(String(y)).tag(y)
                }
            }
            .labelsHidden()
            .pickerStyle(.wheel)
            .tint(AppColor.cadence)
            .frame(maxWidth: .infinity)
            .frame(height: 148)
            .clipped()
            .background(AppColor.bg2)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous)
                    .strokeBorder(AppColor.hair2, lineWidth: 1)
            )

            HStack(alignment: .top, spacing: 12) {
                Text("Helps the AI coach tailor recovery and intensity. Only the year is stored.")
                    .settingsFootnoteMuted()
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if prefs.riderBirthYear != nil {
                    Button {
                        userDidEditBirthYearPicker = false
                        prefs.riderBirthYear = nil
                        applyBirthYearDraftFromPreferences()
                    } label: {
                        Text("Clear")
                            .font(MangoxFont.callout.value)
                            .foregroundStyle(AppColor.cadence)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppColor.cadence.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: CGFloat(MangoxRadius.button.rawValue), style: .continuous))
                    }
                    .buttonStyle(MangoxPressStyle())
                }
            }
        }
    }

    // MARK: - Birth year picker

    private static func initialDraftBirthYear() -> Int {
        let cal = Calendar.current
        let now = Date()
        let defaultYear = cal.component(.year, from: now) - 30
        let stored = RidePreferences.shared.riderBirthYear
        let maxY = cal.component(.year, from: now) - 16
        let y = stored ?? defaultYear
        return min(max(y, 1940), maxY)
    }

    private var birthYearPickerValues: [Int] {
        let cal = Calendar.current
        let maxY = cal.component(.year, from: .now) - 16
        return Array((1940...maxY).reversed())
    }

    private func applyBirthYearDraftFromPreferences() {
        let cal = Calendar.current
        let defaultYear = cal.component(.year, from: Date()) - 30
        let maxY = cal.component(.year, from: Date()) - 16
        let y = prefs.riderBirthYear ?? defaultYear
        draftBirthYear = min(max(y, 1940), maxY)
        userDidEditBirthYearPicker = prefs.riderBirthYear != nil
    }

    private var birthDateSummary: String {
        guard let year = prefs.riderBirthYear else { return "Not set" }
        let age = max(0, Calendar.current.component(.year, from: .now) - year)
        return "\(year) · age \(age)"
    }

    // MARK: - Weight helpers (metric / imperial)

    private var weightDisplayString: String {
        if isWeightMasked {
            return "***"
        }
        return prefs.isImperial
            ? String(format: "%.0f", prefs.riderWeightKg * 2.20462)
            : String(format: "%.0f", prefs.riderWeightKg)
    }

    private var weightRange: ClosedRange<Double> {
        prefs.isImperial ? (66.0...440.0) : (30.0...200.0)  // lbs or kg
    }

    private var weightStep: Double { prefs.isImperial ? 1.0 : 0.5 }

    /// A binding that reads/writes in display units but stores internally in kg.
    private var weightBinding: Binding<Double> {
        Binding(
            get: { prefs.isImperial ? (prefs.riderWeightKg * 2.20462).rounded() : prefs.riderWeightKg },
            set: { newVal in
                prefs.riderWeightKg = prefs.isImperial ? (newVal / 2.20462) : newVal
            }
        )
    }
}
