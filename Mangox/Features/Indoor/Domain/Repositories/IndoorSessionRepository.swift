// Features/Indoor/Domain/Repositories/IndoorSessionRepository.swift
import Foundation

/// Domain contract for managing an indoor training session lifecycle.
/// Concrete implementation: coordinates BLEManager + DataSourceCoordinator in Data layer.
@MainActor
protocol IndoorSessionRepository: AnyObject {
    var isConnected: Bool { get }
    var isRecording: Bool { get }
    var currentMetrics: CyclingMetrics { get }
    var elapsedSeconds: Int { get }

    /// Attempts to start a workout recording session.
    func startRecording() async throws

    /// Pauses the current recording.
    func pauseRecording()

    /// Resumes a paused recording.
    func resumeRecording()

    /// Stops recording and returns the completed workout ready for saving.
    func stopRecording() async throws -> Workout
}
