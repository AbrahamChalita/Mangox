import SwiftUI
import UIKit
import UserNotifications

struct AICoachSettingsView: View {
    @AppStorage(ChatProviderDefaultsKey.providerKind) private var providerKindRaw = ChatProviderKind
        .mangoxBackend.rawValue
    @AppStorage(ChatProviderDefaultsKey.baseURL) private var providerBaseURL = ""
    @AppStorage(ChatProviderDefaultsKey.model) private var providerModel = ""
    @AppStorage(ChatProviderDefaultsKey.apiKey) private var providerAPIKey = ""

    /// Local drafts avoid writing `UserDefaults` on every keystroke (which was freezing the field, paste, and keyboard).
    @State private var baseURLDraft: String
    @State private var modelDraft: String
    @State private var apiKeyDraft: String
    @State private var connectionPersistTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        _baseURLDraft = State(initialValue: d.string(forKey: ChatProviderDefaultsKey.baseURL) ?? "")
        _modelDraft = State(initialValue: d.string(forKey: ChatProviderDefaultsKey.model) ?? "")
        _apiKeyDraft = State(initialValue: d.string(forKey: ChatProviderDefaultsKey.apiKey) ?? "")
    }

    private var selectedKind: ChatProviderKind {
        ChatProviderKind(rawValue: providerKindRaw) ?? .mangoxBackend
    }

    var body: some View {
        SettingsSubviewShell(title: "AI Coach") {
            MangoxSectionLabel(title: "Provider")
            settingsSubCard {
                VStack(spacing: 0) {
                    providerRow(.mangoxBackend)
                    Divider()
                        .background(Color.white.opacity(0.06))
                    providerRow(.openAICompatible)
                }
            }

            // Provider detail + capability badges
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedKind.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(selectedKind.capabilities.badges, id: \.self) { badge in
                                Text(badge)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(AppColor.mango.opacity(0.9))
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
                    if selectedKind == .openAICompatible {
                        settingsField(
                            title: "API Endpoint URL",
                            text: $baseURLDraft,
                            placeholder: "https://api.openai.com",
                            textContentType: .URL,
                            keyboard: .URL
                        )
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.vertical, 12)
                        settingsField(
                            title: "API Key",
                            text: $apiKeyDraft,
                            placeholder: "sk-...",
                            textContentType: .password,
                            secure: true
                        )
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.vertical, 12)
                        settingsField(
                            title: "Model",
                            text: $modelDraft,
                            placeholder: "gpt-4o-mini",
                            textContentType: nil
                        )
                    } else {
                        settingsField(
                            title: "Backend URL",
                            text: $baseURLDraft,
                            placeholder: "https://mangox-backend-production.up.railway.app",
                            textContentType: .URL,
                            keyboard: .URL
                        )
                    }
                }
                .onChange(of: baseURLDraft) { _, _ in schedulePersistConnectionDrafts() }
                .onChange(of: modelDraft) { _, _ in schedulePersistConnectionDrafts() }
                .onChange(of: apiKeyDraft) { _, _ in schedulePersistConnectionDrafts() }
            }

            // Reset
            settingsSubCard {
                HStack(spacing: 12) {
                    Button {
                        connectionPersistTask?.cancel()
                        providerKindRaw = ChatProviderKind.mangoxBackend.rawValue
                        providerBaseURL = ""
                        providerModel = ""
                        providerAPIKey = ""
                        syncDraftsFromAppStorage()
                    } label: {
                        Text("Reset to Defaults")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(AppColor.mango)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Text("Changes apply to the next message you send.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear { syncDraftsFromAppStorage() }
        .onDisappear { flushConnectionDraftsToAppStorage() }
        .onChange(of: providerKindRaw) { _, _ in syncDraftsFromAppStorage() }
    }

    private func syncDraftsFromAppStorage() {
        baseURLDraft = providerBaseURL
        modelDraft = providerModel
        apiKeyDraft = providerAPIKey
    }

    private func flushConnectionDraftsToAppStorage() {
        connectionPersistTask?.cancel()
        providerBaseURL = baseURLDraft
        providerModel = modelDraft
        providerAPIKey = apiKeyDraft
    }

    private func schedulePersistConnectionDrafts() {
        connectionPersistTask?.cancel()
        connectionPersistTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(340))
            guard !Task.isCancelled else { return }
            providerBaseURL = baseURLDraft
            providerModel = modelDraft
            providerAPIKey = apiKeyDraft
        }
    }

    private func providerRow(_ kind: ChatProviderKind) -> some View {
        let isSelected = selectedKind == kind
        let icon = kind == .mangoxBackend ? "sparkles" : "network"
        let iconColor: Color = kind == .mangoxBackend ? AppColor.mango : AppColor.blue

        return Button {
            providerKindRaw = kind.rawValue
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.65))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AppColor.mango)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

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
            .font(.system(size: 14))
            .foregroundStyle(.white.opacity(0.9))
            .accessibilityLabel(title)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                // FTP hero
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Functional Threshold Power")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                            .tracking(0.5)

                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(ftpDraft)")
                                        .font(.system(size: 40, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.white)
                                    Text("W")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.4))
                                }
                                if hasFTPChanges {
                                    Text("Saved: \(PowerZone.ftp) W")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.28))
                                }
                            }
                            Spacer(minLength: 8)
                            Stepper("", value: $ftpDraft, in: 100...500, step: 5)
                                .labelsHidden()
                        }

                        HStack(spacing: 8) {
                            Button {
                                PowerZone.setFTP(ftpDraft)
                                FitnessSettingsSnapshotRecorder.recordFromCurrentSettings(
                                    source: "ftp_settings")
                            } label: {
                                Text("Apply")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        hasFTPChanges
                                            ? AppColor.success : AppColor.success.opacity(0.3)
                                    )
                                    .clipShape(Capsule())
                            }
                            .disabled(!hasFTPChanges)

                            NavigationLink(value: AppRoute.ftpSetup) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.heart.fill")
                                        .font(.system(size: 11))
                                    Text("Take Test")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(AppColor.orange)
                                .clipShape(Capsule())
                            }

                            Button {
                                showFTPHistory = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 11))
                                    Text("History")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                FitnessThresholdTimelineView()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.rectangle")
                                        .font(.system(size: 11))
                                    Text("Log")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
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
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text(
                                        "\(zone.wattRange.lowerBound)–\(zone.wattRange.upperBound) W"
                                    )
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.38))
                                }
                                Spacer()
                                Text(
                                    zone.pctHigh >= 1.5
                                        ? ">\(Int(zone.pctLow * 100))%"
                                        : "\(Int(zone.pctLow * 100))–\(Int(zone.pctHigh * 100))%"
                                )
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.28))
                            }
                        }
                    }
                }

                // Power display mode
                MangoxSectionLabel(title: "Display")
                settingsSubCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Indoor power readout")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                        Text(
                            "Smoothing applied to the live power number and zone indicator. Recorded samples and NP are always per-second averages."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
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
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        if viewModel.whoopConnected {
                            Toggle(isOn: Binding(
                                get: { viewModel.whoopSyncHeartBaselinesFromWhoop },
                                set: { viewModel.whoopSyncHeartBaselinesFromWhoop = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Use WHOOP for max & resting HR")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.85))
                                    Text(
                                        "Max HR from WHOOP body profile; resting HR from latest recovery. Skipped if you set manual overrides below. Turn off to prefer Apple Health when both are available."
                                    )
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.34))
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
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppColor.whoop)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Connect WHOOP in Connections to sync baselines.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Text(
                            "Enable Apple Health to sync max and resting heart rate from Apple Watch or other Health-connected devices."
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                        Button {
                            Task { await viewModel.requestHealthKitAuthorization() }
                        } label: {
                            Text("Enable Apple Health")
                                .font(.system(size: 13, weight: .semibold))
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
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
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
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.85))
                                Text("Counts toward Activity rings. Skips duplicates if a matching workout already exists.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.35))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(AppColor.mango)

                        Text(
                            "For calendar (.ics), FIT export, and Zwift (.zwo), open Connections > Calendar & File Sharing."
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.28))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }

            // Manual overrides
            MangoxSectionLabel(title: "Manual Overrides")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Enter values below to override what's synced from Health. Leave a field empty to use the Health or estimated value."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max HR")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                            TextField("100–240", text: $manualMaxHRInput)
                                .keyboardType(.numberPad)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Max heart rate")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resting HR")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                            TextField("30–120", text: $manualRestingHRInput)
                                .keyboardType(.numberPad)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Resting heart rate")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            applyOverrides()
                        } label: {
                            Text("Apply")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black)
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
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
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            Text(source)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.22))
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(
                                        viewModel.stravaConnected
                                            ? AppColor.success : .white.opacity(0.2)
                                    )
                                    .frame(width: 6, height: 6)
                                Text(viewModel.stravaConnected ? "Connected" : "Not connected")
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        viewModel.stravaConnected
                                            ? AppColor.success : .white.opacity(0.35))
                            }
                        }
                        Spacer()
                    }

                    if !viewModel.stravaIsConfigured {
                        Text("Strava credentials are not set up in this build.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.32))
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
                                .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    if let err = viewModel.stravaLastError, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange.opacity(0.8))
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(
                                        viewModel.whoopConnected
                                            ? AppColor.success : .white.opacity(0.2)
                                    )
                                    .frame(width: 6, height: 6)
                                Text(viewModel.whoopConnected ? "Connected" : "Not connected")
                                    .font(.system(size: 12))
                                    .foregroundStyle(
                                        viewModel.whoopConnected
                                            ? AppColor.success : .white.opacity(0.35))
                            }
                        }
                        Spacer()
                    }

                    if !viewModel.whoopIsConfigured {
                        Text("WHOOP credentials are not set up in this build.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.32))
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
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                }
                                if let rhr = viewModel.whoopLatestRecoveryRestingHR {
                                    Text("Resting HR (recovery): \(rhr) bpm")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                                if let hrv = viewModel.whoopLatestRecoveryHRV {
                                    Text("HRV (RMSSD): \(hrv) ms")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                                if let maxHR = viewModel.whoopLatestMaxHeartRateFromProfile {
                                    Text("Max HR (WHOOP profile): \(maxHR) bpm")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.38))
                                }
                            }
                            .padding(.bottom, 4)

                            Toggle(isOn: Binding(
                                get: { viewModel.whoopSyncHeartBaselinesFromWhoop },
                                set: { viewModel.whoopSyncHeartBaselinesFromWhoop = $0 }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Sync max & resting HR into zones")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.88))
                                    Text(
                                        "Writes WHOOP profile max HR and recovery resting HR into Mangox heart-rate zones when you don't use manual overrides. You can also manage this in Settings > Heart Rate."
                                    )
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.32))
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
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.white.opacity(0.9))
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
                                .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)

                        Text(
                            "VO₂ max is not available from WHOOP's developer API. Enable Apple Health in Mangox to show VO₂ from Apple Watch or other Health sources."
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.26))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    if let err = viewModel.whoopLastError, !err.isEmpty {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.orange.opacity(0.8))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(
                        "Trainer-reported uses your trainer's internal model. Computed derives speed from power using physics."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
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
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer()
                                Text(String(format: "%.2f m²", prefs.riderCda))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(AppColor.mango)
                            }
                            Text("Drops ≈ 0.28 · Hoods ≈ 0.32 · Upright ≈ 0.35")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.35))
                            Slider(
                                value: $prefs.riderCda,
                                in: RidePreferences.cdaRange, step: 0.01
                            )
                            .tint(AppColor.mango)

                            Text(
                                "At 200W on a flat road, your virtual speed will be \(speedPreviewText)."
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text(value)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Outdoor rides are split automatically by distance along your path.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trim start")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text("\(Int(prefs.gpxPrivacyTrimStartMeters)) m")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColor.mango)
                        }
                        Slider(value: $prefs.gpxPrivacyTrimStartMeters, in: 0...2000, step: 50)
                            .tint(AppColor.mango)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Trim end")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Text("\(Int(prefs.gpxPrivacyTrimEndMeters)) m")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                    Text(
                        "Rolling circumference for Bluetooth speed/cadence sensors. Match your tire size (printed on the sidewall)."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
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
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
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
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
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
                            "Occasional cadence, fueling, and posture nudges while you ride (indoor). Off by default.",
                        isOn: $prefs.rideTipsEnabled
                    )
                    if prefs.rideTipsEnabled {
                        Divider().background(Color.white.opacity(0.06))
                        settingsSubToggle(
                            title: "Spoken tips",
                            subtitle: "Hear short versions of tips through the speaker or headphones",
                            isOn: $prefs.rideTipsAudioEnabled
                        )
                        Divider().background(Color.white.opacity(0.06))
                        HStack {
                            Text("How often")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.6))
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(statusDetail)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.45))
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
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
                            Text(
                                "Pro is enabled on this debug build (scheme env or UserDefaults). App Store billing is unchanged."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.4))
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
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.9))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Calendar export & file-sharing guides (Health lives under Heart Rate)

