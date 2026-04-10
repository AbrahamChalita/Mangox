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

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                switch state {
                case .idle:
                    actionButton("START", icon: "play.fill", color: AppColor.mango) {
                        onStart()
                    }

                case .recording:
                    actionButton("PAUSE", icon: "pause.fill", color: Color(red: 240/255, green: 195/255, blue: 78/255)) {
                        onPause()
                    }
                    if showLap {
                        actionButton("LAP", icon: "flag.fill", color: Color(red: 107/255, green: 127/255, blue: 212/255)) {
                            onLap()
                        }
                    }
                    endButton

                case .paused:
                    actionButton("RESUME", icon: "play.fill", color: AppColor.mango) {
                        onResume()
                    }
                    endButton

                case .autoPaused:
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

                    // Manual resume button
                    actionButton("RESUME", icon: "play.fill", color: AppColor.mango) {
                        onResume()
                    }

                    endButton

                case .finished:
                    EmptyView()
                }
            }
        }
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
