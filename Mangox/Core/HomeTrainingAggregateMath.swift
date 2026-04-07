import Foundation

/// Lightweight workout metrics copied on the main thread before off-main aggregation.
struct HomeWorkoutMetricSlice: Sendable {
    let startDate: Date
    let tss: Double
}

struct HomeWeekBarDTO: Sendable {
    let id: String
    let day: String
    let tss: Double
}

struct HomeTrainingCacheDTO: Sendable {
    let weeklyTSS: Double
    let chronicLoad: Double
    let acwr: Double
    let weekRides: Int
    let weekBars: [HomeWeekBarDTO]
}

/// Pure training aggregates for `HomeView` (no SwiftUI / SwiftData types).
enum HomeTrainingAggregateMath {

    static func compute(
        slices: [HomeWorkoutMetricSlice],
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> HomeTrainingCacheDTO {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale

        let startOfWeek =
            calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? now
        let fourWeeksAgo = calendar.date(byAdding: .day, value: -28, to: now) ?? now

        let weeklyTSS = slices.filter { $0.startDate >= startOfWeek }.reduce(0) { $0 + $1.tss }
        let recent = slices.filter { $0.startDate >= fourWeeksAgo }
        let chronicLoad: Double = recent.isEmpty ? 300 : recent.reduce(0) { $0 + $1.tss } / 4.0
        let acwr = chronicLoad > 0 && !slices.isEmpty ? weeklyTSS / chronicLoad : 0
        let weekRides = slices.filter { $0.startDate >= startOfWeek }.count

        let narrowDayFormatter = DateFormatter()
        narrowDayFormatter.locale = locale
        narrowDayFormatter.timeZone = timeZone
        narrowDayFormatter.setLocalizedDateFormatFromTemplate("EEEEE")

        let weekBars: [HomeWeekBarDTO] = (0..<7).map { dayOffset in
            let dayDate =
                calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek) ?? startOfWeek
            let dayStart = calendar.startOfDay(for: dayDate)
            let comps = calendar.dateComponents([.year, .month, .day], from: dayStart)
            let rowId = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            let dayLabel = narrowDayFormatter.string(from: dayStart)
            let tss = slices
                .filter { calendar.isDate($0.startDate, inSameDayAs: dayDate) }
                .reduce(0.0) { $0 + $1.tss }
            return HomeWeekBarDTO(id: rowId, day: dayLabel, tss: tss)
        }

        return HomeTrainingCacheDTO(
            weeklyTSS: weeklyTSS,
            chronicLoad: chronicLoad,
            acwr: acwr,
            weekRides: weekRides,
            weekBars: weekBars
        )
    }
}
