import SwiftUI
import SwiftData

struct CoachSessionsSheet: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.dismiss) private var dismiss

    private static let sessionsDescriptor: FetchDescriptor<ChatSession> = {
        var d = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        d.fetchLimit = 400
        return d
    }()

    @Query(Self.sessionsDescriptor) private var sessions: [ChatSession]

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    private enum DeleteConfirmKind: String, Identifiable {
        case selection, all
        var id: String { rawValue }
    }
    @State private var deleteConfirm: DeleteConfirmKind?

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sessions) { session in
                        rowView(session)
                            .listRowBackground(Color.white.opacity(0.04))
                    }
                    .onDelete(perform: deleteSessionsAtOffsets)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .deleteDisabled(isSelecting)
            }
        }
        .background(AppColor.bg.ignoresSafeArea())
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button("Cancel") {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                    .foregroundStyle(.white.opacity(0.75))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if sessions.isEmpty {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppColor.mango)
                        .fontWeight(.semibold)
                } else if isSelecting {
                    HStack(spacing: 16) {
                        Button("Select All") {
                            selectedIDs = Set(sessions.map(\.id))
                        }
                        .foregroundStyle(AppColor.mango)
                        .fontWeight(.semibold)
                        .disabled(selectedIDs.count == sessions.count)

                        Button("Delete") {
                            deleteConfirm = .selection
                        }
                        .foregroundStyle(selectedIDs.isEmpty ? .white.opacity(0.25) : AppColor.red)
                        .fontWeight(.semibold)
                        .disabled(selectedIDs.isEmpty)
                    }
                } else {
                    HStack(spacing: 16) {
                        Menu {
                            Button {
                                isSelecting = true
                                selectedIDs.removeAll()
                            } label: {
                                Label("Select conversations", systemImage: "checkmark.circle")
                            }
                            Button(role: .destructive) {
                                deleteConfirm = .all
                            } label: {
                                Label("Delete all conversations", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        Button("Done") { dismiss() }
                            .foregroundStyle(AppColor.mango)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .fullScreenCover(item: $deleteConfirm) { kind in
            deleteConfirmCover(kind)
                .presentationBackground(.clear)
        }
    }

    @ViewBuilder
    private func rowView(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(
                        selectedIDs.contains(session.id)
                            ? AppColor.mango
                            : .white.opacity(0.28)
                    )
                    .frame(width: 28)
            }

            sessionRow(session)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIDs.contains(session.id) {
                    selectedIDs.remove(session.id)
                } else {
                    selectedIDs.insert(session.id)
                }
            } else {
                coachViewModel.switchToSession(session.id)
                dismiss()
            }
        }
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        session.id == coachViewModel.currentSessionID
                            ? AppColor.mango.opacity(0.22)
                            : Color.white.opacity(0.06)
                    )
                    .frame(width: 40, height: 40)
                Image(systemName: session.id == coachViewModel.currentSessionID ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 16))
                    .foregroundStyle(
                        session.id == coachViewModel.currentSessionID
                            ? AppColor.mango
                            : .white.opacity(0.4)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(formatRelativeDate(session.updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()

            if session.id == coachViewModel.currentSessionID, !isSelecting {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColor.mango)
            }
        }
        .padding(.vertical, 4)
    }

    private func removeSessions(ids: Set<UUID>) {
        for id in ids {
            coachViewModel.deleteSession(id)
        }
    }

    private func deleteSessionsAtOffsets(_ offsets: IndexSet) {
        guard !isSelecting else { return }
        let ids = offsets.compactMap { sessions.indices.contains($0) ? sessions[$0].id : nil }
        removeSessions(ids: Set(ids))
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.minute, .hour, .day, .weekOfYear], from: date, to: now)
        if let mins = components.minute, mins < 1 { return "Just now" }
        if let mins = components.minute, mins < 60 { return "\(mins)m ago" }
        if let hours = components.hour, hours < 24 { return "\(hours)h ago" }
        if let days = components.day, days < 7 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func deleteConfirmCover(_ kind: DeleteConfirmKind) -> some View {
        let title: String
        let message: String
        let confirmLabel: String
        let onConfirm: () -> Void

        switch kind {
        case .selection:
            let n = selectedIDs.count
            title = "Delete \(n) conversation\(n == 1 ? "" : "s")?"
            message = "This can't be undone."
            confirmLabel = "Delete"
            onConfirm = {
                removeSessions(ids: selectedIDs)
                selectedIDs.removeAll()
                isSelecting = false
            }
        case .all:
            let n = sessions.count
            title = "Delete all \(n) conversation\(n == 1 ? "" : "s")?"
            message = "Permanently removes all chat history. This can't be undone."
            confirmLabel = "Delete all"
            onConfirm = {
                removeSessions(ids: Set(sessions.map(\.id)))
                isSelecting = false
                selectedIDs.removeAll()
            }
        }

        return ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture { deleteConfirm = nil }

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        deleteConfirm = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button {
                        deleteConfirm = nil
                        onConfirm()
                    } label: {
                        Text(confirmLabel)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(AppColor.red.opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColor.bg)
                    .shadow(color: .black.opacity(0.45), radius: 30, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.18))
            Text("No conversations yet")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
