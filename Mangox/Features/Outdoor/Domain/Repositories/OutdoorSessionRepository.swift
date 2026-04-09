// Features/Outdoor/Domain/Repositories/OutdoorSessionRepository.swift
import Foundation

/// Domain contract for managing an outdoor GPS ride session lifecycle.
/// Concrete implementation: coordinates LocationManager + RouteManager in Data layer.
@MainActor
protocol OutdoorSessionRepository: AnyObject {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var currentMetrics: CyclingMetrics { get }
    var elapsedSeconds: Int { get }
    var distanceMeters: Double { get }
    var elevationGainMeters: Double { get }

    /// Requests location permissions and begins GPS recording.
    func startRecording() async throws

    /// Pauses GPS recording while preserving session state.
    func pauseRecording()

    /// Resumes a paused outdoor recording.
    func resumeRecording()

    /// Stops recording and returns the completed workout ready for saving.
    func stopRecording() async throws -> Workout
}
