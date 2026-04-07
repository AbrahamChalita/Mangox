import SwiftUI
import SwiftData

/// Side-by-side ride comparison.
/// Shows current ride metrics alongside the previous ride, highlighting deltas.
struct RideComparisonView: View {
    let current: Workout
    let previous: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text("VS. PREVIOUS RIDE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.35))
                    .tracking(1.5)
                Spacer()
                Text(previous.startDate, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }

            comparisonRow(label: "Duration",
                          current: AppFormat.duration(current.duration),
                          previous: AppFormat.duration(previous.duration),
                          delta: current.duration - previous.duration,
                          deltaFormat: { d in
                              let sign = d >= 0 ? "+" : ""
                              return "\(sign)\(AppFormat.duration(abs(d)))"
                          })

            comparisonRow(label: "Distance",
                          current: String(format: "%.1f km", current.distance / 1000),
                          previous: String(format: "%.1f km", previous.distance / 1000),
                          delta: current.distance - previous.distance,
                          deltaFormat: { d in
                              String(format: "%+.1f km", d / 1000)
                          })

            comparisonRow(label: "Avg Power",
                          current: "\(Int(current.avgPower)) W",
                          previous: "\(Int(previous.avgPower)) W",
                          delta: current.avgPower - previous.avgPower,
                          deltaFormat: { d in
                              String(format: "%+.0f W", d)
                          })

            if current.normalizedPower > 0 && previous.normalizedPower > 0 {
                comparisonRow(label: "NP",
                              current: "\(Int(current.normalizedPower)) W",
                              previous: "\(Int(previous.normalizedPower)) W",
                              delta: current.normalizedPower - previous.normalizedPower,
                              deltaFormat: { d in
                                  String(format: "%+.0f W", d)
                              })
            }

            if current.avgHR > 0 && previous.avgHR > 0 {
                comparisonRow(label: "Avg HR",
                              current: "\(Int(current.avgHR)) bpm",
                              previous: "\(Int(previous.avgHR)) bpm",
                              delta: current.avgHR - previous.avgHR,
                              deltaFormat: { d in
                                  String(format: "%+.0f bpm", d)
                              })
            }

            comparisonRow(label: "TSS",
                          current: String(format: "%.0f", current.tss),
                          previous: String(format: "%.0f", previous.tss),
                          delta: current.tss - previous.tss,
                          deltaFormat: { d in
                              String(format: "%+.0f", d)
                          })
        }
        .padding(14)
        .cardStyle()
    }

    private func comparisonRow(
        label: String,
        current: String,
        previous: String,
        delta: Double,
        deltaFormat: (Double) -> String
    ) -> some View {
        let isPositive = delta > 0
        let deltaColor: Color = isPositive ? AppColor.success : (delta < 0 ? AppColor.red : .white.opacity(0.3))

        return HStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 80, alignment: .leading)

            Text(current)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)

            Text(previous)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .frame(maxWidth: .infinity)

            Text(deltaFormat(delta))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(deltaColor)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }
}

/// Finds the previous workout before a given one and returns a comparison view.
struct RideComparisonLoader: View {
    let workout: Workout
    @Query private var previousCandidates: [Workout]

    init(workout: Workout) {
        self.workout = workout
        let wid = workout.id
        let boundary = workout.startDate
        var d = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { w in
                w.id != wid && w.startDate < boundary
            },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        d.fetchLimit = 1
        _previousCandidates = Query(d)
    }

    var body: some View {
        if let previous = previousCandidates.first {
            RideComparisonView(current: workout, previous: previous)
        }
    }
}
