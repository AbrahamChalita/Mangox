import SwiftUI
import SwiftData

struct ChatHistoryView: View {
    @Environment(AIService.self) private var aiService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\ChatSession.updatedAt, order: .reverse)])
    private var sessions: [ChatSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.mango)
                }
            }
        }
    }

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                sessionRow(session)
            }
            .onDelete(perform: deleteSessions)
        }
        .listStyle(.plain)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        Button {
            aiService.switchToSession(session.id, modelContext: modelContext)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            session.id == aiService.currentSessionID
                                ? AppColor.mango.opacity(0.2)
                                : Color.white.opacity(0.06)
                        )
                        .frame(width: 40, height: 40)
                    Image(systemName: session.id == aiService.currentSessionID ? "bubble.left.fill" : "bubble.left")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            session.id == aiService.currentSessionID
                                ? AppColor.mango
                                : .white.opacity(0.4)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    Text(formatRelativeDate(session.updatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }

                Spacer()

                if session.id == aiService.currentSessionID {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.mango)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            aiService.deleteSession(sessions[index].id, modelContext: modelContext)
        }
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        if let mins = components.minute, mins < 1 {
            return "Just now"
        }
        if let mins = components.minute, mins < 60 {
            return "\(mins)m ago"
        }
        if let hours = components.hour, hours < 24 {
            return "\(hours)h ago"
        }
        if let days = components.day, days < 7 {
            return "\(days)d ago"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.2))

            Text("No conversations yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))

            Text("Your chat history will appear here")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.3))
        }
    }
}
