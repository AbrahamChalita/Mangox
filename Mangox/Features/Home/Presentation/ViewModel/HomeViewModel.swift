// Features/Home/Presentation/ViewModel/HomeViewModel.swift
import Foundation

@MainActor
@Observable
final class HomeViewModel {
    // MARK: - View state
    var weeklyTSS: Double = 0
    var chronicLoad: Double = 0
    var acwr: Double = 0
    var weekRides: Int = 0
    var weekBars: [HomeWeekBarDTO] = []
    var isComputing: Bool = false

    func refresh(slices: [HomeWorkoutMetricSlice]) {
        isComputing = true
        let dto = HomeTrainingAggregateMath.compute(
            slices: slices,
            now: Date(),
            timeZone: TimeZone.current,
            locale: Locale.current
        )
        weeklyTSS = dto.weeklyTSS
        chronicLoad = dto.chronicLoad
        acwr = dto.acwr
        weekRides = dto.weekRides
        weekBars = dto.weekBars
        isComputing = false
    }
}
