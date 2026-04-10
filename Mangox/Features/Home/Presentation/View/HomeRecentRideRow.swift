import SwiftUI

// MARK: - Column layout (header + rows share widths)

private enum HomeRideColumn {
    static let stripe: CGFloat = 4
    static let dur: CGFloat = 48
    static let power: CGFloat = 56
    static let dist: CGFloat = 62
    static let tss: CGFloat = 36
    static let chevron: CGFloat = 14
    static let gap: CGFloat = 6
}

/// Column headers for the home “Recent rides” table.
struct HomeRecentRidesTableHeader: View {
    var body: some View {
        HStack(spacing: HomeRideColumn.gap) {
            Color.clear
                .frame(width: HomeRideColumn.stripe)

            Text("DATE")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("DUR")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.6)
                .frame(width: HomeRideColumn.dur, alignment: .trailing)

            Text("POWER")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.6)
                .frame(width: HomeRideColumn.power, alignment: .trailing)

            Text("DIST")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.6)
                .frame(width: HomeRideColumn.dist, alignment: .trailing)

            Text("TSS")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.28))
                .tracking(0.6)
                .frame(width: HomeRideColumn.tss, alignment: .trailing)

            Color.clear
                .frame(width: HomeRideColumn.chevron)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// One ride row aligned to `HomeRecentRidesTableHeader`.
struct HomeRecentRideRow: View {
    let workout: Workout
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol

    private var zone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower))
    }

    private var isValid: Bool { workout.isValid }

    private var imperial: Bool { RidePreferences.shared.isImperial }

    private let accentYellow = AppColor.yellow

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: HomeRideColumn.gap) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        workout.planDayID != nil
                            ? LinearGradient(colors: [accentYellow, zone.color], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [zone.color.opacity(isValid ? 1.0 : 0.35)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: HomeRideColumn.stripe, height: isValid ? 38 : 44)

                // Date & time — flexible column
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.startDate, format: .dateTime.month(.abbreviated).day().year(.twoDigits))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(isValid ? 0.95 : 0.4))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if isValid {
                        Text(workout.startDate, format: .dateTime.hour().minute())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.38))
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(AppColor.orange.opacity(0.55))
                            Text("Too short")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isValid {
                    Text(AppFormat.duration(workout.duration))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: HomeRideColumn.dur, alignment: .trailing)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int(workout.avgPower))W")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(zone.color)
                            .lineLimit(1)
                        Text("Z\(zone.id)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(zone.color.opacity(0.55))
                            .lineLimit(1)
                    }
                    .frame(width: HomeRideColumn.power, alignment: .trailing)

                    Text(AppFormat.distanceString(workout.distance, imperial: imperial))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: HomeRideColumn.dist, alignment: .trailing)

                    Text(workout.tss > 0 ? String(format: "%.0f", workout.tss) : "—")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(workout.tss > 0 ? tssColor : .white.opacity(0.22))
                        .lineLimit(1)
                        .frame(width: HomeRideColumn.tss, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(width: HomeRideColumn.dur, alignment: .trailing)

                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(width: HomeRideColumn.power, alignment: .trailing)

                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(width: HomeRideColumn.dist, alignment: .trailing)

                    Text("—")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .frame(width: HomeRideColumn.tss, alignment: .trailing)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(isValid ? 0.14 : 0.08))
                    .frame(width: HomeRideColumn.chevron, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let dayID = workout.planDayID {
                HomePlanDayBadgeRow(
                    dayID: dayID,
                    planID: workout.planID,
                    trainingPlanLookupService: trainingPlanLookupService
                )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(
            workout.planDayID != nil
                ? accentYellow.opacity(0.05)
                : Color.white.opacity(0.04)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    workout.planDayID != nil
                        ? accentYellow.opacity(0.15)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .opacity(isValid ? 1.0 : 0.7)
    }

    private var tssColor: Color {
        let tss = workout.tss
        if tss < 150 { return AppColor.success }
        if tss < 300 { return AppColor.yellow }
        if tss < 450 { return AppColor.orange }
        return AppColor.red
    }
}

// MARK: - Plan badge (matches WorkoutRowView)

private struct HomePlanDayBadgeRow: View {
    let dayID: String
    let planID: String?
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol

    private let accentYellow = AppColor.yellow

    var body: some View {
        if let day = trainingPlanLookupService.resolveDay(
            planID: planID,
            dayID: dayID
        ) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 10))
                    Text("W\(day.weekNumber)D\(day.dayOfWeek)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(accentYellow.opacity(0.8))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(accentYellow.opacity(0.1))
                .clipShape(Capsule())

                Text(day.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .padding(.leading, 8)

                if day.zone != .rest && day.zone != .none {
                    Text(day.zone.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(day.zone.color.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(day.zone.color.opacity(0.12))
                        .clipShape(Capsule())
                        .padding(.leading, 6)
                }

                Spacer()
            }
        }
    }
}
