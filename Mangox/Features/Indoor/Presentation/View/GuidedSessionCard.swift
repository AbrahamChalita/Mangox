/// GuidedSessionCard.swift
/// Extracted from DashboardSubviews.swift

import SwiftUI

struct GuidedSessionCard: View {
    let session: GuidedSessionManager
    /// Shorter layout for portrait single-screen fits (drops up-next and stats bar).
    var condensed: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownFontSize = 32
    @ScaledMetric(relativeTo: .headline) private var metricValueFontSize = 18
    @ScaledMetric(relativeTo: .body) private var contentPadding = 14

    private func guidedZoneColor(_ zone: TrainingZoneTarget) -> Color { zone.color }

    private var complianceColor: Color {
        switch session.compliance {
        case .inZone: return AppColor.success
        case .belowZone: return AppColor.yellow
        case .aboveZone: return AppColor.red
        }
    }

    private func gradeColor(for grade: Double) -> Color {
        let abs = Swift.abs(grade)
        if abs < 2 { return AppColor.success }
        if abs < 5 { return AppColor.yellow }
        if abs < 8 { return AppColor.orange }
        return AppColor.red
    }

    private var borderColor: Color {
        if let step = session.currentStep {
            return guidedZoneColor(step.zone).opacity(0.2)
        }
        return AppColor.mango.opacity(0.15)
    }

