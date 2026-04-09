import SwiftUI

struct FTPTestView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(DataSourceCoordinator.self) private var dataSource
    @Environment(HealthKitManager.self) private var healthKitManager
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Binding var navigationPath: NavigationPath

    @State private var manager = FTPTestManager()
    @State private var showEndConfirmation = false
    @State private var showApplyConfirmation = false
    @State private var showHistory = false

    private var metrics: CyclingMetrics {
        var m = CyclingMetrics(lastUpdate: Date())
        m.power = dataSource.power
        m.cadence = dataSource.cadence
        m.speed = dataSource.speed
        m.heartRate = dataSource.heartRate
        m.totalDistance = dataSource.totalDistance
        m.hrSource = bleManager.metrics.hrSource
        return m
    }

    var body: some View {
        FTPRefreshScope {
            ZStack {
                Color(red: 0.03, green: 0.04, blue: 0.06)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    GeometryReader { geo in
                        let isWide = geo.size.width > 700
                        ScrollView {
                            if isWide {
                                HStack(alignment: .top, spacing: 16) {
                                    VStack(spacing: 14) {
                                        phaseCard
                                        powerCards
                                    }
                                    .frame(maxWidth: .infinity)

                                    VStack(spacing: 14) {
                                        protocolCard
                                        if !manager.recentEvents.isEmpty {
                                            trainerActivityCard
                                        }
                                    }
                                    .frame(width: 260)
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 16)
                            } else {
                                VStack(spacing: 14) {
                                    phaseCard
                                    powerCards
                                    protocolCard
                                    if !manager.recentEvents.isEmpty {
                                        trainerActivityCard
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 16)
                            }
                        }
                    }

                    controls
                }
            }
        }
        .onAppear {
            dataSource.updateActiveSource()
            manager.configure(bleManager: bleManager, dataSource: dataSource)
        }
        .onDisappear {
            manager.tearDown()
        }
        .onChange(of: manager.state) { _, newState in
            if newState == .completed {
                HapticManager.shared.ftpTestCompleted()
            }
        }
        .navigationTitle("FTP Test")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(manager.state == .running || manager.state == .paused)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("FTP Test")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text("20-minute protocol")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                if manager.state == .running || manager.state == .paused {
                    Button {
                        showEndConfirmation = true
                    } label: {
                        Label("Back", systemImage: "chevron.backward")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("FTP test history")
            }
        }
        .alert("End FTP Test?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Test", role: .destructive) {
                manager.reset()
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            }
        } message: {
            Text("You will lose current FTP test progress.")
        }
        .sheet(isPresented: $showHistory) {
            FTPHistoryView()
        }
        .alert("Apply New FTP", isPresented: $showApplyConfirmation) {
            Button("Not Now", role: .cancel) {}
            Button("Apply") {
                manager.applyEstimatedFTP()
                navigationPath = NavigationPath()
            }
        } message: {
            Text("Set FTP to \(manager.estimatedFTP) W and return home?")
        }
    }

    @ViewBuilder
    private var phaseCard: some View {
        let currentZone = PowerZone.zone(for: manager.displayPower)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(manager.currentPhase.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.6)

                Spacer()

                // Live trainer mode badge
                if manager.state == .running || manager.state == .paused {
                    trainerModeBadge
                }

                Text("Elapsed \(manager.formattedElapsed)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }

            Text(manager.currentPhase.detail)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))

            // Target power for this phase
            HStack(spacing: 6) {
                Image(
                    systemName: manager.currentPhase.ergTargetPercent != nil
                        ? "target" : "flame.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(manager.currentPhase.targetZone?.color ?? AppColor.orange)
                Text(manager.currentPhase.targetLabel)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(manager.currentPhase.targetZone?.color ?? AppColor.orange)
            }

            Text(manager.formattedRemaining)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            ProgressView(value: manager.phaseProgress)
                .tint(AppColor.mango)

            // Target vs current comparison (ERG phases only)
            if manager.state == .running || manager.state == .paused,
                let targetWatts = manager.currentERGTarget
            {
                let delta = manager.displayPower - targetWatts
                let absDelta = abs(delta)
                let deltaColor: Color =
                    absDelta <= 5
                    ? AppColor.success
                    : absDelta <= 15 ? AppColor.yellow : AppColor.orange

                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        // Target
                        VStack(spacing: 2) {
                            Text("TARGET")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.3))
                                .tracking(1)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(targetWatts)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.5))
                                Text("W")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // Delta
                        VStack(spacing: 1) {
                            Text("\(delta > 0 ? "+" : "")\(delta)W")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(deltaColor)
                        }
                        .frame(width: 56)

                        // Actual
                        VStack(spacing: 2) {
                            Text("ACTUAL")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.3))
                                .tracking(1)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text("\(manager.displayPower)")
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundStyle(currentZone.color)
                                Text("W")
                                    .font(.system(size: 10))
                                    .foregroundStyle(currentZone.color.opacity(0.5))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Compliance bar
                    GeometryReader { barGeo in
                        let maxScale = Double(targetWatts) * 1.4
                        let targetFrac = min(Double(targetWatts) / maxScale, 1.0)
                        let actualFrac = min(max(Double(manager.displayPower) / maxScale, 0), 1.0)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.06))

                            RoundedRectangle(cornerRadius: 3)
                                .fill(deltaColor.opacity(0.35))
                                .frame(width: barGeo.size.width * actualFrac)

                            // Target marker
                            RoundedRectangle(cornerRadius: 1)
                                .fill(.white.opacity(0.5))
                                .frame(width: 2)
                                .offset(x: barGeo.size.width * targetFrac - 1)
                        }
                    }
                    .frame(height: 8)
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // Running FTP estimate & pacing (shown during the 20-min test block)
            if manager.state == .running || manager.state == .paused,
                manager.currentPhase.id == 6,
                manager.runningTwentyMinAvg > 0
            {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColor.yellow)
                        Text("EST. FTP")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.25))
                            .tracking(1)
                        Text("~\(Int((manager.runningTwentyMinAvg * 0.95).rounded()))W")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.yellow)
                        Spacer()
                        Text("\(Int(manager.testBlockProgress * 100))%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }

                    // Pacing indicator (after first minute of test data)
                    if manager.testBlockProgress > 0.05 {
                        let ratio = Double(manager.displayPower) / manager.runningTwentyMinAvg
                        let pacingLabel =
                            ratio > 1.08
                            ? "Above avg — watch pacing"
                            : ratio >= 0.95 ? "Steady pace" : "Below avg — dig deeper"
                        let pacingColor =
                            ratio > 1.08
                            ? AppColor.orange
                            : ratio >= 0.95 ? AppColor.success : AppColor.heartRate
                        let pacingIcon =
                            ratio > 1.08
                            ? "arrow.up.right"
                            : ratio >= 0.95 ? "arrow.right" : "arrow.down.right"

                        HStack(spacing: 6) {
                            Image(systemName: pacingIcon)
                                .font(.system(size: 9))
                                .foregroundStyle(pacingColor)
                            Text(pacingLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(pacingColor)
                            Spacer()
                            Text(
                                "\(manager.displayPower)W vs \(Int(manager.runningTwentyMinAvg.rounded()))W avg"
                            )
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            // HR & Cadence row
            if manager.state == .running || manager.state == .paused {
                HStack(spacing: 16) {
                    if metrics.heartRate > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColor.heartRate)
                            Text("\(metrics.heartRate)")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppColor.heartRate)
                            Text("bpm")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }

                    if metrics.cadence > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColor.blue)
                            Text("\(Int(metrics.cadence))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppColor.blue)
                            Text("rpm")
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }

                    Spacer()
                }
            }

            // Zone bar — shows current power relative to all zones
            if manager.state == .running || manager.state == .paused {
                VStack(spacing: 6) {
                    // Current zone label
                    HStack {
                        Text("Z\(currentZone.id) \(currentZone.name)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(currentZone.color)
                        Spacer()
                        Text("\(manager.displayPower) W")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    // Zone bar visualization
                    GeometryReader { geo in
                        let totalWidth = geo.size.width
                        HStack(spacing: 1) {
                            ForEach(PowerZone.zones) { zone in
                                let zoneFraction = (zone.pctHigh - zone.pctLow) / 1.5
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(
                                            zone.color.opacity(
                                                zone.id == currentZone.id ? 0.5 : 0.15)
                                        )
                                        .frame(height: 6)
                                }
                                .frame(width: totalWidth * zoneFraction)
                            }
                        }

                        // Power position indicator
                        let pct = min(
                            Double(manager.displayPower) / (Double(PowerZone.ftp) * 1.5), 1.0)
                        Circle()
                            .fill(currentZone.color)
                            .frame(width: 8, height: 8)
                            .shadow(color: currentZone.color.opacity(0.6), radius: 3)
                            .offset(x: max(0, totalWidth * pct - 4), y: -1)
                    }
                    .frame(height: 8)
                }
                .padding(.top, 4)
            }

            if !manager.canStart {
                Text("Connect a trainer to start the FTP protocol.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.orange)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .animation(.easeInOut(duration: accessibilityReduceMotion ? 0 : 0.3), value: currentZone.id)

        // Phase transition warning overlay
        if let warning = manager.pendingPhaseWarning {
            phaseWarningOverlay(warning: warning)
        }

        if let coachText = manager.dynamicCoachingText, manager.state == .running {
            Text(coachText)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.mango)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(AppColor.mango.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(AppColor.mango.opacity(0.3), lineWidth: 1)
                )
                .padding(.top, 4)
        }
    }

    private var powerCards: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MetricCardView(
                    label: "POWER (3s)",
                    value: "\(manager.displayPower)",
                    unit: "W",
                    valueColor: PowerZone.zone(for: manager.displayPower).color
                )
                MetricCardView(
                    label: "20M AVG",
                    value: manager.runningTwentyMinAvg > 0
                        ? "\(Int(manager.runningTwentyMinAvg.rounded()))"
                        : "—",
                    unit: "W",
                    subtitle: manager.state == .running && manager.currentPhase.id == 6
                        ? "\(Int(manager.testBlockProgress * 100))% complete"
                        : nil
                )
            }

            HStack(spacing: 10) {
                let currentFTP = PowerZone.ftp
                let projected = manager.liveProjectedFTP
                let projColor =
                    projected > currentFTP
                    ? AppColor.success
                    : (projected < currentFTP ? AppColor.orange : AppColor.yellow)

                let displayFTP = manager.estimatedFTP > 0 ? manager.estimatedFTP : (projected > 0 ? projected : 0)
                let weight = RidePreferences.shared.riderWeightKg
                let wkgSubtitle: String = {
                    if displayFTP > 0, weight > 0 {
                        return String(format: "%.2f W/kg  ·  Current: %d W", Double(displayFTP) / weight, currentFTP)
                    }
                    return "Current FTP: \(currentFTP) W"
                }()
                MetricCardView(
                    label: manager.state == .running && manager.currentPhase.id == 6
                        ? "LIVE PROJECTED FTP" : "ESTIMATED FTP (95%)",
                    value: manager.estimatedFTP > 0
                        ? "\(manager.estimatedFTP)"
                        : projected > 0
                            ? "~\(projected)"
                            : "—",
                    unit: "W",
                    valueColor: manager.estimatedFTP > 0
                        ? AppColor.yellow : (projected > 0 ? projColor : AppColor.yellow),
                    subtitle: wkgSubtitle
                )
                if manager.testMaxPower > 0 {
                    MetricCardView(
                        label: "TEST MAX",
                        value: "\(manager.testMaxPower)",
                        unit: "W",
                        valueColor: PowerZone.zone(for: manager.testMaxPower).color
                    )
                }
            }
        }
    }

    private var protocolCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PROTOCOL")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.5)
                .padding(.bottom, 2)

            ForEach(manager.phases) { phase in
                let phaseIndex = phase.id - 1
                let isCurrent =
                    manager.state != .completed && manager.currentPhaseIndex == phaseIndex
                let isDone = manager.currentPhaseIndex > phaseIndex || manager.state == .completed
                let phaseAvg = manager.phaseAveragePowers[phase.id]

                HStack(spacing: 8) {
                    Circle()
                        .fill(
                            isCurrent
                                ? AppColor.mango
                                : (isDone ? AppColor.blue : Color.white.opacity(0.15))
                        )
                        .frame(width: 7, height: 7)

                    Text(phase.name)
                        .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(isDone ? 0.5 : 0.7))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let avg = phaseAvg, isDone {
                        Text("\(Int(avg.rounded()))W")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(
                                PowerZone.zone(for: Int(avg.rounded())).color.opacity(0.8))
                    } else {
                        Text(FTPTestManager.format(seconds: phase.duration))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(isCurrent ? AppColor.mango.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var controls: some View {
        VStack(spacing: 8) {
            switch manager.state {
            case .idle:
                Button {
                    manager.start()
                } label: {
                    Label("Start FTP Protocol", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(manager.canStart ? .black : .white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            manager.canStart
                                ? AppColor.mango
                                : Color.white.opacity(0.06)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
                .disabled(!manager.canStart)

            case .running:
                HStack(spacing: 10) {
                    controlButton(label: "Pause", systemImage: "pause.fill") {
                        manager.pause()
                    }
                    controlButton(label: "End", systemImage: "stop.fill", isDestructive: true) {
                        showEndConfirmation = true
                    }
                }

            case .paused:
                HStack(spacing: 10) {
                    controlButton(label: "Resume", systemImage: "play.fill") {
                        manager.resume()
                    }
                    controlButton(label: "End", systemImage: "stop.fill", isDestructive: true) {
                        showEndConfirmation = true
                    }
                }

            case .completed:
                Button {
                    showApplyConfirmation = manager.estimatedFTP > 0
                } label: {
                    Label(
                        "Apply FTP \(manager.estimatedFTP) W", systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.yellow)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
                .disabled(manager.estimatedFTP == 0)

                controlButton(label: "Done", systemImage: "house.fill") {
                    navigationPath = NavigationPath()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.02))
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                }
        )
    }

    private func controlButton(
        label: String,
        systemImage: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    isDestructive
                        ? Color(red: 232 / 255, green: 68 / 255, blue: 90 / 255)
                        : .white.opacity(0.85)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }

    // MARK: - Phase Warning Overlay

    private func phaseWarningOverlay(warning: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(AppColor.yellow)
            Text("Next: \(warning)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.yellow)
            Spacer()
            Text("\(manager.secondsRemainingInPhase)s")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.yellow)
        }
        .padding(10)
        .background(AppColor.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Trainer Mode Badge

    @ViewBuilder
    private var trainerModeBadge: some View {
        let label = manager.trainerModeLabel
        let color: Color = {
            if label.hasPrefix("ERG") { return AppColor.mango }
            if label == "Free Ride" { return AppColor.success }
            return Color.white.opacity(0.4)
        }()

        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .animation(.easeInOut(duration: accessibilityReduceMotion ? 0 : 0.3), value: label)
    }

    // MARK: - Trainer Activity Card

    private var trainerActivityCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
                Text("TRAINER ACTIVITY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.5)
                Spacer()
                Text("\(manager.recentEvents.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.bottom, 2)

            ForEach(manager.recentEvents.reversed()) { event in
                HStack(spacing: 6) {
                    Text(FTPTestManager.format(seconds: event.elapsed))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: 56, alignment: .leading)

                    let eventColor: Color = {
                        if event.mode.hasPrefix("ERG") { return AppColor.mango }
                        if event.mode == "Free Ride" { return AppColor.success }
                        return Color.white.opacity(0.5)
                    }()

                    Circle()
                        .fill(eventColor)
                        .frame(width: 4, height: 4)

                    Text(event.mode)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(eventColor)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    let ble = BLEManager()
    let wifi = WiFiTrainerService()
    let ds = DataSourceCoordinator(bleManager: ble, wifiService: wifi)
    FTPTestView(
        navigationPath: .constant(NavigationPath())
    )
    .environment(ble)
    .environment(wifi)
    .environment(ds)
    .environment(HealthKitManager())
    .environment(FTPRefreshTrigger.shared)
}
