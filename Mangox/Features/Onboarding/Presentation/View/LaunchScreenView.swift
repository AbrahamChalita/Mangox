import SwiftUI

/// In-app launch screen shown while SwiftData and BLE initialize.
///
/// Animation sequence:
///   0.00s  — "Mangox" fades + scales in
///   0.55s  — loading dots appear and animate
///   1.40s  — (ready signal received) dots fade out, wordmark lifts + fades out
///
/// The exit is driven by `isVisible: Bool` from MangoxApp. Because the view
/// owns its own entry animation state, the exit always happens *after* the
/// entry has fully played — no mid-fade content pop.
struct LaunchScreenView: View {

    /// Set to false from outside to trigger the exit transition.
    let isVisible: Bool

    // MARK: - Internal animation state

    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkScale: Double = 0.88
    @State private var dotsVisible: Bool = false
    @State private var exitPhase: Bool = false   // true = exit animation running
    @State private var dotsRevealTask: Task<Void, Never>?
    @State private var exitPhaseTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            VStack(spacing: 22) {
                // Wordmark
                Text("Mangox")
                    .font(.system(size: 36, weight: .bold, design: .default))
                    .foregroundStyle(.white)
                    .tracking(1.5)
                    .scaleEffect(exitPhase ? 1.06 : wordmarkScale)
                    .opacity(exitPhase ? 0 : wordmarkOpacity)

                // Loading dots — three bouncing circles
                LoadingDotsView()
                    .opacity(dotsVisible && !exitPhase ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: dotsVisible)
                    .animation(.easeIn(duration: 0.25), value: exitPhase)
            }
        }
        // Full view fade handles the very final step so the background
        // doesn't flash when the wordmark has already gone transparent.
        .opacity(exitPhase ? 0 : 1)
        .animation(.easeIn(duration: 0.28), value: exitPhase)
        .allowsHitTesting(isVisible)

        // MARK: - Entry sequence
        .onAppear {
            // Step 1: wordmark fades + scales up
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
                wordmarkOpacity = 1
                wordmarkScale = 1.0
            }
            // Step 2: dots appear after wordmark settles
            dotsRevealTask?.cancel()
            dotsRevealTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                dotsVisible = true
            }
        }

        // MARK: - Exit sequence (triggered when isVisible becomes false)
        .onChange(of: isVisible) { _, newValue in
            guard !newValue else { return }
            // Dots fade out first (handled by their own opacity animation above).
            // Wordmark lifts and fades, then the background fades — staggered.
            exitPhaseTask?.cancel()
            exitPhaseTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                withAnimation(.easeIn(duration: 0.35)) {
                    exitPhase = true
                }
            }
        }
        .onDisappear {
            dotsRevealTask?.cancel()
            exitPhaseTask?.cancel()
        }
    }
}

// MARK: - Loading Dots

/// Three dots that bounce in a staggered wave loop.
private struct LoadingDotsView: View {
    @State private var animate = false

    private let dotSize: CGFloat = 6
    private let dotColor = AppColor.mango.opacity(0.7)
    private let delays: [Double] = [0, 0.18, 0.36]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(delays.indices, id: \.self) { i in
                Circle()
                    .fill(dotColor)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animate ? 1.0 : 0.4)
                    .opacity(animate ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(delays[i]),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}
