import SwiftUI

/// Infers plan-intake step labels for the progress strip under coach follow-up panels.
enum CoachPlanIntakeProgress {
    static let defaultTotalSteps = 4

    struct Snapshot: Equatable {
        let step: Int
        let total: Int
        let fieldLabel: String
    }

    static func snapshot(for message: ChatMessage) -> Snapshot? {
        guard message.role == .assistant, message.category != "error" else { return nil }
        guard CoachMessagePresentation.shouldShowPlanIntakeChrome(for: message) else { return nil }

        if message.followUpBlocks.count > 1 {
            return Snapshot(
                step: 1,
                total: message.followUpBlocks.count,
                fieldLabel: "Plan setup"
            )
        }

        let question = (
            message.followUpBlocks.first?.question
                ?? message.followUpQuestion
                ?? ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return nil }

        let lower = question.lowercased()

        if lower.contains("route") || lower.contains("distance") || lower.contains("elevation") {
            return Snapshot(step: 5, total: 5, fieldLabel: "Route option")
        }
        if lower.contains("experience") || lower.contains("beginner") || lower.contains("level") {
            return Snapshot(step: 4, total: defaultTotalSteps, fieldLabel: "Experience")
        }
        if lower.contains("hour") || lower.contains("weekly") || lower.contains("volume") {
            return Snapshot(step: 3, total: defaultTotalSteps, fieldLabel: "Weekly hours")
        }
        if lower.contains("date") || lower.contains("when") || lower.contains("race day") {
            return Snapshot(step: 2, total: defaultTotalSteps, fieldLabel: "Event date")
        }
        if lower.contains("event") || lower.contains("goal") || lower.contains("race") || lower.contains("plan") {
            return Snapshot(step: 1, total: defaultTotalSteps, fieldLabel: "Event & goal")
        }
        return Snapshot(step: 1, total: defaultTotalSteps, fieldLabel: "Plan setup")
    }

    static func fieldLabel(forQuestion question: String) -> String {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Plan setup" }
        let lower = trimmed.lowercased()
        if lower.contains("route") || lower.contains("distance") || lower.contains("elevation") {
            return "Route option"
        }
        if lower.contains("experience") || lower.contains("beginner") || lower.contains("level") {
            return "Experience"
        }
        if lower.contains("hour") || lower.contains("weekly") || lower.contains("volume") {
            return "Weekly hours"
        }
        if lower.contains("date") || lower.contains("when") || lower.contains("race day") {
            return "Event date"
        }
        if lower.contains("event") || lower.contains("goal") || lower.contains("race") || lower.contains("plan") {
            return "Event & goal"
        }
        return "Plan setup"
    }
}

struct CoachPlanIntakeProgressStrip: View {
    let snapshot: CoachPlanIntakeProgress.Snapshot

    private var progress: Double {
        guard snapshot.total > 0 else { return 0 }
        return Double(min(snapshot.step, snapshot.total)) / Double(snapshot.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan setup")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.mango.opacity(0.9))
                Spacer(minLength: 0)
                Text("Step \(snapshot.step) of \(snapshot.total)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: snapshot.step)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(AppColor.mango.opacity(0.85))
                        .frame(width: max(8, geo.size.width * progress))
                }
            }
            .frame(height: 4)
            .animation(.smooth(duration: 0.45), value: snapshot.step)
            .animation(.smooth(duration: 0.45), value: snapshot.total)

            Text(snapshot.fieldLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppColor.mango.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Plan setup step \(snapshot.step) of \(snapshot.total), \(snapshot.fieldLabel)")
    }
}

enum CoachChatMotionSupport {
    static func animation(reduceMotion: Bool, _ preferred: Animation) -> Animation {
        reduceMotion ? .default : preferred
    }
}

enum CoachChipSentState {
    static func key(messageID: UUID, action: SuggestedAction) -> String {
        "\(messageID.uuidString)|\(CoachChipPresentation.displayTitle(for: action))"
    }
}

enum CoachMessageTimestampFormatting {
    static func shouldShow(before previous: ChatMessage?, current: ChatMessage) -> Bool {
        guard let previous else { return true }
        return shouldShow(previousTimestamp: previous.timestamp, current: current.timestamp)
    }

    static func shouldShow(previousTimestamp: Date?, current: Date) -> Bool {
        guard let previousTimestamp else { return true }
        return current.timeIntervalSince(previousTimestamp) > 300
    }

    static func label(for date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday \(date.formatted(date: .omitted, time: .shortened))"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
