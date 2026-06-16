import Foundation
import FoundationModels
import os

// MARK: - Guided generation: plan skeleton

@Generable
struct OnDevicePlanSkeletonWeek: Equatable {
    var weekNumber: Int
    var phase: String
    var title: String
    var tssTargetLow: Int
    var tssTargetHigh: Int
    var focus: String
}

@Generable
struct OnDevicePlanSkeleton: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    var planName: String
    var description: String

    @Guide(description: "One entry per training week, in order.")
    var weeks: [OnDevicePlanSkeletonWeek]
}

// MARK: - Guided generation: single week

@Generable
struct OnDeviceGeneratedPlanDay: Equatable {
    var dayOfWeek: Int
    var dayType: String
    var title: String
    var durationMinutes: Int
    var zone: String
    var notes: String
    var isKeyWorkout: Bool
    var requiresFTPTest: Bool
    var intervals: [OnDeviceWorkoutInterval]
}

@Generable
struct OnDeviceGeneratedPlanWeek: Equatable {
    @Guide(description: "Internal plan — not shown in UI.")
    var reasoning: String

    @Guide(description: "Exactly seven days (Mon=1 … Sun=7).", .count(7))
    var days: [OnDeviceGeneratedPlanDay]
}

// MARK: - Generator

enum OnDevicePlanGenerator {

    private static let logger = Logger(subsystem: "com.abchalita.Mangox", category: "OnDevicePlan")

    /// True when PCC can run plan generation (preferred) or on-device FM as fallback for short plans.
    static var canGenerateOnDevice: Bool {
        if MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable { return true }
        return OnDeviceCoachEngine.isOnDeviceWritingModelAvailable
    }

    static func plannedWeekCount(inputs: PlanInputs, today: Date = .now) -> Int {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current
        df.dateFormat = "yyyy-MM-dd"
        guard let event = df.date(from: inputs.event_date) else { return 12 }
        let days = Calendar.current.dateComponents([.day], from: today, to: event).day ?? 84
        return max(4, min(20, (days + 6) / 7))
    }

    @MainActor
    static func generate(
        inputs: PlanInputs,
        factSheet: String,
        ftp: Int,
        tools: [any Tool] = [],
        onProgress: @escaping @Sendable (PlanGenerationProgress) -> Void
    ) async throws -> TrainingPlan {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()

        let weekCount = plannedWeekCount(inputs: inputs)
        let usePCC = MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable
            && MangoxFoundationModelsSupport.privateCloudComputeSupportsCurrentLocale()

        if usePCC {
            try MangoxPCCSupport.throwIfPlanGenerationQuotaBlocked(estimatedPCCCalls: weekCount + 1)
        }

        onProgress(
            PlanGenerationProgress(
                phase: "skeleton",
                message: usePCC ? "Designing plan structure (Private Cloud)…" : "Designing plan structure…",
                current: nil,
                total: nil
            )
        )

        do {
            let session = makePlanSession(usePCC: usePCC, tools: tools)
            return try await runGeneration(
                session: session,
                inputs: inputs,
                factSheet: factSheet,
                ftp: ftp,
                weekCount: weekCount,
                onProgress: onProgress
            )
        } catch {
            guard usePCC, MangoxPCCSupport.shouldFallbackToOnDeviceAfterPCCFailure(error) else { throw error }
            logger.info("PCC plan generation failed — retrying on-device: \(error.localizedDescription, privacy: .public)")
            onProgress(
                PlanGenerationProgress(
                    phase: "skeleton",
                    message: "Private Cloud unavailable — continuing on-device…",
                    current: nil,
                    total: nil
                )
            )
            await Task.yield()
            let session = makeOnDevicePlanSession(tools: tools)
            return try await runGeneration(
                session: session,
                inputs: inputs,
                factSheet: factSheet,
                ftp: ftp,
                weekCount: weekCount,
                onProgress: onProgress
            )
        }
    }

