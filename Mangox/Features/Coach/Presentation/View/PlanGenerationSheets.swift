import SwiftUI
import SwiftData

// MARK: - Inline confirm (no extra sheet / cover — avoids SwiftUI single-sheet limits)

/// Shown above the composer in chat, or as a bottom overlay on the hub when chat is closed.
struct CoachPlanConfirmBanner: View {
    let draft: PlanGenerationDraft
    @Binding var navigationPath: NavigationPath

    @Environment(CoachViewModel.self) private var coachViewModel

    @State private var localError: String?
    /// Collapsed by default so the confirm card fits above the keyboard + composer; user expands to edit.
    @State private var editDetailsExpanded = false

    @State private var eventName = ""
    @State private var eventDateYMD = ""
    @State private var routeOption = ""
    @State private var distanceKmText = ""
    @State private var elevationMText = ""
    @State private var locationText = ""
    @State private var notesText = ""
    @State private var weeklyHoursText = ""
    @State private var experienceText = ""
    @State private var ftpText = ""

    /// Caps the expandable details scroll; outer chat `inputBar` also scrolls when this sheet is up.
    private static let planFormScrollMaxHeight: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if editDetailsExpanded {
                    ScrollView {
                        planConfirmMainContent
                    }
                    .frame(maxHeight: Self.planFormScrollMaxHeight)
                    .scrollDismissesKeyboard(.interactively)
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                } else {
                    planConfirmMainContent
                }
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button {
                        localError = nil
                        coachViewModel.clearPlanConfirmationDraft()
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white.opacity(0.85))
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(MangoxPressStyle())
                    .disabled(coachViewModel.generatingPlan)

                    Button {
                        localError = nil
                        let built = buildPlanInputsFromForm()
                        if let msg = built.error {
                            localError = msg
                            editDetailsExpanded = true
                        } else if let inputs = built.inputs {
                            let confirmed = PlanGenerationDraft(
                                id: draft.id,
                                inputs: inputs,
                                summaryLine: coachViewModel.planGenerationSummaryLine(for: inputs)
                            )
                            Task {
                                do {
                                    try await coachViewModel.runConfirmedPlanGeneration(
                                        draft: confirmed,
                                        isPro: coachViewModel.isPro
                                    )
                                } catch {
                                    localError = coachViewModel.userFacingPlanGenerationError(error)
                                    editDetailsExpanded = true
                                }
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                if coachViewModel.generatingPlan {
                                    ProgressView()
                                        .tint(.black.opacity(0.8))
                                }
                                Text(coachViewModel.generatingPlan
                                     ? (coachViewModel.planProgress?.message ?? "Generating…")
                                     : "Generate")
                                    .font(.system(size: 15, weight: .bold))
                                    .lineLimit(1)
                            }
                            if coachViewModel.generatingPlan, let progress = coachViewModel.planProgress {
                                ProgressView(value: progress.fraction)
                                    .tint(.black.opacity(0.6))
                                    .scaleEffect(y: 1.5)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .foregroundStyle(.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .animation(.easeInOut(duration: 0.2), value: coachViewModel.planProgress)
                    }
                    .buttonStyle(MangoxPressStyle())
                    .disabled(coachViewModel.generatingPlan)
                }
                .padding(.top, 12)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.bg)
                .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            AppColor.mango.opacity(0.45),
                            Color.white.opacity(0.12),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm plan generation for \(eventName)")
        .onAppear { syncFormFromDraft() }
        .onChange(of: draft.id) { _, _ in syncFormFromDraft() }
    }

