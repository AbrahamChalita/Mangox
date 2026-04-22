import SwiftUI

struct WorkoutRowView: View {
    let workout: Workout
    let trainingPlanLookupService: TrainingPlanLookupServiceProtocol

    private var zone: PowerZone {
        PowerZone.zone(for: Int(workout.avgPower))
    }

    private var isValid: Bool {
        workout.isValid
    }

    private let accentGreen = AppColor.success
    private let accentYellow = AppColor.yellow
    private let accentOrange = AppColor.orange
    private let accentRed = AppColor.red

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(
                        workout.planDayID != nil
                            ? LinearGradient(colors: [accentYellow, zone.color], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [zone.color.opacity(isValid ? 1.0 : 0.35)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(MangoxFont.body.value)
                        .foregroundStyle(isValid ? AppColor.fg0 : AppColor.fg3)

                    Text(workout.startDate, format: .dateTime.hour().minute())
                        .font(MangoxFont.caption.value)
                        .foregroundStyle(isValid ? AppColor.fg3 : AppColor.fg4)
                }

                Spacer(minLength: 8)

                if isValid {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formattedDuration)
                                .font(MangoxFont.caption.value)
                                .foregroundStyle(AppColor.fg1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("duration")
                                .mangoxFont(.micro)
                                .foregroundStyle(AppColor.fg3)
                                .lineLimit(1)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(workout.avgPower))W")
                                .font(MangoxFont.caption.value)
                                .foregroundStyle(zone.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(zone.name.lowercased())
                                .mangoxFont(.micro)
                                .foregroundStyle(zone.color.opacity(0.7))
                                .lineLimit(1)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1fkm", workout.distance / 1000))
                                .font(MangoxFont.caption.value)
                                .foregroundStyle(AppColor.fg1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("dist")
                                .mangoxFont(.micro)
                                .foregroundStyle(AppColor.fg3)
                                .lineLimit(1)
                        }

                        if workout.tss > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.0f", workout.tss))
                                    .font(MangoxFont.caption.value)
                                    .foregroundStyle(tssColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("tss")
                                    .mangoxFont(.micro)
                                    .foregroundStyle(AppColor.fg3)
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentOrange.opacity(0.6))
                        Text("Too short (\(formattedDuration))")
                            .mangoxFont(.caption)
                            .foregroundStyle(AppColor.fg3)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isValid ? AppColor.fg4 : AppColor.fg4.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if let dayID = workout.planDayID {
                planDayBadge(dayID: dayID)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(
            AppColor.bg2
        )
        .overlay(
            Rectangle()
                .stroke(AppColor.hair2, lineWidth: 1)
        )
        .opacity(isValid ? 1.0 : 0.65)
    }

    // MARK: - Plan Day Badge

    @ViewBuilder
    private func planDayBadge(dayID: String) -> some View {
        let day = trainingPlanLookupService.resolveDay(
            planID: workout.planID,
            dayID: dayID
        )
        if let day = day {
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
                .background(AppColor.bg1)
                .overlay(Capsule().strokeBorder(accentYellow.opacity(0.35), lineWidth: 1))
                .clipShape(Capsule())

                Text(day.title)
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.fg2)
                    .lineLimit(1)
                    .padding(.leading, 8)

                if day.zone != .rest && day.zone != .none {
                    Text(day.zone.label)
                        .mangoxFont(.caption)
                        .foregroundStyle(day.zone.color.opacity(0.8))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(AppColor.bg1)
                        .overlay(Capsule().strokeBorder(day.zone.color.opacity(0.35), lineWidth: 1))
                        .clipShape(Capsule())
                        .padding(.leading, 6)
                }

                Spacer()
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        AppFormat.duration(workout.duration)
    }

    private var tssColor: Color {
        let tss = workout.tss
        if tss < 150 { return accentGreen }
        if tss < 300 { return accentYellow }
        if tss < 450 { return accentOrange }
        return accentRed
    }


}
