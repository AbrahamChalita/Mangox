import SwiftUI

/// Pause-aware wall-clock inputs for deriving active session elapsed time in views.
struct SessionElapsedTiming: Equatable {
    let startDate: Date
    let totalPausedDuration: TimeInterval
    let pauseStartedAt: Date?

    func elapsedSeconds(at date: Date) -> TimeInterval {
        var pauseTime = totalPausedDuration
        if let pauseStartedAt {
            pauseTime += date.timeIntervalSince(pauseStartedAt)
        }
        return max(0, date.timeIntervalSince(startDate) - pauseTime)
    }
}

struct SessionElapsedStyle: Equatable {
    var font: Font = .body
    var foregroundStyle: Color = AppColor.fg0
    var monospacedDigit: Bool = true
    var tracking: CGFloat = 0
    var minimumScaleFactor: CGFloat = 1.0
    var multilineTextAlignment: TextAlignment = .center

    static let `default` = SessionElapsedStyle()
}

/// Live elapsed-time readout driven by `TimelineView` instead of manager tick observation.
struct SessionElapsedLabel: View, Equatable {
    let timing: SessionElapsedTiming?
    let placeholder: String
    var style: SessionElapsedStyle = .default
    var accessibilityLabel: String = "Elapsed time"

    static func == (lhs: SessionElapsedLabel, rhs: SessionElapsedLabel) -> Bool {
        lhs.timing == rhs.timing
            && lhs.placeholder == rhs.placeholder
            && lhs.style == rhs.style
            && lhs.accessibilityLabel == rhs.accessibilityLabel
    }

    var body: some View {
        Group {
            if let timing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    elapsedText(AppFormat.duration(timing.elapsedSeconds(at: context.date)))
                }
            } else {
                elapsedText(placeholder)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func elapsedText(_ value: String) -> some View {
        let text = Text(value)
            .font(style.font)
            .foregroundStyle(style.foregroundStyle)
            .tracking(style.tracking)
            .lineLimit(1)
            .minimumScaleFactor(style.minimumScaleFactor)
            .multilineTextAlignment(style.multilineTextAlignment)
            .accessibilityValue(value)

        if style.monospacedDigit {
            text.monospacedDigit()
        } else {
            text
        }
    }
}