    @ViewBuilder
    private var planConfirmMainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generate this plan?")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text("Expand details to edit, then generate.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                Spacer(minLength: 0)
            }

            DisclosureGroup(isExpanded: $editDetailsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    coachPlanField(title: "Event name", prompt: "e.g. L'Étape Mexico City", text: $eventName)
                    coachPlanField(title: "Event date", prompt: "yyyy-MM-dd", text: $eventDateYMD)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    coachPlanField(title: "Route option", prompt: "long, medium, short…", text: $routeOption)
                    HStack(alignment: .top, spacing: 10) {
                        coachPlanField(title: "Distance (km)", prompt: "optional", text: $distanceKmText)
                        coachPlanField(title: "Climbing (m)", prompt: "optional", text: $elevationMText)
                    }
                    coachPlanField(title: "Location", prompt: "City, country", text: $locationText)
                    coachPlanField(title: "Event notes", prompt: "Optional one line", text: $notesText, axis: .vertical)
                    HStack(alignment: .top, spacing: 10) {
                        coachPlanField(title: "Hours / week", prompt: "optional", text: $weeklyHoursText)
                        coachPlanField(title: "Experience", prompt: "optional", text: $experienceText)
                    }
                    coachPlanField(title: "FTP (watts)", prompt: "your FTP", text: $ftpText, keyboard: .numberPad)
                }
                .padding(.top, 8)
            } label: {
                Text("Review & edit details")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .tint(AppColor.mango)

            Text("Uses one server plan generation (server daily limits still apply). Your FTP and training context are sent encrypted when configured.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.38))
                .fixedSize(horizontal: false, vertical: true)

            if let localError {
                Text(localError)
                    .font(.footnote)
                    .foregroundStyle(AppColor.red.opacity(0.95))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func coachPlanField(
        title: String,
        prompt: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField(
                prompt,
                text: text,
                prompt: Text(prompt).foregroundColor(.white.opacity(0.28)),
                axis: axis
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .tint(AppColor.mango)
            .keyboardType(keyboard)
            .lineLimit(axis == .vertical ? 2...4 : 1...1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncFormFromDraft() {
        let i = draft.inputs
        eventName = i.event_name
        eventDateYMD = i.event_date
        routeOption = i.route_option ?? ""
        distanceKmText = Self.formatKmInput(i.target_distance_km)
        elevationMText = Self.formatMInput(i.target_elevation_m)
        locationText = i.event_location ?? ""
        notesText = i.event_notes ?? ""
        weeklyHoursText = i.weekly_hours.map(String.init) ?? ""
        experienceText = i.experience ?? ""
        ftpText = String(i.ftp)
    }

    private static func formatKmInput(_ v: Double?) -> String {
        guard let v, v > 0 else { return "" }
        if v >= 100 { return String(format: "%.0f", v) }
        return String(format: "%.1f", v)
    }

    private static func formatMInput(_ v: Double?) -> String {
        guard let v, v > 0 else { return "" }
        return String(Int(v.rounded()))
    }

    private func buildPlanInputsFromForm() -> (inputs: PlanInputs?, error: String?) {
        let nameTrim = eventName.trimmingCharacters(in: .whitespacesAndNewlines)
        if nameTrim.isEmpty {
            return (nil, "Enter an event name.")
        }
        let dateTrim = eventDateYMD.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedDate = coachViewModel.normalizePlanEventDate(dateTrim) else {
            return (nil, "Event date must be a valid yyyy-MM-dd (or a recognizable date).")
        }
        let ftpTrim = ftpText.trimmingCharacters(in: .whitespacesAndNewlines)
        let ftpVal: Int = {
            if ftpTrim.isEmpty { return draft.inputs.ftp }
            guard let v = Int(ftpTrim), v >= 20, v <= 800 else {
                return -1
            }
            return v
        }()
        if ftpVal < 0 {
            return (nil, "FTP should be between 20 and 800 W.")
        }
        let whTrim = weeklyHoursText.trimmingCharacters(in: .whitespacesAndNewlines)
        let weekly: Int?
        if whTrim.isEmpty {
            weekly = nil
        } else if let v = Int(whTrim), v >= 1, v <= 40 {
            weekly = v
        } else {
            return (nil, "Weekly hours should be 1–40 or leave blank.")
        }
        let dist = parseOptionalDouble(distanceKmText)
        let elev = parseOptionalDouble(elevationMText)
        let ro = routeOption.trimmingCharacters(in: .whitespacesAndNewlines)
        let loc = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        let exp = experienceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            PlanInputs(
                event_name: nameTrim,
                event_date: normalizedDate,
                ftp: ftpVal,
                weekly_hours: weekly,
                experience: exp.isEmpty ? nil : exp,
                route_option: ro.isEmpty ? nil : ro,
                target_distance_km: dist,
                target_elevation_m: elev,
                event_location: loc.isEmpty ? nil : loc,
                event_notes: notes.isEmpty ? nil : notes
            ),
            nil
        )
    }

    private func parseOptionalDouble(_ raw: String) -> Double? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let norm = t.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(norm), v > 0 else { return nil }
        return v
    }
}

// MARK: - Inline success

struct CoachPlanSuccessBanner: View {
    let celebration: PlanSaveCelebration
    @Binding var navigationPath: NavigationPath
    /// e.g. dismiss full-screen chat so the plan route is visible on the tab stack.
    var dismissChat: (() -> Void)?

    @Environment(CoachViewModel.self) private var coachViewModel

    @State private var regeneratingWeek: Int?
    @State private var regenError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan saved")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(celebration.planName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            if !celebration.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(celebration.warnings.enumerated()), id: \.offset) { _, w in
                        Text("• \(w)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }

            if !celebration.fallbackWeekNumbers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Retry AI for fallback weeks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    ForEach(celebration.fallbackWeekNumbers, id: \.self) { wn in
                        Button {
                            Task { @MainActor in
                                regeneratingWeek = wn
                                regenError = nil
                                defer { regeneratingWeek = nil }
                                do {
                                    try await coachViewModel.regenerateFallbackPlanWeek(
                                        wn,
                                        celebration: celebration,
                                        isPro: coachViewModel.isPro
                                    )
                                } catch {
                                    regenError = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                if regeneratingWeek == wn {
                                    ProgressView()
                                        .tint(AppColor.mango)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Regenerate week \(wn)")
                                    .font(.caption.weight(.semibold))
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(regeneratingWeek != nil)
                    }
                    if let regenError {
                        Text(regenError)
                            .font(.caption2)
                            .foregroundStyle(AppColor.mango.opacity(0.9))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    coachViewModel.clearPlanSaveCelebration()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white.opacity(0.85))
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

                Button {
                    navigationPath.append(AppRoute.aiPlan(planID: celebration.planID))
                    coachViewModel.clearPlanSaveCelebration()
                    dismissChat?()
                } label: {
                    Text("Open plan")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .foregroundStyle(.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.bg)
                .shadow(color: Color.black.opacity(0.3), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.success.opacity(0.4), lineWidth: 1)
        )
    }
}

struct CoachWorkoutConfirmBanner: View {
    let draft: WorkoutGenerationDraft

    @Environment(CoachViewModel.self) private var coachViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.heart.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppColor.mango)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Save this workout?")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(draft.workout.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
            }

            Text(draft.workout.purpose)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))

            if let rationale = draft.workout.rationale, !rationale.isEmpty {
                Text(rationale)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.48))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(draft.workout.day.durationMinutes) min · \(draft.inputs.goal)")
                Text("\(draft.workout.day.intervals.count) intervals")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))

            HStack(spacing: 10) {
                Button {
                    coachViewModel.clearWorkoutConfirmationDraft()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white.opacity(0.85))
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

                Button {
                    do {
                        try coachViewModel.saveConfirmedWorkoutDraft(draft)
                    } catch {
                    }
                } label: {
                    Text("Save workout")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .foregroundStyle(.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.bg)
                .shadow(color: Color.black.opacity(0.3), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.mango.opacity(0.35), lineWidth: 1)
        )
    }
}

struct CoachWorkoutSuccessBanner: View {
    let celebration: WorkoutSaveCelebration
    @Binding var navigationPath: NavigationPath
    var dismissChat: (() -> Void)?

    @Environment(CoachViewModel.self) private var coachViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColor.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Workout saved")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(celebration.workoutTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
            }

            Text(celebration.purpose)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.52))

            HStack(spacing: 10) {
                Button {
                    coachViewModel.clearWorkoutSaveCelebration()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white.opacity(0.85))
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

                Button {
                    navigationPath.append(AppRoute.customWorkoutRide(templateID: celebration.templateID))
                    coachViewModel.clearWorkoutSaveCelebration()
                    dismissChat?()
                } label: {
                    Text("Start workout")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(AppColor.mango)
                        .foregroundStyle(.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppColor.bg)
                .shadow(color: Color.black.opacity(0.3), radius: 12, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppColor.success.opacity(0.4), lineWidth: 1)
        )
    }
}
