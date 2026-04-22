import SwiftUI

struct WorkoutControlBar: View {
    let state: RecordingState
    @Binding var isScreenLocked: Bool
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onLap: () -> Void
    /// Parent shows the same custom end/discard sheet as outdoor (dimmed overlay + card).
    @Binding var showEndConfirmation: Bool
    var showLap: Bool = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            switch state {
            case .idle:
                HStack(spacing: 24) {
                    Spacer()
                    heroCircleButton(
                        icon: "play.fill",
                        color: AppColor.mango,
                        accessibilityLabel: String(localized: "indoor.workout.start_accessibility"),
                        action: onStart
                    )
                    Spacer()
                }

            case .recording:
                HStack(spacing: 24) {
                    HStack(spacing: 12) {
                        smallCircleButton(
                            icon: "lock.fill",
                            tint: isScreenLocked ? AppColor.mango : AppColor.fg3,
                            accessibilityLabel: isScreenLocked ? "Screen unlocked" : "Screen locked",
                            action: { isScreenLocked.toggle() }
                        )
                        if showLap {
                            smallCircleButton(
                                icon: "flag.fill",
                                tint: AppColor.blue,
                                accessibilityLabel: String(localized: "indoor.workout.lap_accessibility"),
                                action: onLap
                            )
                        }
                    }
                    Spacer()
                    heroCircleButton(
                        icon: "pause.fill",
                        color: AppColor.yellow,
                        accessibilityLabel: String(localized: "indoor.workout.pause_accessibility"),
                        action: onPause
                    )
                    Spacer()
                    smallCircleButton(
                        icon: "stop.fill",
                        tint: AppColor.red,
                        accessibilityLabel: String(localized: "indoor.workout.end_accessibility"),
                        action: { showEndConfirmation = true }
                    )
                }

            case .paused:
                HStack(spacing: 24) {
                    smallCircleButton(
                        icon: "lock.fill",
                        tint: isScreenLocked ? AppColor.mango : AppColor.fg3,
                        accessibilityLabel: isScreenLocked ? "Screen unlocked" : "Screen locked",
                        action: { isScreenLocked.toggle() }
                    )
                    Spacer()
                    heroCircleButton(
                        icon: "play.fill",
                        color: AppColor.mango,
                        accessibilityLabel: String(localized: "indoor.workout.resume_accessibility"),
                        action: onResume
                    )
                    Spacer()
                    smallCircleButton(
                        icon: "stop.fill",
                        tint: AppColor.red,
                        accessibilityLabel: String(localized: "indoor.workout.end_accessibility"),
                        action: { showEndConfirmation = true }
                    )
                }

            case .autoPaused:
                VStack(spacing: 12) {
                    autoPausedStatus
                    HStack(spacing: 24) {
                        smallCircleButton(
                            icon: "lock.fill",
                            tint: isScreenLocked ? AppColor.mango : AppColor.fg3,
                            accessibilityLabel: isScreenLocked ? "Screen unlocked" : "Screen locked",
                            action: { isScreenLocked.toggle() }
                        )
                        Spacer()
                        heroCircleButton(
                            icon: "play.fill",
                            color: AppColor.mango,
                            accessibilityLabel: String(localized: "indoor.workout.resume_accessibility"),
                            action: onResume
                        )
                        Spacer()
                        smallCircleButton(
                            icon: "stop.fill",
                            tint: AppColor.red,
                            accessibilityLabel: String(localized: "indoor.workout.end_accessibility"),
                            action: { showEndConfirmation = true }
                        )
                    }
                }

            case .finished:
                EmptyView()
            }
        }
    }

    private var autoPausedStatus: some View {
        VStack(spacing: 5) {
            HStack(spacing: 6) {
                ProgressView()
                    .tint(AppColor.yellow.opacity(0.6))
                    .scaleEffect(0.7)
                Text("AUTO-PAUSED")
                    .mangoxFont(.caption)
                    .foregroundStyle(AppColor.yellow)
                    .tracking(1)
            }
            Text(String(localized: "indoor.workout.auto_pause_detail"))
                .mangoxFont(.micro)
                .foregroundStyle(AppColor.fg3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(AppColor.wash(for: AppColor.yellow))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue)
                .strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1)
        )
    }

    private func heroCircleButton(
        icon: String,
        color: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(color, in: Circle())
                .shadow(color: color.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func smallCircleButton(
        icon: String,
        tint: Color,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(AppColor.bg2, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(tint.opacity(0.4), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