struct IntegrationsSettingsView: View {
    @State private var icsStartHour = PlanICSPreferences.defaultStartHour
    @State private var icsValarm = PlanICSPreferences.includeWorkoutReminder

    var body: some View {
        SettingsSubviewShell(title: "Calendar & File Sharing") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Training Plan to Calendar (.ics)", systemImage: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    Text(
                        "From your active plan, open the menu and choose Export Calendar (.ics), then import it into Apple Calendar, Google Calendar, or Outlook."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.42))
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Default workout start (local hour)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                            Spacer()
                            Stepper(
                                value: $icsStartHour,
                                in: 0...23,
                                step: 1
                            ) {
                                Text(String(format: "%02d:00", icsStartHour))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .frame(minWidth: 52, alignment: .trailing)
                            }
                            .onChange(of: icsStartHour) { _, v in
                                PlanICSPreferences.defaultStartHour = v
                            }
                        }
                        Toggle(isOn: $icsValarm) {
                            Text("15-minute reminder before each timed workout")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .tint(AppColor.mango)
                        .onChange(of: icsValarm) { _, v in
                            PlanICSPreferences.includeWorkoutReminder = v
                        }
                    }
                }
            }

            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ride files & Zwift workouts", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("After a ride")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(
                            "Open Ride Summary and use Share to export FIT or GPX. AirDrop or open in Garmin Connect, TrainingPeaks, Intervals.icu, and similar apps."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Before an indoor workout")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(
                            "Home > Indoor Ride Setup > Custom Workout > Import .zwo. Mangox maps common Zwift steps (steady state, intervals, ramps, warm up/cool down, free ride, short max efforts) to guided ERG."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            icsStartHour = PlanICSPreferences.defaultStartHour
            icsValarm = PlanICSPreferences.includeWorkoutReminder
        }
    }
}