    @MainActor
    static func regenerateWeek(
        inputs: PlanInputs,
        plan: TrainingPlan,
        weekNumber: Int,
        factSheet: String,
        ftp: Int,
        tools: [any Tool] = []
    ) async throws -> [PlanDay] {
        try MangoxFoundationModelsSupport.throwIfLocaleUnsupported()
        guard let skelWeek = plan.weeks.first(where: { $0.weekNumber == weekNumber }) else {
            throw OnDevicePlanGeneratorError.weekNotFound
        }

        let usePCC = MangoxFoundationModelsSupport.isPrivateCloudComputeCoachAvailable
        if usePCC {
            try MangoxPCCSupport.throwIfPlanGenerationQuotaBlocked(estimatedPCCCalls: 1)
        }

        do {
            let session = makePlanSession(usePCC: usePCC, tools: tools)
            return try await runWeekRegeneration(
                session: session,
                inputs: inputs,
                plan: plan,
                weekNumber: weekNumber,
                skelWeek: skelWeek,
                ftp: ftp
            )
        } catch {
            guard usePCC, MangoxPCCSupport.shouldFallbackToOnDeviceAfterPCCFailure(error) else { throw error }
            logger.info("PCC week regeneration failed — retrying on-device: \(error.localizedDescription, privacy: .public)")
            await Task.yield()
            let session = makeOnDevicePlanSession(tools: tools)
            return try await runWeekRegeneration(
                session: session,
                inputs: inputs,
                plan: plan,
                weekNumber: weekNumber,
                skelWeek: skelWeek,
                ftp: ftp
            )
        }
    }

    // MARK: - Session factories

    @MainActor
    private static func makePlanSession(usePCC: Bool, tools: [any Tool]) -> LanguageModelSession {
        if usePCC {
            return CoachDynamicProfiles.makeSession(mode: .planDeep, tools: tools)
        }
        return makeOnDevicePlanSession(tools: tools)
    }

    @MainActor
    private static func makeOnDevicePlanSession(tools: [any Tool]) -> LanguageModelSession {
        LanguageModelSession(
            model: MangoxFoundationModelsSupport.coachSystemLanguageModel(),
            tools: tools,
            instructions: Instructions(planInstructions(usePCC: false))
        )
    }

    // MARK: - Generation core

    @MainActor
    private static func runGeneration(
        session: LanguageModelSession,
        inputs: PlanInputs,
        factSheet: String,
        ftp: Int,
        weekCount: Int,
        onProgress: @escaping @Sendable (PlanGenerationProgress) -> Void
    ) async throws -> TrainingPlan {
        let skeletonPrompt = skeletonPromptText(
            inputs: inputs,
            factSheet: factSheet,
            ftp: ftp,
            weekCount: weekCount
        )

        let skeletonResponse = try await MangoxFoundationModelsSupport.respond(
            session: session,
            to: skeletonPrompt,
            generating: OnDevicePlanSkeleton.self,
            options: MangoxFoundationModelsSupport.greedyGenerationOptions,
            label: "plan_skeleton"
        )
        let skeleton = skeletonResponse.content
        guard !skeleton.weeks.isEmpty else {
            throw OnDevicePlanGeneratorError.emptySkeleton
        }

        var builtWeeks: [PlanWeek] = []
        let skeletonWeeks = skeleton.weeks.prefix(weekCount)

        for (index, skelWeek) in skeletonWeeks.enumerated() {
            let weekNum = skelWeek.weekNumber > 0 ? skelWeek.weekNumber : index + 1
            onProgress(
                PlanGenerationProgress(
                    phase: "weeks",
                    message: "Building week \(weekNum) of \(skeletonWeeks.count)…",
                    current: index + 1,
                    total: skeletonWeeks.count
                )
            )

            let weekPrompt = weekPromptText(
                inputs: inputs,
                skeleton: skeleton,
                week: skelWeek,
                weekNumber: weekNum,
                ftp: ftp,
                priorWeeksSummary: builtWeeks
            )

            let weekResponse = try await MangoxFoundationModelsSupport.respond(
                session: session,
                to: weekPrompt,
                generating: OnDeviceGeneratedPlanWeek.self,
                options: MangoxFoundationModelsSupport.greedyGenerationOptions,
                label: "plan_week_\(weekNum)"
            )

            let planWeek = mapWeek(
                generated: weekResponse.content,
                skeletonWeek: skelWeek,
                weekNumber: weekNum
            )
            builtWeeks.append(planWeek)
        }

        onProgress(
            PlanGenerationProgress(
                phase: "assembling",
                message: "Finalizing plan…",
                current: nil,
                total: nil
            )
        )

        return assemblePlan(inputs: inputs, skeleton: skeleton, weeks: builtWeeks)
    }

