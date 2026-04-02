import SwiftUI
import SwiftData

struct PlanGenerationView: View {
    @Environment(AIService.self) private var aiService
    @Environment(PurchasesManager.self) private var purchases
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step: Int = 1
    @State private var eventName: String = ""
    @State private var eventDate: Date = Calendar.current.date(byAdding: .day, value: 84, to: .now) ?? .now
    @State private var ftp: Int = PowerZone.ftp
    @State private var weeklyHours: Int = 6
    @State private var experience: ExperienceLevel = .intermediate

    @State private var generatedPlan: TrainingPlan? = nil
    @State private var generateError: String? = nil

    enum ExperienceLevel: String, CaseIterable {
        case beginner, intermediate, advanced
        var label: String { rawValue.capitalized }
    }

    private let minEventDate: Date = Calendar.current.date(byAdding: .day, value: 42, to: .now) ?? .now
    private let weeklyHoursOptions = [4, 6, 8, 10]

    var body: some View {
        NavigationStack {
            ZStack {
                AppColor.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        stepIndicator

                        Group {
                            switch step {
                            case 1: stepOneView
                            case 2: stepTwoView
                            case 3: stepThreeView
                            default: EmptyView()
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                    }
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Build Your Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? AppColor.mango : Color.white.opacity(0.15))
                    .frame(maxWidth: i == step ? .infinity : 28, minHeight: 3, maxHeight: 3)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    // MARK: - Step 1: Event Details

    private var stepOneView: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("About your event")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("Tell us what you're training for and we'll build a plan around it.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 16) {
                formField(label: "EVENT NAME") {
                    TextField("e.g. Gran Fondo Alps 2026", text: $eventName)
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .tint(AppColor.mango)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                formField(label: "EVENT DATE") {
                    DatePicker("", selection: $eventDate, in: minEventDate..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .tint(AppColor.mango)
                        .colorScheme(.dark)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 20)

            ctaButton(
                label: "Continue",
                icon: "arrow.right",
                enabled: !eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    step = 2
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 2: Fitness Profile

    private var stepTwoView: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your fitness profile")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                Text("We'll use these to personalize zones, training load, and weekly structure.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.48))
            }
            .padding(.horizontal, 24)

            VStack(spacing: 16) {
                // FTP
                formField(label: "FUNCTIONAL THRESHOLD POWER") {
                    HStack {
                        Text("\(ftp) W")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColor.mango)
                        Spacer()
                        Stepper("", value: $ftp, in: 80...500, step: 5)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // Weekly hours
                formField(label: "WEEKLY TRAINING HOURS") {
                    HStack(spacing: 8) {
                        ForEach(weeklyHoursOptions, id: \.self) { h in
                            Button {
                                withAnimation(.spring(response: 0.3)) { weeklyHours = h }
                            } label: {
                                Text(h == 10 ? "10+" : "\(h)h")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(weeklyHours == h ? .black : .white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(weeklyHours == h ? AppColor.mango : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(MangoxPressStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }

                // Experience
                formField(label: "EXPERIENCE LEVEL") {
                    HStack(spacing: 8) {
                        ForEach(ExperienceLevel.allCases, id: \.self) { level in
                            Button {
                                withAnimation(.spring(response: 0.3)) { experience = level }
                            } label: {
                                Text(level.label)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(experience == level ? .black : .white.opacity(0.7))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(experience == level ? AppColor.mango : Color.white.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(MangoxPressStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { step = 1 }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(MangoxPressStyle())

                ctaButton(label: "Build My Plan", icon: "sparkles", enabled: true) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        step = 3
                    }
                    Task { await runGeneration() }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Step 3: Generating / Result

    @ViewBuilder
    private var stepThreeView: some View {
        if let plan = generatedPlan {
            planResultView(plan)
        } else if let error = generateError {
            errorView(error)
        } else {
            generatingView
        }
    }

    private var generatingView: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppColor.mango.opacity(0.1))
                        .frame(width: 88, height: 88)
                    GeneratingPulseIcon()
                }

                VStack(spacing: 8) {
                    Text("Building your plan")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Analyzing your event and personalizing\nzones, phases, and workouts...")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                }
            }

            generatingStepsList

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var generatingStepsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            generatingStep("Analyzing event profile", delay: 0.3)
            generatingStep("Designing training phases", delay: 1.0)
            generatingStep("Calibrating power zones", delay: 1.8)
            generatingStep("Building interval workouts", delay: 2.6)
        }
        .padding(18)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func generatingStep(_ label: String, delay: Double) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(AppColor.mango)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func planResultView(_ plan: TrainingPlan) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // Success header
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AppColor.success)
                    Text("Your plan is ready!")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Personalized for \(plan.eventName)")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)

            // Plan summary card
            VStack(alignment: .leading, spacing: 16) {
                Text(plan.name)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))

                HStack(spacing: 10) {
                    planSummaryChip(icon: "calendar", value: "\(plan.totalWeeks) weeks")
                    planSummaryChip(icon: "figure.outdoor.cycle", value: "\(plan.allDays.filter { $0.dayType == .workout }.count) workouts")
                    if !plan.distance.isEmpty {
                        planSummaryChip(icon: "arrow.right", value: plan.distance)
                    }
                }

                Divider().background(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 8) {
                    Text("PHASES")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1.0)

                    let phases = Dictionary(grouping: plan.weeks, by: \.phase)
                        .sorted { $0.value.first!.weekNumber < $1.value.first!.weekNumber }
                    ForEach(phases, id: \.key) { phase, weeks in
                        HStack {
                            Circle()
                                .fill(phaseColor(phase))
                                .frame(width: 6, height: 6)
                            Text(phase)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                            Spacer()
                            Text("\(weeks.count) week\(weeks.count == 1 ? "" : "s")")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }

                if let remaining = aiService.lastCreditsRemaining {
                    Text("\(remaining) plan generation\(remaining == 1 ? "" : "s") remaining this month")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(18)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            ctaButton(label: "Save Plan & Start Training", icon: "checkmark", enabled: true) {
                savePlan(plan)
            }
            .padding(.horizontal, 20)

            Button {
                withAnimation { generateError = nil; generatedPlan = nil }
                Task { await runGeneration() }
            } label: {
                Text("Regenerate")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(AppColor.yellow)

                VStack(spacing: 6) {
                    Text("Couldn't generate plan")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.48))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ctaButton(label: "Try Again", icon: "arrow.clockwise", enabled: true) {
                    withAnimation { generateError = nil }
                    Task { await runGeneration() }
                }
                Button {
                    withAnimation(.spring(response: 0.45)) { step = 2 }
                    generateError = nil
                } label: {
                    Text("Edit inputs")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Helpers

    private func formField(label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white.opacity(0.35))
                .tracking(1.0)
                .padding(.horizontal, 4)

            content()
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                )
        }
    }

    private func ctaButton(label: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(enabled ? AppColor.mango : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(MangoxPressStyle())
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private func planSummaryChip(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func phaseColor(_ phase: String) -> Color {
        switch phase.lowercased() {
        case let p where p.contains("foundation"): return AppColor.blue
        case let p where p.contains("build"): return AppColor.success
        case let p where p.contains("taper"): return AppColor.yellow
        case let p where p.contains("race"): return AppColor.orange
        default: return .white.opacity(0.4)
        }
    }

    // MARK: - Actions

    private func runGeneration() async {
        generateError = nil
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let inputs = PlanInputs(
            event_name: eventName.trimmingCharacters(in: .whitespacesAndNewlines),
            event_date: dateFormatter.string(from: eventDate),
            ftp: ftp,
            weekly_hours: weeklyHours,
            experience: experience.rawValue
        )
        do {
            let plan = try await aiService.generatePlan(inputs: inputs)
            withAnimation(.spring(response: 0.5)) {
                generatedPlan = plan
            }
        } catch {
            withAnimation(.spring(response: 0.4)) {
                generateError = "Generation failed. Please check your connection and try again."
            }
        }
    }

    private func savePlan(_ plan: TrainingPlan) {
        guard let planData = try? JSONEncoder().encode(plan) else { return }

        let aiPlan = AIGeneratedPlan(
            id: plan.id,
            planJSON: planData,
            generatedAt: .now,
            userPrompt: "\(eventName) — \(experience.label), \(weeklyHours)h/week"
        )
        modelContext.insert(aiPlan)

        let progress = TrainingPlanProgress(planID: plan.id, startDate: .now, ftp: ftp)
        progress.aiPlanTitle = plan.name
        progress.currentFTP = ftp
        modelContext.insert(progress)

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Generating Pulse Icon

struct GeneratingPulseIcon: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.6

    var body: some View {
        ZStack {
            Circle()
                .fill(AppColor.mango.opacity(0.15))
                .frame(width: 60, height: 60)
                .scaleEffect(scale)
                .opacity(opacity)

            Image(systemName: "sparkles")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppColor.mango)
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
            ) {
                scale = 1.35
                opacity = 0.0
            }
        }
    }
}
