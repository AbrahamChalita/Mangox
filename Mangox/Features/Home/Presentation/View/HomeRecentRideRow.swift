import SwiftUI

struct HomeRecentRidesTableHeader: View {
    var body: some View {
        EmptyView()
    }
}

struct HomeRecentRideRow: View {
    let workout: Workout
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol

    private var isValid: Bool { workout.isValid }
    private var imperial: Bool { RidePreferences.shared.isImperial }

    private var zone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower))
    }

    private var isOutdoor: Bool {
        workout.savedRouteName != nil || workout.elevationGain > 0
    }

    private var dayTitle: String? {
        guard let dayID = workout.planDayID else { return nil }
        return trainingPlanLookupService.resolveDay(planID: workout.planID, dayID: dayID)?.title
    }

    private var titleText: String {
        if let route = workout.savedRouteName, !route.isEmpty {
            return route
        }
        if let dayTitle, !dayTitle.isEmpty {
            return dayTitle
        }
        return isOutdoor ? "Outdoor ride" : "Indoor session"
    }

    private var subtitleText: String {
        let kind = isOutdoor ? "Outdoor" : "Indoor"
        return "\(workout.startDate.formatted(.dateTime.month(.abbreviated).day())) · \(kind) · \(AppFormat.duration(workout.duration))"
    }

    private var metricValue: String {
        if isOutdoor {
            return String(format: "%.1f", AppFormat.distance(workout.distance, imperial: imperial).value)
        }
        if workout.avgPower > 0 {
            return "\(Int(workout.avgPower.rounded()))"
        }
        return "\(Int(workout.tss.rounded()))"
    }

    private var metricUnit: String {
        if isOutdoor {
            return AppFormat.distanceUnit(imperial: imperial)
        }
        if workout.avgPower > 0 {
            return "w"
        }
        return "tss"
    }

    private var iconGlyph: String {
        isOutdoor ? "↗" : "→"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(iconGlyph)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOutdoor ? AppColor.mango : AppColor.blue)
                .frame(width: 28, height: 28)
                .background(AppColor.bg1)
                .overlay(
                    Rectangle()
                        .stroke(
                            isOutdoor ? AppColor.mango.opacity(0.3) : AppColor.blue.opacity(0.28),
                            lineWidth: 1
                        )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .font(MangoxFont.bodyBold.value)
                    .foregroundStyle(isValid ? AppColor.fg0 : AppColor.fg3)
                    .lineLimit(1)

                Text(subtitleText)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg3)
                    .lineLimit(1)

                if let dayTitle, workout.savedRouteName != dayTitle {
                    Text(dayTitle.uppercased())
                        .mangoxFont(.micro)
                        .foregroundStyle(AppColor.yellow.opacity(0.75))
                        .tracking(0.8)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 10)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(metricValue)
                    .font(MangoxFont.value.value)
                    .foregroundStyle(isOutdoor ? AppColor.fg0 : zone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(metricUnit)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg2)
            }
            .frame(minWidth: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppColor.bg2)
        .overlay(
            Rectangle()
                .stroke(workout.planDayID != nil ? AppColor.yellow.opacity(0.18) : AppColor.hair, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(workout.planDayID != nil ? AppColor.yellow : zone.color.opacity(isValid ? 0.9 : 0.35))
                .frame(width: 2)
        }
        .opacity(isValid ? 1.0 : 0.72)
    }
}

private extension HomeRecentRideRow {
    var tssColor: Color {
        let tss = workout.tss
        if tss < 150 { return AppColor.success }
        if tss < 300 { return AppColor.yellow }
        if tss < 450 { return AppColor.orange }
        return AppColor.red
    }
}
