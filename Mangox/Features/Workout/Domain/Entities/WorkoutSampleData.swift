// Features/Workout/Domain/Entities/WorkoutSampleData.swift
import Foundation

public struct WorkoutSampleData: Sendable {
    public let timestamp: Date
    public let elapsedSeconds: Int
    public let power: Int
    public let cadence: Double
    public let speed: Double
    public let heartRate: Int

    nonisolated public init(
        timestamp: Date, elapsedSeconds: Int, power: Int, cadence: Double, speed: Double,
        heartRate: Int
    ) {
        self.timestamp = timestamp
        self.elapsedSeconds = elapsedSeconds
        self.power = power
        self.cadence = cadence
        self.speed = speed
        self.heartRate = heartRate
    }
}
