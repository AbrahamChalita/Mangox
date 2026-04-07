import SwiftUI

// MARK: - Fitness (HR, FTP, HealthKit)

/// Heart rate limits, FTP, and HealthKit — training baselines for zones.
struct FitnessZonesProfileCard: View {
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(FTPRefreshTrigger.self) private var ftpRefresh

    @State private var manualMaxHRInput = ""
    @State private var manualRestingHRInput = ""
    @State private var manualOverrideStatus: String?
    @State private var ftpDraft: Int = PowerZone.ftp

    private var hasHRChanges: Bool {
        let currentMax = HeartRateZone.hasManualMaxHROverride ? "\(HeartRateZone.maxHR)" : ""
        let currentResting =
            HeartRateZone.hasManualRestingHROverride ? "\(HeartRateZone.restingHR)" : ""
        return manualMaxHRInput.trimmingCharacters(in: .whitespacesAndNewlines) != currentMax
            || manualRestingHRInput.trimmingCharacters(in: .whitespacesAndNewlines)
                != currentResting
    }

    private var hasFTPChanges: Bool { ftpDraft != PowerZone.ftp }

    @State private var isEditingHealthData = false
    @State private var showFTPHistory = false

    var body: some View {
        FTPRefreshScope {
            fitnessCard
        }
        .task {
            syncHealthKitToZones()
            loadManualOverrideInputs()
            ftpDraft = PowerZone.ftp
        }
        .onChange(of: ftpRefresh.generation) { _, _ in
            ftpDraft = PowerZone.ftp
        }
        .sheet(isPresented: $showFTPHistory) {
            FTPHistoryView()
        }
        .keyboardDismissToolbar()
    }

    private var fitnessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.heartRate)
                Text("Heart rate & power")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                if healthKitManager.isAuthorized {
                    HStack(spacing: 4) {
                        Text("Health")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.3))
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColor.success)
                    }
                } else {
                    Text("Defaults")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.25))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isEditingHealthData.toggle()
                    }
                    if isEditingHealthData {
                        loadManualOverrideInputs()
                    } else {
                        manualOverrideStatus = nil
                    }
                } label: {
                    Image(
                        systemName: isEditingHealthData ? "checkmark.circle.fill" : "pencil.circle"
                    )
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isEditingHealthData ? AppColor.success : .white.opacity(0.55))
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 16) {
                healthMetric(
                    label: "Max HR",
                    value: "\(HeartRateZone.maxHR)",
                    unit: "bpm",
                    source: HeartRateZone.hasManualMaxHROverride
                        ? "Manual"
                        : (healthKitManager.maxHeartRate != nil ? "Health" : "Estimated")
                )
                healthMetric(
                    label: "Resting HR",
                    value: HeartRateZone.hasRestingHR ? "\(HeartRateZone.restingHR)" : "—",
                    unit: HeartRateZone.hasRestingHR ? "bpm" : "",
                    source: HeartRateZone.hasManualRestingHROverride
                        ? "Manual"
                        : (healthKitManager.restingHeartRate != nil ? "Health" : "Not set")
                )
                if let vo2 = healthKitManager.vo2Max {
                    healthMetric(
                        label: "VO2 Max",
                        value: String(format: "%.1f", vo2),
                        unit: "",
                        source: "Health"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("FTP")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.2)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(ftpDraft) W")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("Saved: \(PowerZone.ftp) W for power zones")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.28))
                    }
                    Spacer(minLength: 8)
                    Stepper("", value: $ftpDraft, in: 100...500, step: 5)
                        .labelsHidden()
                }
                HStack(spacing: 8) {
                    Button {
                        PowerZone.ftp = ftpDraft
                    } label: {
                        Text("Apply")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                hasFTPChanges ? AppColor.success : AppColor.success.opacity(0.3)
                            )
                            .clipShape(Capsule())
                    }
                    .disabled(!hasFTPChanges)

                    NavigationLink(value: AppRoute.ftpSetup) {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.heart.fill")
                                .font(.system(size: 11))
                            Text("Take Test")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
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
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)

            if HeartRateZone.hasRestingHR {
                Text("HR zones use Karvonen (heart rate reserve) method")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))
            }

            if isEditingHealthData {
                VStack(alignment: .leading, spacing: 8) {
                    Text("MANUAL HR OVERRIDES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.35))
                        .tracking(1.2)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max HR")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                            TextField("100-240", text: $manualMaxHRInput)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resting HR")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.35))
                            TextField("30-120", text: $manualRestingHRInput)
                                .keyboardType(.numberPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            applyManualOverrides()
                        } label: {
                            Text("Apply")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    hasHRChanges ? AppColor.success : AppColor.success.opacity(0.3)
                                )
                                .clipShape(Capsule())
                        }
                        .disabled(!hasHRChanges)
                        Button {
                            clearManualOverrides()
                        } label: {
                            Text("Use HealthKit/Defaults")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }

                    if let manualOverrideStatus {
                        Text(manualOverrideStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.top, 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !healthKitManager.isAuthorized {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(
                            "Enable HealthKit for accurate HR zones from Apple Watch or Health-synced devices."
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.25))
                    }
                    Button {
                        Task { await healthKitManager.requestAuthorization() }
                    } label: {
                        Text("Enable HealthKit")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.success)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(AppColor.success.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private func healthMetric(label: String, value: String, unit: String, source: String)
        -> some View
    {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            Text(source)
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.2))
        }
    }

    private func syncHealthKitToZones() {
        let effectiveMax = healthKitManager.effectiveMaxHR
        if effectiveMax > 0, !HeartRateZone.hasManualMaxHROverride {
            HeartRateZone.maxHR = effectiveMax
        }
        if let resting = healthKitManager.restingHeartRate,
            resting > 0,
            !HeartRateZone.hasManualRestingHROverride
        {
            HeartRateZone.restingHR = resting
        }
    }

    private func loadManualOverrideInputs() {
        manualMaxHRInput = HeartRateZone.hasManualMaxHROverride ? "\(HeartRateZone.maxHR)" : ""
        manualRestingHRInput =
            HeartRateZone.hasManualRestingHROverride ? "\(HeartRateZone.restingHR)" : ""
    }

    private func applyManualOverrides() {
        let trimmedMax = manualMaxHRInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResting = manualRestingHRInput.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedMax.isEmpty {
            HeartRateZone.clearManualMaxHROverride()
        } else if let max = Int(trimmedMax), (100...240).contains(max) {
            HeartRateZone.setManualMaxHR(max)
        } else {
            manualOverrideStatus = "Max HR must be between 100 and 240 bpm."
            return
        }

        if trimmedResting.isEmpty {
            HeartRateZone.clearManualRestingHROverride()
        } else if let resting = Int(trimmedResting), (30...120).contains(resting) {
            HeartRateZone.setManualRestingHR(resting)
        } else {
            manualOverrideStatus = "Resting HR must be between 30 and 120 bpm."
            return
        }

        syncHealthKitToZones()
        loadManualOverrideInputs()
        manualOverrideStatus = "Manual HR overrides saved."
    }

    private func clearManualOverrides() {
        HeartRateZone.clearManualMaxHROverride()
        HeartRateZone.clearManualRestingHROverride()
        syncHealthKitToZones()
        loadManualOverrideInputs()
        manualOverrideStatus = "Manual HR overrides cleared."
    }
}