    var body: some View {
        Group {
            if condensed {
                condensedStepContent
            } else {
                VStack(spacing: 0) {
                    currentStepContent
                    upNextPreview
                    sessionStatsBar
                }
            }
        }
        .background(AppColor.bg2)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.sharp.rawValue)
                .strokeBorder(borderColor, lineWidth: condensed ? 1 : 1.5)
        )
        .animation(MangoxMotion.standard, value: session.currentStepIndex)
    }

    @ViewBuilder
    private var condensedStepContent: some View {
        if let step = session.currentStep {
            activeStepCondensed(step)
        } else if session.isPastPlan {
            pastPlanCondensed
        } else if !session.hasIntervals {
            steadyStateCondensed
        }
    }

    private func activeStepCondensed(_ step: TimelineStep) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.label)
                .font(.headline)
                .foregroundStyle(AppColor.fg0)
                .lineLimit(2)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    condensedCountdown
                    stepZoneChip(step)
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    condensedCountdown
                    stepZoneChip(step)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.hair)
                    Capsule()
                        .fill(guidedZoneColor(step.zone))
                        .frame(width: max(0, geo.size.width * session.stepProgress))
                        .animation(MangoxMotion.smooth, value: session.stepProgress)
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    compliancePill
                    if let range = session.scaledTargetWattRange(for: step) {
                        targetMetricPill(
                            title: "Target",
                            value: "\(range.lowerBound)-\(range.upperBound)",
                            unit: "W",
                            color: guidedZoneColor(step.zone)
                        )
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 6) {
                    compliancePill
                    if let range = session.scaledTargetWattRange(for: step) {
                        targetMetricPill(
                            title: "Target",
                            value: "\(range.lowerBound)-\(range.upperBound)",
                            unit: "W",
                            color: guidedZoneColor(step.zone)
                        )
                    }
                }
            }
        }
        .padding(10)
    }

    private var condensedCountdown: some View {
        Text(GuidedSessionManager.formatCountdown(session.stepSecondsRemaining))
            .font(DashboardFontToken.mono(size: max(22, countdownFontSize - 6), weight: .black))
            .foregroundStyle(AppColor.fg0)
            .contentTransition(.numericText())
    }

    private func targetMetricPill(title: String, value: String, unit: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title.uppercased())
                .mangoxFont(.micro)
                .fontWeight(.bold)
                .foregroundStyle(AppColor.fg3)
            Text(value)
                .font(DashboardFontToken.mono(size: 11, weight: .bold))
                .foregroundStyle(color)
            Text(unit)
                .mangoxFont(.micro)
                .foregroundStyle(AppColor.fg3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func stepZoneChip(_ step: TimelineStep) -> some View {
        Text(step.zone.label)
            .mangoxFont(.micro)
            .fontWeight(.bold)
            .foregroundStyle(guidedZoneColor(step.zone))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(guidedZoneColor(step.zone).opacity(0.15))
            .clipShape(Capsule())
    }

    private var pastPlanCondensed: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(MangoxFont.title.value)
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Complete!")
                    .mangoxFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg0)
                Text("Free riding — end when ready")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
    }

    private var steadyStateCondensed: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.indoor.cycle")
                .mangoxFont(.callout)
                .foregroundStyle(AppColor.success)
            Text(session.dayTitle)
                .mangoxFont(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(AppColor.fg0)
                .lineLimit(1)
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder
    private var currentStepContent: some View {
        if let step = session.currentStep {
            activeStepView(step)
        } else if session.isPastPlan {
            pastPlanView
        } else if !session.hasIntervals {
            steadyStateView
        }
    }

    private func activeStepView(_ step: TimelineStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(step.label)
                .font(.headline.weight(.bold))
                .foregroundStyle(AppColor.fg0)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

            stepMetaChips(step)

            VStack(alignment: .leading, spacing: 4) {
                Text("REMAINING")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                Text(GuidedSessionManager.formatCountdown(session.stepSecondsRemaining))
                    .font(DashboardFontToken.mono(size: countdownFontSize, weight: .black))
                    .foregroundStyle(AppColor.fg0)
                    .contentTransition(.numericText())
                    .animation(MangoxMotion.standard, value: session.stepSecondsRemaining)
                    .minimumScaleFactor(0.75)
            }

            stepMetricsSection(step)

            // Step progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColor.hair)
                    Capsule()
                        .fill(guidedZoneColor(step.zone))
                        .frame(width: max(0, geo.size.width * session.stepProgress))
                        .animation(MangoxMotion.smooth, value: session.stepProgress)
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            complianceSummaryRow(step)

            Text(session.motivationalMessage)
                .font(.callout.weight(.medium))
                .foregroundStyle(AppColor.fg1)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(MangoxMotion.standard, value: session.motivationalMessage)
        }
        .padding(contentPadding)
    }

    private func stepMetaChips(_ step: TimelineStep) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                stepMetaChip(
                    title: step.zone.label,
                    icon: nil,
                    foreground: guidedZoneColor(step.zone),
                    background: guidedZoneColor(step.zone).opacity(0.15)
                )
                stepMetaChip(
                    title: step.suggestedTrainerMode.label,
                    icon: step.suggestedTrainerMode.icon,
                    foreground: AppColor.success.opacity(0.9),
                    background: AppColor.success.opacity(0.1)
                )
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                stepMetaChip(
                    title: step.zone.label,
                    icon: nil,
                    foreground: guidedZoneColor(step.zone),
                    background: guidedZoneColor(step.zone).opacity(0.15)
                )
                stepMetaChip(
                    title: step.suggestedTrainerMode.label,
                    icon: step.suggestedTrainerMode.icon,
                    foreground: AppColor.success.opacity(0.9),
                    background: AppColor.success.opacity(0.1)
                )
            }
        }
    }

    private func stepMetaChip(title: String, icon: String?, foreground: Color, background: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .mangoxFont(.label)
                    .fontWeight(.semibold)
            }
            Text(title)
                .mangoxFont(.label)
                .fontWeight(.bold)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background)
        .clipShape(Capsule())
    }

    private func stepMetricsSection(_ step: TimelineStep) -> some View {
        let columns = [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 150 : 120), spacing: 8)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            if let range = session.scaledTargetWattRange(for: step) {
                guidedMetricBlock(
                    title: "Target",
                    value: "\(range.lowerBound)-\(range.upperBound)",
                    unit: "watts",
                    color: guidedZoneColor(step.zone)
                )
            }
            if let low = step.cadenceLow, let high = step.cadenceHigh {
                guidedMetricBlock(
                    title: "Cadence",
                    value: "\(low)-\(high)",
                    unit: "rpm",
                    color: AppColor.blue
                )
            }
        }
    }

    private func guidedMetricBlock(title: String, value: String, unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
            Text(value)
                .font(DashboardFontToken.mono(size: metricValueFontSize, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(unit)
                .mangoxFont(.label)
                .foregroundStyle(AppColor.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
    }

    private func complianceSummaryRow(_ step: TimelineStep) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                compliancePill
                Spacer(minLength: 0)
                inZonePill
                if step.suggestedTrainerMode == .simulation, let grade = step.simulationGrade {
                    gradePill(grade)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                compliancePill
                HStack(spacing: 8) {
                    inZonePill
                    if step.suggestedTrainerMode == .simulation, let grade = step.simulationGrade {
                        gradePill(grade)
                    }
                }
            }
        }
    }

    private var compliancePill: some View {
        HStack(spacing: 5) {
            Image(systemName: session.compliance.icon)
                .mangoxFont(.label)
                .fontWeight(.semibold)
            Text(session.compliance.label)
                .mangoxFont(.label)
                .fontWeight(.semibold)
        }
        .foregroundStyle(complianceColor)
    }

    private var inZonePill: some View {
        HStack(spacing: 4) {
            Image(systemName: "target")
                .mangoxFont(.micro)
            Text("\(DashboardNumberFormat.percent0(session.stepInZonePercent)) in zone")
                .mangoxFont(.label)
        }
        .foregroundStyle(AppColor.fg2)
    }

    private func gradePill(_ grade: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "mountain.2.fill")
                .mangoxFont(.micro)
            Text(DashboardNumberFormat.percent1(grade))
                .mangoxFont(.label)
                .fontWeight(.bold)
        }
        .foregroundStyle(gradeColor(for: grade))
    }

    private var pastPlanView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(MangoxFont.bodyBold.value)
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Workout Complete!")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)
                Text("Free riding — keep going or end when ready")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(DashboardNumberFormat.percent0(session.totalInZonePercent))
                    .font(DashboardFontToken.mono(size: 16, weight: .bold))
                    .foregroundStyle(AppColor.success)
                Text("in zone")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
            }
        }
        .padding(14)
    }

    private var steadyStateView: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.indoor.cycle")
                .font(MangoxFont.title.value)
                .foregroundStyle(AppColor.success)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.dayTitle)
                    .mangoxFont(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColor.fg0)
                Text(session.dayNotes)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
    }

    @ViewBuilder
    private var upNextPreview: some View {
        if let next = session.nextStep {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    upNextLead(next)
                    Spacer()
                    upNextTrailing(next)
                }
                VStack(alignment: .leading, spacing: 6) {
                    upNextLead(next)
                    upNextTrailing(next)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func upNextLead(_ next: TimelineStep) -> some View {
        HStack(spacing: 8) {
            Text("UP NEXT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColor.fg4)
                .tracking(1.0)
            Circle()
                .fill(guidedZoneColor(next.zone))
                .frame(width: 6, height: 6)
            Text(next.label)
                .font(.callout.weight(.medium))
                .foregroundStyle(AppColor.fg2)
                .lineLimit(2)
        }
    }

    private func upNextTrailing(_ next: TimelineStep) -> some View {
        HStack(spacing: 8) {
            Text(GuidedSessionManager.formatCountdown(next.durationSeconds))
                .font(.callout.monospacedDigit())
                .foregroundStyle(AppColor.fg3)
            Text(next.zone.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(guidedZoneColor(next.zone).opacity(0.7))
            Text(next.suggestedTrainerMode.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppColor.fg3)
        }
    }

    @ViewBuilder
    private var sessionStatsBar: some View {
        if session.hasIntervals {
            Rectangle()
                .fill(AppColor.hair)
                .frame(height: 1)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 110 : 78), spacing: 8)],
                spacing: 8
            ) {
                guidedStatPill(
                    label: "OVERALL",
                    value: DashboardNumberFormat.percent0(session.overallProgress * 100))
                guidedStatPill(
                    label: "IN ZONE",
                    value: DashboardNumberFormat.percent0(session.totalInZonePercent))
                guidedStatPill(
                    label: "ELAPSED",
                    value: GuidedSessionManager.formatCountdown(session.elapsedSeconds))
                guidedStatPill(
                    label: "REMAINING",
                    value: GuidedSessionManager.formatCountdown(
                        max(0, session.totalPlannedSeconds - session.elapsedSeconds)
                    )
                )
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
        }
    }

    private func guidedStatPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppColor.fg4)
                .tracking(1.0)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(AppColor.fg2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppColor.hair)
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.overlay.rawValue, style: .continuous))
    }
}
