import SwiftUI

struct WorkoutControlBar: View {
    let state: RecordingState
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
                actionButton("START", icon: "play.fill", color: AppColor.mango, action: onStart)

            case .recording:
                recordingControls

            case .paused:
                if dynamicTypeSize.isAccessibilitySize {
                    stackedPausedControls
                } else {
                    HStack(spacing: 12) {
                        actionButton("RESUME", icon: "play.fill", color: AppColor.mango, action: onResume)
                        endButton
                    }
                }

            case .autoPaused:
                autoPausedControls

            case .finished:
                EmptyView()
            }
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 12) {
            actionButton(
                "PAUSE",
                icon: "pause.fill",
                color: Color(red: 240/255, green: 195/255, blue: 78/255),
                action: onPause
            )

            if showLap {
                HStack(spacing: 12) {
                    actionButton(
                        "LAP",
                        icon: "flag.fill",
                        color: Color(red: 107/255, green: 127/255, blue: 212/255),
                        action: onLap
                    )
                    endButton
                }
            } else {
                endButton
            }
        }
    }

    private var stackedPausedControls: some View {
        VStack(spacing: 12) {
            actionButton("RESUME", icon: "play.fill", color: AppColor.mango, action: onResume)
            endButton
        }
    }

    private var autoPausedControls: some View {
        VStack(spacing: 12) {
            autoPausedStatus
            HStack(spacing: 12) {
                actionButton("RESUME", icon: "play.fill", color: AppColor.mango, action: onResume)
                endButton
            }
        }
    }

    private var autoPausedStatus: some View {
        HStack(spacing: 6) {
            ProgressView()
                .tint(AppColor.yellow.opacity(0.6))
                .scaleEffect(0.7)
            Text("AUTO-PAUSED")
                .mangoxFont(.caption)
                .foregroundStyle(AppColor.yellow)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColor.wash(for: AppColor.yellow))
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue))
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.button.rawValue)
                .strokeBorder(AppColor.yellow.opacity(0.25), lineWidth: 1)
        )
    }

    private func actionButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .mangoxFont(.callout)
                    .tracking(0.5)
            }
            .mangoxButtonChrome(.primary, tint: color)
        }
        .buttonStyle(MangoxPressStyle())
    }

    private var endButton: some View {
        Button {
            showEndConfirmation = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                Text("END")
                    .mangoxFont(.callout)
                    .tracking(0.5)
            }
            .padding(.horizontal, 20)
            .mangoxButtonChrome(.destructive)
        }
        .buttonStyle(MangoxPressStyle())
    }
}