// MARK: - Strava

/// Strava OAuth — uploads and account link, separate from training baselines.
struct StravaConnectionCard: View {
    @Environment(StravaService.self) private var stravaService

    @State private var stravaStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.discord)
                Text("Strava")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Circle()
                    .fill(stravaService.isConnected ? AppColor.success : AppColor.discord)
                    .frame(width: 8, height: 8)
                Text(stravaService.isConnected ? "Connected" : "Not connected")
                    .font(.system(size: 9))
                    .foregroundStyle(
                        stravaService.isConnected ? AppColor.success : AppColor.discord)
            }

            if !stravaService.isConfigured {
                Text("Set STRAVA_CLIENT_ID and STRAVA_CLIENT_SECRET in build settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.32))
            } else {
                Button {
                    if stravaService.isConnected { disconnectStrava() } else { connectStrava() }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: stravaService.isConnected
                                ? "link.circle" : "link.badge.plus"
                        )
                        .font(.system(size: 12, weight: .semibold))
                        Text(stravaService.isConnected ? "Disconnect Strava" : "Connect Strava")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColor.discord.opacity(0.24))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(AppColor.discord.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(stravaService.isBusy)

                Text("Account-level setting: ride summaries handle upload details.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if let stravaStatus {
                Text(stravaStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.35))
            }
            if let serviceError = stravaService.lastError, !serviceError.isEmpty {
                Text(serviceError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.8))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(AppOpacity.cardBorder), lineWidth: 1)
        )
    }

    private func connectStrava() {
        Task {
            do {
                try await stravaService.connect()
                stravaStatus =
                    "Connected as \(stravaService.athleteDisplayName ?? "Strava athlete")."
            } catch {
                stravaStatus =
                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func disconnectStrava() {
        stravaService.disconnect()
        stravaStatus = "Strava disconnected."
    }
}
