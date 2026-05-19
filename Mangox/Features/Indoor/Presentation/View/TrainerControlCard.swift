/// TrainerControlCard.swift
/// Extracted from DashboardSubviews.swift

import SwiftUI

struct TrainerControlCard: View {
    let trainerMode: TrainerControlMode
    let supportsSimulation: Bool
    let supportsERG: Bool
    let supportsResistance: Bool
    let hasRoute: Bool
    let isWorkoutActive: Bool
    /// When true, show the “load GPX for simulation” line (e.g. guided session has no mode banner).
    let showRouteSimulationFooterHint: Bool
    /// Tighter chrome for portrait single-screen layouts.
    var condensed: Bool = false

    var intensityMultiplier: Double = 1.0
    var onIntensityChange: ((Double) -> Void)? = nil

    var routeDifficultyScale: Double = 0.5
    var onDifficultyChange: ((Double) -> Void)? = nil

    let onRouteSim: () -> Void
    let onERG: () -> Void
    let onResistance: () -> Void
    let onFreeRide: () -> Void

    private var isRouteSimActive: Bool {
        if case .simulation = trainerMode { return true }
        return false
    }
    private var isERGActive: Bool {
        if case .erg = trainerMode { return true }
        return false
    }
    private var isResistanceActive: Bool {
        if case .resistance = trainerMode { return true }
        return false
    }

    private func gradeColor(for grade: Double) -> Color {
        let abs = Swift.abs(grade)
        if abs < 2 { return AppColor.success }
        if abs < 5 { return AppColor.yellow }
        if abs < 8 { return AppColor.orange }
        return AppColor.red
    }

    var body: some View {
        VStack(spacing: condensed ? 6 : 10) {
            if !condensed {
                // Header row
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .mangoxFont(.label)
                        .foregroundStyle(
                            trainerMode.isActive ? AppColor.success : AppColor.fg3)
                    Text("TRAINER CONTROL")
                        .mangoxFont(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1.0)
                    Spacer()

                    Text(trainerMode.label)
                        .mangoxFont(.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            trainerMode.isActive ? AppColor.success : AppColor.fg3
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            (trainerMode.isActive ? AppColor.success : Color.white).opacity(0.08)
                        )
                        .clipShape(Capsule())
                }
            }

            // Simulation grade display
            if case .simulation(let grade) = trainerMode {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: grade >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .mangoxFont(.callout)
                            .fontWeight(.bold)
                            .foregroundStyle(gradeColor(for: grade))
                        Text(DashboardNumberFormat.percent1(grade))
                            .font(
                                .system(
                                    size: condensed ? 18 : 22, weight: .bold, design: .monospaced)
                            )
                            .foregroundStyle(gradeColor(for: grade))
                    }
                    Spacer()
                    if let onDifficultyChange = onDifficultyChange {
                        compactStepper(
                            value: routeDifficultyScale,
                            step: 0.1,
                            minVal: 0.1,
                            maxVal: 2.0,
                            action: onDifficultyChange
                        )
                    }
                }
            }

            // ERG display
            if case .erg(let watts) = trainerMode {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.orange)
                    Text("TARGET")
                        .mangoxFont(.micro)
                        .fontWeight(.bold)
                        .foregroundStyle(AppColor.fg3)
                        .tracking(1)
                    Text("\(watts)W")
                        .font(
                            .system(size: condensed ? 17 : 20, weight: .bold, design: .monospaced)
                        )
                        .foregroundStyle(AppColor.orange)
                    Spacer()
                    if let onIntensityChange = onIntensityChange {
                        compactStepper(
                            value: intensityMultiplier,
                            step: 0.05,
                            minVal: 0.5,
                            maxVal: 1.5,
                            action: onIntensityChange
                        )
                    }
                }
            }

            // Quick buttons
            if isWorkoutActive {
                HStack(spacing: condensed ? 6 : 8) {
                    if supportsSimulation && hasRoute {
                        trainerButton(
                            "Route", icon: "map.fill", isActive: isRouteSimActive,
                            action: onRouteSim, condensed: condensed)
                    }
                    if supportsERG {
                        trainerButton(
                            "ERG", icon: "lock.fill", isActive: isERGActive, action: onERG,
                            condensed: condensed)
                    }
                    if supportsResistance {
                        trainerButton(
                            "Resist", icon: "dial.medium.fill", isActive: isResistanceActive,
                            action: onResistance, condensed: condensed)
                    }
                    if trainerMode.isActive {
                        trainerButton(
                            "Free", icon: "figure.outdoor.cycle", isActive: false,
                            action: onFreeRide, condensed: condensed)
                    }
                }
            }

            if condensed {
                switch trainerMode {
                case .simulation, .erg:
                    EmptyView()
                default:
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.2.fill")
                            .mangoxFont(.micro)
                            .foregroundStyle(
                                trainerMode.isActive ? AppColor.success : AppColor.fg3)
                        Text(trainerMode.label)
                            .mangoxFont(.label)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                trainerMode.isActive ? AppColor.success : AppColor.fg3)
                        Spacer()
                    }
                }
            }

            if supportsSimulation, !hasRoute, isWorkoutActive, showRouteSimulationFooterHint,
                !condensed
            {
                Text(IndoorDashboardL10n.trainerRouteSimFooter)
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, condensed ? 10 : 12)
        .padding(
            .vertical,
            supportsSimulation && !hasRoute && isWorkoutActive && showRouteSimulationFooterHint
                && !condensed ? 10 : (condensed ? 8 : 12)
        )
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(
                    trainerMode.isActive
                        ? AppColor.success.opacity(0.15) : AppColor.hair,
                    lineWidth: 1
                )
        )
        .animation(.easeInOut(duration: 0.3), value: trainerMode.label)
    }

    @ViewBuilder
    private func compactStepper(
        value: Double,
        step: Double,
        minVal: Double,
        maxVal: Double,
        action: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                action(max(minVal, value - step))
            } label: {
                Image(systemName: "minus")
                    .mangoxFont(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg1)
                    .frame(width: 44, height: 44)
                    .mangoxSurface(.flatSubtle, shape: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text("\(Int(round(value * 100)))%")
                .font(DashboardFontToken.mono(size: 11, weight: .bold))
                .foregroundStyle(AppColor.fg1)
                .frame(minWidth: 48)
                .multilineTextAlignment(.center)

            Button {
                action(min(maxVal, value + step))
            } label: {
                Image(systemName: "plus")
                    .mangoxFont(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.fg1)
                    .frame(width: 44, height: 44)
                    .mangoxSurface(.flatSubtle, shape: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func trainerButton(
        _ label: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void,
        condensed: Bool = false
    ) -> some View {
        Button(action: action) {
            VStack(spacing: condensed ? 2 : 4) {
                Image(systemName: icon)
                    .font(MangoxFont.caption.value)
                Text(label)
                    .mangoxFont(.micro)
                    .fontWeight(.semibold)
                    .tracking(0.5)
            }
            .foregroundStyle(isActive ? AppColor.success : AppColor.fg2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, condensed ? 6 : 8)
            .background((isActive ? AppColor.success : Color.white).opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue))
            .overlay(
                RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue)
                    .strokeBorder(
                        isActive ? AppColor.success.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
