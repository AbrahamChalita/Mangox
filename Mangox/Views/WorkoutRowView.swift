import SwiftUI

struct WorkoutRowView: View {
    let workout: Workout

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
            // Main row content
            HStack(spacing: 12) {
                // Zone color indicator — taller when plan badge is present
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        workout.planDayID != nil
                            ? LinearGradient(colors: [accentYellow, zone.color], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: [zone.color.opacity(isValid ? 1.0 : 0.35)], startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 4)

                // Date & time
                VStack(alignment: .leading, spacing: 3) {
                    Text(workout.startDate, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(isValid ? 1.0 : 0.4))

                    Text(workout.startDate, format: .dateTime.hour().minute())
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(isValid ? 0.4 : 0.2))
                }

                Spacer(minLength: 8)

                if isValid {
                    // Valid workout stats
                    HStack(spacing: 8) {
                        // Duration
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formattedDuration)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("duration")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.25))
                                .lineLimit(1)
                        }

                        // Avg Power
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(workout.avgPower))W")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(zone.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(zone.name.lowercased())
                                .font(.system(size: 10))
                                .foregroundStyle(zone.color.opacity(0.5))
                                .lineLimit(1)
                        }

                        // Distance
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.1fkm", workout.distance / 1000))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("dist")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.25))
                                .lineLimit(1)
                        }

                        // TSS pill
                        if workout.tss > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(format: "%.0f", workout.tss))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(tssColor)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Text("tss")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.25))
                                    .lineLimit(1)
                            }
                        }
                    }
                } else {
                    // Invalid workout indicator
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(accentOrange.opacity(0.6))
                        Text("Too short (\(formattedDuration))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isValid ? 0.15 : 0.08))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            // Plan day badge — below the main row, inside the VStack
            if let dayID = workout.planDayID {
                planDayBadge(dayID: dayID)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }
        }
        .background(
            workout.planDayID != nil
                ? accentYellow.opacity(0.05)
                : Color.white.opacity(0.04)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    workout.planDayID != nil
                        ? accentYellow.opacity(0.15)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .opacity(isValid ? 1.0 : 0.65)
    }

    // MARK: - Plan Day Badge

    @ViewBuilder
    private func planDayBadge(dayID: String) -> some View {
        let day = PlanLibrary.resolveDay(planID: workout.planID, dayID: dayID)
        if let day = day {
            HStack(spacing: 0) {
                // Plan icon + week/day tag
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

                // Day title
                Text(day.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .padding(.leading, 8)

                // Zone target badge
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