    @MainActor
    private static func runWeekRegeneration(
        session: LanguageModelSession,
        inputs: PlanInputs,
        plan: TrainingPlan,
        weekNumber: Int,
        skelWeek: PlanWeek,
        ftp: Int
    ) async throws -> [PlanDay] {
        let skeleton = OnDevicePlanSkeleton(
            reasoning: "regenerate week",
            planName: plan.name,
            description: plan.description,
            weeks: [
                OnDevicePlanSkeletonWeek(
                    weekNumber: skelWeek.weekNumber,
                    phase: skelWeek.phase,
                    title: skelWeek.title,
                    tssTargetLow: skelWeek.tssTarget.lowerBound,
                    tssTargetHigh: skelWeek.tssTarget.upperBound,
                    focus: skelWeek.focus
                )
            ]
        )

        let weekPrompt = weekPromptText(
            inputs: inputs,
            skeleton: skeleton,
            week: skeleton.weeks[0],
            weekNumber: weekNumber,
            ftp: ftp,
            priorWeeksSummary: plan.weeks.filter { $0.weekNumber < weekNumber }
        )

        let regenerationPrompt =
            weekPrompt + "\n\nRegenerate this week with fresh workouts; keep phase and TSS target."
        let weekResponse = try await MangoxFoundationModelsSupport.respond(
            session: session,
            to: regenerationPrompt,
            generating: OnDeviceGeneratedPlanWeek.self,
            options: MangoxFoundationModelsSupport.greedyGenerationOptions,
            label: "plan_week_regeneration_\(weekNumber)"
        )

        return mapWeek(
            generated: weekResponse.content,
            skeletonWeek: skeleton.weeks[0],
            weekNumber: weekNumber
        ).days
    }

    // MARK: - Prompts

    private static func planInstructions(usePCC: Bool) -> String {
        """
        You generate structured indoor cycling training plans for Mangox.
        Version \(CoachOnDevicePromptVersion.pccPlan).
        Output realistic periodization with rest days, progressive load, and a taper before the event.
        Use zones Z1–Z5 and day types: workout, rest, race, ftpTest, optionalWorkout, commute.
        Never invent rider metrics not in the prompt.
        """
    }

    private static func skeletonPromptText(
        inputs: PlanInputs,
        factSheet: String,
        ftp: Int,
        weekCount: Int
    ) -> String {
        """
        Create a \(weekCount)-week training plan skeleton for this event.

        Event: \(inputs.event_name)
        Event date: \(inputs.event_date)
        FTP: \(ftp) W
        Weekly hours target: \(inputs.weekly_hours.map(String.init) ?? "flexible")
        Experience: \(inputs.experience ?? "intermediate")
        Route: \(inputs.route_option ?? "n/a")
        Distance km: \(inputs.target_distance_km.map { String($0) } ?? "n/a")
        Elevation m: \(inputs.target_elevation_m.map { String(Int($0.rounded())) } ?? "n/a")
        Location: \(inputs.event_location ?? "")
        Notes: \(inputs.event_notes ?? "")

        Rider context:
        \(factSheet)

        Return exactly \(weekCount) weeks in `weeks`, numbered 1…\(weekCount).
        Include Foundation, Build, and Taper phases as appropriate.
        """
    }

    private static func weekPromptText(
        inputs: PlanInputs,
        skeleton: OnDevicePlanSkeleton,
        week: OnDevicePlanSkeletonWeek,
        weekNumber: Int,
        ftp: Int,
        priorWeeksSummary: [PlanWeek]
    ) -> String {
        let prior = priorWeeksSummary.map {
            "Week \($0.weekNumber): \($0.title) TSS \($0.tssTarget.lowerBound)–\($0.tssTarget.upperBound)"
        }.joined(separator: "\n")

        return """
        Plan: \(skeleton.planName)
        Event: \(inputs.event_name) on \(inputs.event_date)
        FTP: \(ftp) W

        Build week \(weekNumber): \(week.title)
        Phase: \(week.phase)
        TSS target: \(week.tssTargetLow)–\(week.tssTargetHigh)
        Focus: \(week.focus)

        Prior weeks:
        \(prior.isEmpty ? "None (first week)." : prior)

        Return exactly 7 days (Mon=1 … Sun=7).
        Include at least one rest day. Key workouts should have structured intervals when appropriate.
        """
    }

    // MARK: - Mapping

    private static func assemblePlan(
        inputs: PlanInputs,
        skeleton: OnDevicePlanSkeleton,
        weeks: [PlanWeek]
    ) -> TrainingPlan {
        let distanceStr: String = {
            guard let km = inputs.target_distance_km, km > 0 else { return "" }
            return km >= 100 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }()
        let elevStr: String = {
            guard let m = inputs.target_elevation_m, m > 0 else { return "" }
            return String(format: "%.0f m", m)
        }()

        return TrainingPlan(
            id: "ondevice-\(UUID().uuidString.lowercased())",
            name: skeleton.planName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(inputs.event_name) Plan" : skeleton.planName,
            eventName: inputs.event_name,
            eventDate: inputs.event_date,
            distance: distanceStr,
            elevation: elevStr,
            location: inputs.event_location ?? "",
            description: skeleton.description,
            weeks: weeks
        )
    }

