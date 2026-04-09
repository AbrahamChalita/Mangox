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
    private var audioInterruptionObserver: NSObjectProtocol?

    private override init() {
        super.init()
        synth.delegate = self
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            // Delivered on `.main`; avoid `Task` so `Notification` is not captured in a `@Sendable` async hop.
            MainActor.assumeIsolated {
                self.handleAudioInterruption(notification)
            }
        }
    }

    deinit {
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
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

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }

        switch type {
        case .began:
            if synth.isSpeaking {
                synth.pauseSpeaking(at: .immediate)
            }
        case .ended:
            configureAudioSessionIfNeeded()
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume),
               synth.isPaused {
                synth.continueSpeaking()
            }
        @unknown default:
            break
        }
    }
}
