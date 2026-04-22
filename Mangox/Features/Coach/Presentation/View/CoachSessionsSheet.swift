import SwiftUI
import SwiftData

struct CoachSessionsSheet: View {
    @Environment(CoachViewModel.self) private var coachViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

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

    private var textPrimary: Color { .white.opacity(AppOpacity.textPrimary) }
    private var textSecondary: Color { .white.opacity(AppOpacity.textSecondary) }
    private var textTertiary: Color { .white.opacity(AppOpacity.textTertiary) }

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyState
            } else {
                sessionsList
            }
        }
        .background(AppColor.bg.ignoresSafeArea())
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button("Cancel") {
                        withAnimation(accessibilityReduceMotion ? .none : MangoxMotion.standard) {
                            isSelecting = false
                            selectedIDs.removeAll()
                        }
                    }
                    .foregroundStyle(textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                toolbarTrailingContent
            }
        }
        .overlay {
            if let kind = deleteConfirm {
                deleteConfirmationOverlay(for: kind)
                    .zIndex(300)
                    .transition(.opacity)
            }
        }
        .animation(accessibilityReduceMotion ? .none : MangoxMotion.smooth, value: deleteConfirm?.id)
    }

    @ViewBuilder
    private var toolbarTrailingContent: some View {
        if sessions.isEmpty {
            Button("Done") { dismiss() }
                .foregroundStyle(AppColor.mango)
                .fontWeight(.semibold)
        } else if isSelecting {
            HStack(spacing: MangoxSpacing.lg.rawValue) {
                Button("Select All") {
                    withAnimation(accessibilityReduceMotion ? .none : MangoxMotion.micro) {
                        selectedIDs = Set(sessions.map(\.id))
                    }
                }
                .foregroundStyle(AppColor.mango)
                .fontWeight(.semibold)
                .disabled(selectedIDs.count == sessions.count)

                Button("Delete") {
                    deleteConfirm = .selection
                }
                .foregroundStyle(selectedIDs.isEmpty ? textTertiary : AppColor.red)
                .fontWeight(.semibold)
                .disabled(selectedIDs.isEmpty)
            }
        } else {
            HStack(spacing: MangoxSpacing.lg.rawValue) {
                Menu {
                    Button {
                        withAnimation(accessibilityReduceMotion ? .none : MangoxMotion.micro) {
                            isSelecting = true
                            selectedIDs.removeAll()
                        }
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
                        .foregroundStyle(textSecondary)
                }

                Button("Done") { dismiss() }
                    .foregroundStyle(AppColor.mango)
                    .fontWeight(.semibold)
            }
        }
    }

    private var sessionsList: some View {
        ScrollView {
            LazyVStack(spacing: MangoxSpacing.sm.rawValue) {
                ForEach(sessions) { session in
                    sessionCard(session)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                removeSessions(ids: [session.id])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(.horizontal, MangoxSpacing.md.rawValue)
            .padding(.vertical, MangoxSpacing.md.rawValue)
        }
        .scrollIndicators(.hidden)
        .animation(accessibilityReduceMotion ? .none : MangoxMotion.smooth, value: sessions.map(\.id))
    }

    @ViewBuilder
    private func sessionCard(_ session: ChatSession) -> some View {
        HStack(spacing: MangoxSpacing.md.rawValue) {
            if isSelecting {
                selectionIndicator(for: session)
            }

            sessionRow(session)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleSessionTap(session)
        }
    }

    @ViewBuilder
    private func selectionIndicator(for session: ChatSession) -> some View {
        let isSelected = selectedIDs.contains(session.id)
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? AppColor.mango : textTertiary)
            .frame(width: 28)
            .contentTransition(.interpolate)
    }

    private func sessionRow(_ session: ChatSession) -> some View {
        let isCurrentSession = session.id == coachViewModel.currentSessionID

        return HStack(spacing: MangoxSpacing.md.rawValue) {
            sessionIcon(isCurrentSession: isCurrentSession)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(MangoxFont.bodyBold.value)
                    .foregroundStyle(textPrimary)
                    .lineLimit(1)

                Text(formatRelativeDate(session.updatedAt))
                    .font(MangoxFont.caption.value)
                    .foregroundStyle(textTertiary)
            }

            Spacer(minLength: 0)

            if isCurrentSession && !isSelecting {
                currentSessionBadge
            }
        }
        .padding(MangoxSpacing.md.rawValue)
        .background {
            if isSelecting && selectedIDs.contains(session.id) {
                RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous)
                    .fill(AppColor.mango.opacity(0.08))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous)
                .strokeBorder(
                    isCurrentSession ? AppColor.mango.opacity(0.3) : Color.white.opacity(AppOpacity.cardBorder),
                    lineWidth: isCurrentSession ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: MangoxRadius.card.rawValue, style: .continuous))
        .buttonStyle(MangoxPressStyle())
    }

    private func sessionIcon(isCurrentSession: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isCurrentSession ? AppColor.mango.opacity(0.22) : Color.white.opacity(AppOpacity.pillBg))
                .frame(width: 44, height: 44)

            Image(systemName: isCurrentSession ? "bubble.left.fill" : "bubble.left")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isCurrentSession ? AppColor.mango : textTertiary)
        }
    }

    private var currentSessionBadge: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(AppColor.mango)
            .contentTransition(.interpolate)
    }

    private func handleSessionTap(_ session: ChatSession) {
        if isSelecting {
            withAnimation(accessibilityReduceMotion ? .none : MangoxMotion.micro) {
                if selectedIDs.contains(session.id) {
                    selectedIDs.remove(session.id)
                } else {
                    selectedIDs.insert(session.id)
                }
            }
        } else {
            coachViewModel.switchToSession(session.id)
            dismiss()
        }
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

    private var emptyState: some View {
        VStack(spacing: MangoxSpacing.lg.rawValue) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(AppOpacity.pillBg))
                    .frame(width: 88, height: 88)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36))
                    .foregroundStyle(textTertiary)
            }

            VStack(spacing: MangoxSpacing.xs.rawValue) {
                Text("No conversations yet")
                    .font(MangoxFont.title.value)
                    .foregroundStyle(textPrimary)

                Text("Start a new chat with your coach")
                    .font(MangoxFont.body.value)
                    .foregroundStyle(textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 80)
    }

    private func deleteConfirmationPayload(for kind: DeleteConfirmKind)
        -> (title: String, message: String, confirmLabel: String, onCommit: () -> Void)
    {
        switch kind {
        case .selection:
            let n = selectedIDs.count
            return (
                "Delete \(n) conversation\(n == 1 ? "" : "s")?",
                "This can't be undone.",
                "Delete",
                {
                    removeSessions(ids: selectedIDs)
                    selectedIDs.removeAll()
                    isSelecting = false
                }
            )
        case .all:
            let n = sessions.count
            return (
                "Delete all \(n) conversation\(n == 1 ? "" : "s")?",
                "Permanently removes all chat history. This can't be undone.",
                "Delete all",
                {
                    removeSessions(ids: Set(sessions.map(\.id)))
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            )
        }
    }

    private func deleteConfirmationOverlay(for kind: DeleteConfirmKind) -> some View {
        let p = deleteConfirmationPayload(for: kind)
        return MangoxConfirmOverlay(
            title: p.title,
            message: p.message,
            onDismiss: { deleteConfirm = nil }
        ) {
            MangoxConfirmDualButtonRow(
                cancelTitle: "Cancel",
                confirmTitle: p.confirmLabel,
                trailingStyle: .destructive,
                onCancel: { deleteConfirm = nil },
                onConfirm: {
                    deleteConfirm = nil
                    p.onCommit()
                }
            )
        }
    }
}
