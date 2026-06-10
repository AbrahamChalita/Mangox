import SwiftUI
import SwiftData

/// Saved interval workouts (AI-generated, ZWO imports) for the Coach hub and "My workouts" sheet.
struct CoachWorkoutsPanel: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var navigationPath: NavigationPath
    var dismissParentChat: Binding<Bool>? = nil
    var showsIntroCopy: Bool = true
    var showsSectionHeader: Bool = true
    var onOpenChat: (() -> Void)? = nil

    private static let templatesDescriptor: FetchDescriptor<CustomWorkoutTemplate> = {
        var d = FetchDescriptor<CustomWorkoutTemplate>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        d.fetchLimit = 128
        return d
    }()

    @Query(Self.templatesDescriptor) private var templates: [CustomWorkoutTemplate]

    @State private var templatePendingDelete: CustomWorkoutTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsIntroCopy {
                Text("Workouts you save from chat appear here and sync to your account. Start them indoors from this list or Indoor → Connection.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsSectionHeader {
                sectionHeader("Your workouts")
            }

            if templates.isEmpty {
                workoutsEmptyState
            } else {
                ForEach(templates, id: \.id) { template in
                    workoutCard(template)
                }
            }
        }
        .padding(.bottom, 16)
        .overlay {
            if let template = templatePendingDelete {
                MangoxConfirmOverlay(
                    title: "Delete this workout?",
                    message: "Removes \"\(template.name)\" from your library. This can't be undone.",
                    onDismiss: { templatePendingDelete = nil }
                ) {
                    MangoxConfirmDualButtonRow(
                        cancelTitle: "Cancel",
                        confirmTitle: "Delete workout",
                        trailingStyle: .destructive,
                        onCancel: { templatePendingDelete = nil },
                        onConfirm: {
                            templatePendingDelete = nil
                            deleteTemplate(template)
                        }
                    )
                }
                .zIndex(300)
                .transition(.opacity)
            }
        }
        .animation(MangoxMotion.smooth, value: templatePendingDelete?.id)
    }

    private func dismissParentChatIfNeeded() {
        dismissParentChat?.wrappedValue = false
    }

    private var workoutsEmptyState: some View {
        VStack(alignment: .leading, spacing: MangoxSpacing.lg.rawValue) {
            VStack(alignment: .leading, spacing: MangoxSpacing.sm.rawValue) {
                Text("Workout library")
                    .mangoxFont(.label)
                    .foregroundStyle(AppColor.fg3)
                    .tracking(1.4)
                    .textCase(.uppercase)

                Text("No saved workouts yet")
                    .mangoxFont(.bodyBold)
                    .foregroundStyle(AppColor.fg0)

                Text("Ask your coach for a single session — threshold, endurance, recovery — then tap Save workout when it looks right.")
                    .mangoxFont(.body)
                    .foregroundStyle(AppColor.fg1)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }

            if let onOpenChat {
                Button(action: onOpenChat) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Build a workout")
                            .mangoxFont(.callout)
                    }
                    .foregroundStyle(AppColor.bg0)
                    .padding(.horizontal, MangoxSpacing.xl.rawValue)
                    .padding(.vertical, 11)
                    .background(AppColor.mango)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(AppColor.mango.opacity(0.45), lineWidth: 1)
                    )
                }
                .buttonStyle(MangoxPressStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, MangoxSpacing.xl.rawValue)
        .padding(.vertical, MangoxSpacing.xxl.rawValue)
        .mangoxSurface(.flatSubtle, shape: .rounded(MangoxRadius.overlay.rawValue))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .mangoxFont(.label)
            .foregroundStyle(AppColor.fg3)
            .tracking(1.4)
    }

    private func workoutCard(_ template: CustomWorkoutTemplate) -> some View {
        let totalMinutes = max(1, template.intervals.reduce(0) { $0 + $1.totalSeconds } / 60)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Color.clear
                        .frame(width: 42, height: 42)
                        .mangoxSurface(
                            .flatCustom(fill: AppColor.bg1, border: AppColor.mango.opacity(0.32)),
                            shape: .rounded(MangoxRadius.sharp.rawValue)
                        )
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.mango)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("SAVED WORKOUT")
                        .mangoxFont(.label)
                        .foregroundStyle(AppColor.mango)
                        .tracking(1.4)

                    Text(template.name)
                        .font(MangoxFont.value.value)
                        .foregroundStyle(.white.opacity(AppOpacity.textPrimary))
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)

                    Text("Saved \(template.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .mangoxFont(.caption)
                        .foregroundStyle(.white.opacity(AppOpacity.textTertiary))
                }

                Spacer(minLength: 6)

                Button {
                    templatePendingDelete = template
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.fg2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete workout")
            }

            HStack(spacing: 6) {
                planStatPill(icon: "clock", text: "\(totalMinutes) min")
                planStatPill(icon: "list.number", text: "\(template.intervals.count) steps")
            }

            Button {
                navigationPath.append(AppRoute.customWorkoutRide(templateID: template.id))
                dismissParentChatIfNeeded()
            } label: {
                HStack(spacing: 8) {
                    Text("Start workout")
                        .mangoxFont(.label)
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(AppColor.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .mangoxSurface(
                    .flatCustom(fill: AppColor.mango, border: AppColor.mango.opacity(0.45)),
                    shape: .rounded(MangoxRadius.sharp.rawValue)
                )
            }
            .buttonStyle(MangoxPressStyle())
        }
        .padding(16)
        .mangoxSurface(.flat, shape: .rounded(MangoxRadius.sharp.rawValue))
    }

    private func planStatPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppColor.fg3)
            Text(text)
                .mangoxFont(.caption)
                .foregroundStyle(.white.opacity(AppOpacity.textSecondary))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .mangoxSurface(.flatSubtle, shape: .rounded(MangoxRadius.sharp.rawValue))
    }

    private func deleteTemplate(_ template: CustomWorkoutTemplate) {
        modelContext.delete(template)
        try? modelContext.save()
    }
}
