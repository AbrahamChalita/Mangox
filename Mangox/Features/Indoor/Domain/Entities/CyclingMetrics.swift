// Features/Indoor/Domain/Entities/CyclingMetrics.swift
import Foundation

enum HRSource: String, Sendable {
    case none
    case ftmsEmbedded
    case dedicated
}

struct CyclingMetrics: Sendable {
    var power: Int = 0           // watts
    var cadence: Double = 0      // rpm
    var speed: Double = 0        // km/h
    var heartRate: Int = 0       // bpm
    var hrSource: HRSource = .none
    var totalDistance: Double = 0 // meters
    /// True only when this snapshot’s transport actually included total distance (BLE FTMS bit 4, Wi‑Fi field, etc.).
    /// Odometer may legitimately read `0`; do not infer presence from `totalDistance > 0`.
    var includesTotalDistanceInPacket: Bool = false
    var lastUpdate: Date?
}
