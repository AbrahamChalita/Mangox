// Features/Workout/Data/PersistenceModels/WorkoutSample.swift
import Foundation
import SwiftData

@Model
final class WorkoutSample {
    var timestamp: Date
    var elapsedSeconds: Int      // monotonic, excludes pauses
    var power: Int = 0
    var cadence: Double = 0
    var speed: Double = 0        // km/h
    var heartRate: Int = 0

    var workout: Workout?

    init(timestamp: Date = .now, elapsedSeconds: Int, power: Int, cadence: Double, speed: Double, heartRate: Int) {
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.power = power
        self.cadence = cadence
        self.speed = speed
        self.heartRate = heartRate
    }
}
