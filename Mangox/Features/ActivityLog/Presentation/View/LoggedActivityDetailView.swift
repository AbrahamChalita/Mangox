// Features/ActivityLog/Presentation/View/LoggedActivityDetailView.swift
import SwiftUI

struct LoggedActivityDetailView: View {
    let id: UUID
    let repository: LoggedActivityRepository
    @Binding var navigationPath: NavigationPath

    @State private var activity: LoggedActivity?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            if let activity {
                content(activity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { activity = try? repository.fetch(id: id) }
        .confirmationDialog("Delete Activity", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let activity {
                    try? repository.delete(id: activity.id)
                    navigationPath.removeLast()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func content(_ activity: LoggedActivity) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                header(activity)
                statsGrid(activity)
                if !activity.notes.isEmpty { notesCard(activity) }
                if activity.source != .manual { sourceCard(activity) }
                if activity.source == .manual { actionButtons(activity) }
            }
            .padding(16)
            .padding(.bottom, 40)
        }
    }

    private func header(_ activity: LoggedActivity) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LoggedActivityIcon.color(for: activity.type).opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: LoggedActivityIcon.symbol(for: activity.type))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(LoggedActivityIcon.color(for: activity.type))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(activity.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(AppColor.fg0)

                HStack(spacing: 8) {
                    Text(activity.startDate.formatted(date: .long, time: .shortened))
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.fg3)

                    let badge = LoggedActivityIcon.sourceBadge(for: activity.source)
                    Text(badge.text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badge.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            Spacer()
        }
        .padding(16)
        .background(AppColor.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppColor.hair))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            A11yL10n.activityHeaderFormat(
                activity.displayName,
                activity.startDate.formatted(date: .long, time: .shortened),
                LoggedActivityIcon.sourceBadge(for: activity.source).text
            )
        )
    }

    @ViewBuilder
    private func statsGrid(_ activity: LoggedActivity) -> some View {
        let stats = buildStats(activity)
        if !stats.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(stats, id: \.label) { stat in
                    VStack(spacing: 4) {
                        Text(stat.value)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColor.fg0)
                        Text(stat.label)
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.fg3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.bg1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppColor.hair))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(A11yL10n.statFormat(stat.label, stat.value))
                }
            }
        }
    }

    private func notesCard(_ activity: LoggedActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColor.fg3)
            Text(activity.notes)
                .font(.system(size: 15))
                .foregroundStyle(AppColor.fg1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColor.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppColor.hair))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yL10n.notesFormat(activity.notes))
    }

    private func sourceCard(_ activity: LoggedActivity) -> some View {
        let badge = LoggedActivityIcon.sourceBadge(for: activity.source)
        return HStack {
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(badge.color)
            Text("View on \(badge.text)")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppColor.fg1)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(AppColor.fg3)
        }
        .padding(16)
        .background(AppColor.bg1)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppColor.hair))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yL10n.viewOnSourceFormat(badge.text))
        .accessibilityAddTraits(.isButton)
    }

    private func actionButtons(_ activity: LoggedActivity) -> some View {
        VStack(spacing: 10) {
            Button {
                navigationPath.append(AppRoute.loggedActivityForm(editing: activity.id))
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.bg2)
                    .foregroundStyle(AppColor.fg1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(AppColor.hair2))
            }
            .accessibilityLabel(A11yL10n.editActivity)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete Activity", systemImage: "trash")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColor.red.opacity(0.10))
                    .foregroundStyle(AppColor.red)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(A11yL10n.deleteActivity)
            .accessibilityHint(A11yL10n.deleteActivityHint)
        }
    }

    private struct Stat { let label: String; let value: String }

    private func buildStats(_ a: LoggedActivity) -> [Stat] {
        var stats: [Stat] = []
        stats.append(.init(label: "Duration", value: a.durationFormatted))
        if let d = a.metrics.distanceMeters, d > 0 {
            stats.append(.init(label: "Distance", value: d >= 1000 ? String(format: "%.1f km", d/1000) : String(format: "%.0f m", d)))
        }
        if let hr = a.metrics.avgHeartRate, hr > 0 { stats.append(.init(label: "Avg HR", value: "\(hr) bpm")) }
        if let mhr = a.metrics.maxHeartRate, mhr > 0 { stats.append(.init(label: "Max HR", value: "\(mhr) bpm")) }
        if let cal = a.metrics.calories, cal > 0 { stats.append(.init(label: "Calories", value: "\(cal)")) }
        if let s = a.metrics.sets, s > 0, let r = a.metrics.reps, r > 0 { stats.append(.init(label: "Sets × Reps", value: "\(s) × \(r)")) }
        if let w = a.metrics.weightKg, w >= 0 { stats.append(.init(label: "Weight", value: String(format: "%.1f kg", w))) }
        if let strain = a.metrics.strain, strain >= 0 { stats.append(.init(label: "Strain", value: String(format: "%.1f", strain))) }
        if let kj = a.metrics.kilojoules, kj > 0 { stats.append(.init(label: "kJ", value: String(format: "%.0f", kj))) }
        if let rpe = a.rpe { stats.append(.init(label: "RPE", value: "\(rpe)/10")) }
        return stats
    }
}