// MARK: - Goal & season (coach context)

struct GoalEventSettingsView: View {
    @State private var eventName: String = ""
    @State private var phaseLabel: String = ""
    @State private var hasEventDate = false
    @State private var eventDate = Date()

    var body: some View {
        SettingsSubviewShell(title: "Goal & Season") {
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optional context for the AI coach and your own planning—not tied to calendar export.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Goal event name")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                        TextField("e.g. Local fondo, gravel race", text: $eventName)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Goal event name")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Toggle("Set an event date", isOn: $hasEventDate)
                        .tint(AppColor.mango)
                        .font(.system(size: 13, weight: .semibold))

                    if hasEventDate {
                        DatePicker(
                            "Event date",
                            selection: $eventDate,
                            displayedComponents: .date
                        )
                        .tint(AppColor.mango)
                        .foregroundStyle(.white.opacity(0.85))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Training phase label")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                        TextField("e.g. Base, Build, Peak, Taper", text: $phaseLabel)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Training phase label")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Button {
                        MangoxTrainingGoals.eventName = eventName
                        MangoxTrainingGoals.phaseLabel = phaseLabel
                        MangoxTrainingGoals.eventDate = hasEventDate ? eventDate : nil
                    } label: {
                        Text("Save")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            eventName = MangoxTrainingGoals.eventName
            phaseLabel = MangoxTrainingGoals.phaseLabel
            if let d = MangoxTrainingGoals.eventDate {
                hasEventDate = true
                eventDate = d
            } else {
                hasEventDate = false
            }
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Outdoor bike")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                        TextField("e.g. Road / Race bike", text: $prefs.primaryOutdoorBikeName)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Outdoor bike label")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Indoor / trainer")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                        TextField("e.g. Wahoo KICKR", text: $prefs.primaryIndoorBikeName)
                            .textFieldStyle(.plain)
                            .accessibilityLabel("Indoor trainer label")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white.opacity(0.9))
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
                        "Ride files: Ride Summary > Share for FIT, GPX, or TCX. Plan calendar: Connections > Calendar & File Sharing."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Open iOS Settings for Mangox")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.mango)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColor.mango.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
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
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text("Turn on reminders to get evening previews, missed-key nudges, and FTP test prompts.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.34))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Master switch for evening previews, missed-key nudges, and FTP reminders.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.32))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(AppColor.mango)

                    Toggle(isOn: $notifyTomorrow) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Evening preview for tomorrow")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("One reminder with your next plan day after you leave the app.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.32))
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
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.55))
                        .disabled(!MangoxFeatureFlags.allowsTrainingNotifications)
                        .opacity(MangoxFeatureFlags.allowsTrainingNotifications ? 1 : 0.45)
                        .onChange(of: notifyHour) { _, v in
                            TrainingNotificationsPreferences.tomorrowReminderHour = v
                        }
                    }

                    Toggle(isOn: $notifyMissed) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Missed key workout")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("When you open the app after a priority day was missed.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.32))
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
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Nudge if no FTP test in about 90 days.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.32))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    if authStatusText == "Denied in Settings" {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Text("Open iOS notification settings")
                                .font(.system(size: 12, weight: .semibold))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)

                    Text("Extended export adds sample counts, max power, elevation, and completion status per ride.")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.32))
                        .fixedSize(horizontal: false, vertical: true)

                    if let exportError {
                        Text(exportError)
                            .font(.system(size: 11))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppColor.success)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(ok ? AppColor.success : .white.opacity(0.35))
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

