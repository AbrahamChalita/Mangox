// Core/Utilities/AudioCueManager.swift
import AVFoundation
import AudioToolbox
import os.log

nonisolated private let audioLogger = Logger(subsystem: "com.abchalita.Mangox", category: "AudioCue")

/// Plays spoken audio cues and system sounds during rides.
/// Uses AVSpeechSynthesizer for TTS and AudioServices for haptic-style chimes.
/// All methods are MainActor-isolated since AVSpeechSynthesizer requires the main thread.
@MainActor
final class AudioCueManager: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = AudioCueManager()

    private let synth = AVSpeechSynthesizer()
    private var isEnabled: Bool { RidePreferences.shared.stepAudioCueEnabled }
    private nonisolated(unsafe) var audioSessionObservers: [NotificationCenter.ObservationToken] = []

    private override init() {
        super.init()
        synth.delegate = self
        observeAudioSessionNotifications()
    }

    deinit {
        for token in audioSessionObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Speak a short phrase. Debounced to avoid overlapping speech.
    private var lastSpokenAt: ContinuousClock.Instant = .now
    private let minimumInterval: Duration = .seconds(1.5)

    func speak(_ text: String) {
        guard isEnabled else { return }
        let now = ContinuousClock.now
        if now - lastSpokenAt < minimumInterval { return }
        lastSpokenAt = now
        configureAudioSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utterance)
    }

    /// Play a short system chime (ascending tone).
    func chime() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1113) // "tock" — unintrusive
    }

    /// Play a success chime (triple tone).
    func successChime() {
        guard isEnabled else { return }
        AudioServicesPlaySystemSound(1057) // "ding-ding-ding"
    }

    // MARK: - Domain-Specific Cues

    func announceZoneChange(to zone: PowerZone) {
        speak("Zone \(zone.id), \(zone.name)")
    }

    func announceIntervalStart(title: String, duration: String, targetZone: Int, targetWatts: Int?) {
        var text = "\(title), \(duration), zone \(targetZone)"
        if let watts = targetWatts {
            text += ", \(watts) watts"
        }
        speak(text)
    }

    func announceIntervalCountdown(seconds: Int) {
        if seconds == 10 { speak("Ten seconds") }
        else if seconds == 5 { chime() }
        else if seconds <= 3 && seconds >= 1 { speak("\(seconds)") }
    }

    /// Short coaching line; independent of step / navigation cue toggles.
    func announceRideTip(script: String) {
        guard RidePreferences.shared.rideTipsAudioEnabled else { return }
        let now = ContinuousClock.now
        if now - lastSpokenAt < minimumInterval { return }
        lastSpokenAt = now
        configureAudioSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: script)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.78
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utterance)
    }

    func announceWorkoutComplete() {
        successChime()
        speak("Workout complete. Great ride.")
    }

    private func configureAudioSessionIfNeeded() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            audioLogger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func observeAudioSessionNotifications() {
        let session = AVAudioSession.sharedInstance()
        audioSessionObservers = [
            NotificationCenter.default.addObserver(
                of: session,
                for: AVAudioSession.DidBecomeInactiveMessage.self
            ) { [weak self] _ in
                self?.handleAudioSessionDidBecomeInactive()
            },
            NotificationCenter.default.addObserver(
                of: session,
                for: AVAudioSession.ResumptionRecommendationMessage.self
            ) { [weak self] _ in
                self?.handleAudioSessionResumptionRecommendation()
            },
        ]
    }

    private func handleAudioSessionDidBecomeInactive() {
        if synth.isSpeaking {
            synth.pauseSpeaking(at: .immediate)
        }
    }

    private func handleAudioSessionResumptionRecommendation() {
        if synth.isPaused {
            configureAudioSessionIfNeeded()
            synth.continueSpeaking()
        }
    }
}
