// Features/Workout/Data/PersistenceModels/LapSplit.swift
import Foundation
import SwiftData

@Model
final class LapSplit {
    var lapNumber: Int
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval = 0
    var avgPower: Double = 0
    var maxPower: Int = 0
    var avgCadence: Double = 0
    var avgSpeed: Double = 0
    var avgHR: Double = 0
    var distance: Double = 0

    var workout: Workout?

    init(lapNumber: Int, startTime: Date = .now) {
        self.lapNumber = lapNumber
        self.startTime = startTime
    }
}
