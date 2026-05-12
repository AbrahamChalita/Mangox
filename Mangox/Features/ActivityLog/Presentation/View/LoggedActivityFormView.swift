// Features/ActivityLog/Presentation/View/LoggedActivityFormView.swift
import SwiftUI

struct LoggedActivityFormView: View {
    @Bindable var viewModel: LoggedActivityFormViewModel
    let navigationPath: Binding<NavigationPath>

    var body: some View {
        ZStack {
            AppColor.bg.ignoresSafeArea()

            Form {
                basicsSection
                intensitySection
                metricsSection
                notesSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(viewModel.isEditing ? "Edit Activity" : "New Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { navigationPath.wrappedValue.removeLast() }
                    .foregroundStyle(AppColor.fg2)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    Task {
                        await viewModel.save()
                        if viewModel.didSave { navigationPath.wrappedValue.removeLast() }
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(viewModel.isValid ? AppColor.mango : AppColor.fg3)
                .disabled(!viewModel.isValid || viewModel.isSaving)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.dismissError() }
        } message: {
            if let msg = viewModel.errorMessage { Text(msg) }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        Section("Basics") {
            Picker("Type", selection: $viewModel.draft.type) {
                ForEach(LoggedActivityType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.sfSymbol).tag(type)
                }
            }

            if viewModel.draft.type == .other {
                TextField("Custom label", text: Binding(
                    get: { viewModel.draft.customLabel ?? "" },
                    set: { viewModel.draft.customLabel = $0.isEmpty ? nil : $0 }
                ))
            }

            DatePicker("Date & Time", selection: $viewModel.draft.startDate, displayedComponents: [.date, .hourAndMinute])

            Stepper(value: $viewModel.durationHours, in: 0...23) {
                HStack {
                    Text("Hours")
                    Spacer()
                    Text("\(viewModel.durationHours)h")
                        .foregroundStyle(AppColor.fg2)
                }
            }

            Stepper(value: $viewModel.durationMinutes, in: 0...55, step: 5) {
                HStack {
                    Text("Minutes")
                    Spacer()
                    Text("\(viewModel.durationMinutes)m")
                        .foregroundStyle(AppColor.fg2)
                }
            }
        }
    }

    private var intensitySection: some View {
        Section("Intensity") {
            Picker("Band", selection: Binding(
                get: { viewModel.draft.intensity },
                set: { viewModel.draft.intensity = $0 }
            )) {
                Text("None").tag(Optional<LoggedActivityIntensity>.none)
                ForEach(LoggedActivityIntensity.allCases, id: \.self) {
                    Text($0.displayName).tag(Optional($0))
                }
            }
            .pickerStyle(.segmented)

            if let _ = viewModel.draft.intensity {
                HStack {
                    Text("RPE")
                    Spacer()
                    Text(viewModel.draft.rpe.map { "\($0)" } ?? "–")
                        .foregroundStyle(AppColor.fg2)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { Double(viewModel.draft.rpe ?? 5) },
                        set: { viewModel.draft.rpe = Int($0) }
                    ),
                    in: 1...10, step: 1
                )
                .tint(AppColor.mango)
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        let type = viewModel.draft.type
        if type.isStrength {
            strengthMetricsSection
        } else if type.isCardioDistance {
            cardioMetricsSection
        }
    }

    private var strengthMetricsSection: some View {
        Section("Metrics") {
            metricStepper("Sets", value: Binding(
                get: { viewModel.draft.metrics.sets ?? 0 },
                set: { viewModel.draft.metrics.sets = $0 > 0 ? $0 : nil }
            ), range: 0...30)

            metricStepper("Reps", value: Binding(
                get: { viewModel.draft.metrics.reps ?? 0 },
                set: { viewModel.draft.metrics.reps = $0 > 0 ? $0 : nil }
            ), range: 0...100)

            HStack {
                Text("Weight (kg)")
                Spacer()
                TextField("0", value: Binding(
                    get: { viewModel.draft.metrics.weightKg },
                    set: { viewModel.draft.metrics.weightKg = $0 }
                ), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppColor.fg2)
                .frame(width: 80)
            }
        }
    }

    private var cardioMetricsSection: some View {
        Section("Metrics") {
            HStack {
                Text("Distance (km)")
                Spacer()
                TextField("0.0", value: Binding(
                    get: { viewModel.draft.metrics.distanceMeters.map { $0 / 1000 } },
                    set: { viewModel.draft.metrics.distanceMeters = $0.map { $0 * 1000 } }
                ), format: .number.precision(.fractionLength(2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(AppColor.fg2)
                .frame(width: 80)
            }

            metricStepper("Avg HR (bpm)", value: Binding(
                get: { viewModel.draft.metrics.avgHeartRate ?? 0 },
                set: { viewModel.draft.metrics.avgHeartRate = $0 > 0 ? $0 : nil }
            ), range: 0...220, step: 1)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes…", text: $viewModel.draft.notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private func metricStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue > 0 ? "\(value.wrappedValue)" : "–")
                    .foregroundStyle(AppColor.fg2)
            }
        }
    }
}