/// Rider body weight and birth year — used for W/kg display, AI coaching context, and indoor speed estimation.
struct RiderProfileSettingsView: View {
    @Bindable private var prefs = RidePreferences.shared

    var body: some View {
        SettingsSubviewShell(title: "Rider Profile") {
            MangoxSectionLabel(title: "WEIGHT")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(weightDisplayString)
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(prefs.isImperial ? "lb" : "kg")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Stepper("", value: weightBinding, in: weightRange, step: weightStep)
                            .labelsHidden()
                    }

                    if PowerZone.ftp > 0 {
                        let wkg = Double(PowerZone.ftp) / prefs.riderWeightKg
                        Text(String(format: "%.2f W/kg at %d W FTP", wkg, PowerZone.ftp))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppColor.mango.opacity(0.85))
                    }

                    Text("Also used for indoor speed estimation when computing from power.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MangoxSectionLabel(title: "AGE")
            settingsSubCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        if let age = prefs.riderAge {
                            Text("\(age)")
                                .font(.system(size: 28, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                            Text(" yrs")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.4))
                        } else {
                            Text("Not set")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                        Spacer()
                        HStack(spacing: 8) {
                            if prefs.riderBirthYear != nil {
                                Button {
                                    prefs.riderBirthYear = nil
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.white.opacity(0.35))
                                }
                                .buttonStyle(.plain)
                            }
                            Stepper("", value: riderAgeStepperBinding, in: riderAgeStepRange)
                                .labelsHidden()
                        }
                    }

                    if let year = prefs.riderBirthYear {
                        Text("Born \(year)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }

                    Text("Helps the AI coach tailor recovery periods and intensity recommendations.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Weight helpers (metric / imperial)

    private var weightDisplayString: String {
        prefs.isImperial
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

    /// Stepper bound to **age** so + increases age (earlier birth year). Binding directly to birth year inverted +/− vs the age label.
    private var riderAgeStepRange: ClosedRange<Int> {
        let y = Calendar.current.component(.year, from: .now)
        return (y - 2010)...(y - 1940)
    }

    private var riderAgeStepperBinding: Binding<Int> {
        let currentYear = Calendar.current.component(.year, from: .now)
        return Binding(
            get: {
                if let year = prefs.riderBirthYear {
                    return currentYear - year
                }
                return 30
            },
            set: { prefs.riderBirthYear = currentYear - $0 }
        )
    }
}