    private static func mapWeek(
        generated: OnDeviceGeneratedPlanWeek,
        skeletonWeek: OnDevicePlanSkeletonWeek,
        weekNumber: Int
    ) -> PlanWeek {
        let low = Double(skeletonWeek.tssTargetLow)
        let high = Double(skeletonWeek.tssTargetHigh)
        let hoursLow = max(1, low / 50.0)
        let hoursHigh = max(hoursLow, high / 45.0)

        let days = generated.days.enumerated().map { offset, day in
            mapDay(day, weekNumber: weekNumber, fallbackDayOfWeek: offset + 1)
        }

        return PlanWeek(
            weekNumber: weekNumber,
            phase: skeletonWeek.phase,
            title: skeletonWeek.title,
            totalHoursLow: hoursLow,
            totalHoursHigh: hoursHigh,
            tssTarget: skeletonWeek.tssTargetLow...max(
                skeletonWeek.tssTargetLow,
                skeletonWeek.tssTargetHigh
            ),
            focus: skeletonWeek.focus,
            days: days
        )
    }

    private static func mapDay(
        _ day: OnDeviceGeneratedPlanDay,
        weekNumber: Int,
        fallbackDayOfWeek: Int
    ) -> PlanDay {
        let dow = (1...7).contains(day.dayOfWeek) ? day.dayOfWeek : fallbackDayOfWeek
        let intervals = day.intervals.enumerated().map { index, item in
            IntervalSegment(
                order: index + 1,
                name: item.name.isEmpty ? "Interval \(index + 1)" : item.name,
                durationSeconds: max(30, item.durationSeconds),
                zone: mapZone(item.zone),
                repeats: max(1, item.repeats),
                cadenceLow: item.cadenceLow,
                cadenceHigh: item.cadenceHigh,
                recoverySeconds: max(0, item.recoverySeconds),
                recoveryZone: mapZone(item.recoveryZone),
                notes: item.notes,
                suggestedTrainerMode: mapTrainerMode(item.suggestedTrainerMode),
                simulationGrade: item.simulationGrade
            )
        }

        return PlanDay(
            id: "w\(weekNumber)-d\(dow)",
            weekNumber: weekNumber,
            dayOfWeek: dow,
            dayType: mapDayType(day.dayType),
            title: day.title.isEmpty ? "Ride" : day.title,
            durationMinutes: max(0, day.durationMinutes),
            zone: mapZone(day.zone),
            notes: day.notes,
            intervals: intervals,
            isKeyWorkout: day.isKeyWorkout,
            requiresFTPTest: day.requiresFTPTest
        )
    }

    private static func mapZone(_ raw: String) -> TrainingZoneTarget {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let z = TrainingZoneTarget(rawValue: t) { return z }
        switch t {
        case "Z1": return .z1
        case "Z2": return .z2
        case "Z3": return .z3
        case "Z4": return .z4
        case "Z5": return .z5
        case "Z1-Z2", "Z1Z2": return .z1z2
        case "Z2-Z3", "Z2Z3": return .z2z3
        case "Z3-Z4", "Z3Z4": return .z3z4
        case "Z3-Z5", "Z3Z5": return .z3z5
        case "Z4-Z5", "Z4Z5": return .z4z5
        case "REST": return .rest
        default: return .mixed
        }
    }

    private static func mapDayType(_ raw: String) -> PlanDayType {
        if let t = PlanDayType(rawValue: raw) { return t }
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "rest", "recovery": return .rest
        case "race": return .race
        case "event": return .event
        case "ftptest", "ftp_test", "ftp test": return .ftpTest
        case "optional", "optional_workout": return .optionalWorkout
        case "commute": return .commute
        default: return .workout
        }
    }

    private static func mapTrainerMode(_ raw: String) -> SuggestedTrainerMode {
        switch raw.lowercased() {
        case "simulation", "sim": return .simulation
        case "free", "free_ride", "freeride": return .freeRide
        default: return .erg
        }
    }
}

enum OnDevicePlanGeneratorError: Error, LocalizedError {
    case emptySkeleton
    case weekNotFound
    case unavailable
    case cloudFallbackDisabled
    case quotaLimitReached(String)

    var errorDescription: String? {
        switch self {
        case .emptySkeleton: return "Plan skeleton was empty."
        case .weekNotFound: return "Week not found in plan."
        case .unavailable: return "On-device plan generation is not available."
        case .cloudFallbackDisabled:
            return "Plan generation couldn't complete on-device. Enable **Allow Mangox Cloud fallback** in Settings → AI Coach, or try again after closing other coach sessions."
        case .quotaLimitReached(let message): return message
        }
    }
}
