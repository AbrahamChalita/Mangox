#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

@MainActor
enum SimulatorDemoDataSeeder {
    static let seedKey = "debug.seedSimulatorData"
    static let resetKey = "debug.resetSimulatorData"
    private static let seededVersionKey = "debug.seedSimulatorData.version"
    private static let seededVersion = "2026-04-19-v1"

    static func runIfNeeded(modelContext: ModelContext) {
        let defaults = UserDefaults.standard
        let shouldSeed = defaults.bool(forKey: seedKey)
        let shouldReset = defaults.bool(forKey: resetKey)

        guard shouldSeed || shouldReset else { return }

        if shouldReset {
            clearSeedableData(modelContext: modelContext)
            defaults.removeObject(forKey: seededVersionKey)
        }

        if defaults.string(forKey: seededVersionKey) == seededVersion {
            defaults.set(false, forKey: seedKey)
            defaults.set(false, forKey: resetKey)
            return
        }

        if !shouldReset && hasExistingUserData(modelContext: modelContext) {
            defaults.set(false, forKey: seedKey)
            defaults.set(false, forKey: resetKey)
            return
        }

        seedData(modelContext: modelContext)
        defaults.set(seededVersion, forKey: seededVersionKey)
        defaults.set(false, forKey: seedKey)
        defaults.set(false, forKey: resetKey)
        defaults.set(true, forKey: "hasCompletedOnboarding")
    }

    private static func hasExistingUserData(modelContext: ModelContext) -> Bool {
        hasAny(Workout.self, modelContext: modelContext)
            || hasAny(AIGeneratedPlan.self, modelContext: modelContext)
            || hasAny(ChatSession.self, modelContext: modelContext)
    }

    private static func hasAny<T: PersistentModel>(
        _ type: T.Type,
        modelContext: ModelContext
    ) -> Bool {
        var descriptor = FetchDescriptor<T>()
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor)) ?? []).isEmpty == false
    }

    private static func clearSeedableData(modelContext: ModelContext) {
        deleteAll(Workout.self, modelContext: modelContext)
        deleteAll(ChatSession.self, modelContext: modelContext)
        deleteAll(AIGeneratedPlan.self, modelContext: modelContext)
        deleteAll(TrainingPlanProgress.self, modelContext: modelContext)
        try? modelContext.save()
    }

    private static func deleteAll<T: PersistentModel>(
        _ type: T.Type,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<T>()
        let objects = (try? modelContext.fetch(descriptor)) ?? []
        for object in objects {
            modelContext.delete(object)
        }
    }

    private static func seedData(modelContext: ModelContext) {
        let plan = seededPlan()
        let planData = try? JSONEncoder().encode(plan)
        let generatedPlan = AIGeneratedPlan(
            id: plan.id,
            planJSON: planData ?? Data(),
            generatedAt: .now.addingTimeInterval(-3600 * 6),
            userPrompt: "Build me a structured 6-week climbing plan for a gran fondo with 7 to 9 hours per week."
        )
        let progress = seededProgress(for: plan)

        modelContext.insert(generatedPlan)
        modelContext.insert(progress)

        for workout in seededWorkouts(plan: plan) {
            modelContext.insert(workout)
            for sample in workout.samples {
                modelContext.insert(sample)
            }
        }

        for session in seededChatSessions() {
            modelContext.insert(session)
            for message in session.messages {
                modelContext.insert(message)
            }
        }

        try? modelContext.save()
    }

    private static func seededProgress(for plan: TrainingPlan) -> TrainingPlanProgress {
        let startDate = seededPlanStartDate()
        let progress = TrainingPlanProgress(
            planID: plan.id,
            startDate: startDate,
            ftp: 265,
            aiPlanTitle: plan.name
        )
        progress.completedDayIDs = ["sim-week1-day2", "sim-week1-day4", "sim-week1-day6"]
        progress.currentFTP = 265
        progress.adaptiveLoadMultiplier = 1.03
        return progress
    }

    private static func seededPlanStartDate() -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let offsetFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offsetFromMonday, to: today) ?? today
    }

    private static func seededPlan() -> TrainingPlan {
        let weekOneDays: [PlanDay] = [
            PlanDay(
                id: "sim-week1-day1",
                weekNumber: 1,
                dayOfWeek: 1,
                dayType: .rest,
                title: "Reset + mobility",
                durationMinutes: 0,
                zone: .rest,
                notes: "Keep it easy and prepare for the build block.",
                intervals: [],
                isKeyWorkout: false,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day2",
                weekNumber: 1,
                dayOfWeek: 2,
                dayType: .workout,
                title: "Threshold ladders",
                durationMinutes: 70,
                zone: .z4,
                notes: "Stay seated and smooth on the threshold ramps.",
                intervals: [
                    IntervalSegment(order: 1, name: "Warm up", durationSeconds: 900, zone: .z2, cadenceLow: 85, cadenceHigh: 95),
                    IntervalSegment(order: 2, name: "Threshold", durationSeconds: 480, zone: .z4, repeats: 3, cadenceLow: 88, cadenceHigh: 96, recoverySeconds: 180, recoveryZone: .z2),
                    IntervalSegment(order: 3, name: "Cool down", durationSeconds: 600, zone: .z1)
                ],
                isKeyWorkout: true,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day3",
                weekNumber: 1,
                dayOfWeek: 3,
                dayType: .commute,
                title: "Endurance spin",
                durationMinutes: 50,
                zone: .z2,
                notes: "Cadence focus.",
                intervals: [],
                isKeyWorkout: false,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day4",
                weekNumber: 1,
                dayOfWeek: 4,
                dayType: .workout,
                title: "VO2 repeats",
                durationMinutes: 60,
                zone: .z5,
                notes: "Keep recoveries easy.",
                intervals: [
                    IntervalSegment(order: 1, name: "Warm up", durationSeconds: 900, zone: .z2),
                    IntervalSegment(order: 2, name: "VO2", durationSeconds: 180, zone: .z5, repeats: 5, cadenceLow: 95, cadenceHigh: 105, recoverySeconds: 180, recoveryZone: .z1),
                    IntervalSegment(order: 3, name: "Cool down", durationSeconds: 600, zone: .z1)
                ],
                isKeyWorkout: true,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day5",
                weekNumber: 1,
                dayOfWeek: 5,
                dayType: .rest,
                title: "Recovery day",
                durationMinutes: 0,
                zone: .rest,
                notes: "Walk, stretch, sleep.",
                intervals: [],
                isKeyWorkout: false,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day6",
                weekNumber: 1,
                dayOfWeek: 6,
                dayType: .workout,
                title: "Sweet spot build",
                durationMinutes: 90,
                zone: .z3z4,
                notes: "Progress through the final block if legs feel good.",
                intervals: [
                    IntervalSegment(order: 1, name: "Warm up", durationSeconds: 900, zone: .z2),
                    IntervalSegment(order: 2, name: "Sweet spot", durationSeconds: 720, zone: .z3z4, repeats: 3, cadenceLow: 85, cadenceHigh: 95, recoverySeconds: 240, recoveryZone: .z2),
                    IntervalSegment(order: 3, name: "Cool down", durationSeconds: 600, zone: .z1)
                ],
                isKeyWorkout: true,
                requiresFTPTest: false
            ),
            PlanDay(
                id: "sim-week1-day7",
                weekNumber: 1,
                dayOfWeek: 7,
                dayType: .workout,
                title: "Climbing simulation",
                durationMinutes: 105,
                zone: .mixed,
                notes: "Simulate gran fondo pacing with seated climbs and one late surge.",
                intervals: [
                    IntervalSegment(order: 1, name: "Warm up", durationSeconds: 900, zone: .z2),
                    IntervalSegment(order: 2, name: "Climb block", durationSeconds: 900, zone: .z3, repeats: 3, cadenceLow: 72, cadenceHigh: 84, recoverySeconds: 300, recoveryZone: .z2, suggestedTrainerMode: .simulation, simulationGrade: 5.5),
                    IntervalSegment(order: 3, name: "Late surge", durationSeconds: 300, zone: .z4z5, cadenceLow: 80, cadenceHigh: 92),
                    IntervalSegment(order: 4, name: "Cool down", durationSeconds: 600, zone: .z1)
                ],
                isKeyWorkout: true,
                requiresFTPTest: false
            )
        ]

        let weekTwoDays = weekOneDays.enumerated().map { index, day in
            PlanDay(
                id: "sim-week2-day\(index + 1)",
                weekNumber: 2,
                dayOfWeek: day.dayOfWeek,
                dayType: day.dayType,
                title: index == 6 ? "Gran fondo taper ride" : day.title,
                durationMinutes: index == 6 ? 80 : day.durationMinutes,
                zone: day.zone,
                notes: day.notes,
                intervals: day.intervals,
                isKeyWorkout: day.isKeyWorkout,
                requiresFTPTest: false
            )
        }

        return TrainingPlan(
            id: "sim-plan-gran-fondo",
            name: "Gran Fondo Build",
            eventName: "Climbing Gran Fondo",
            eventDate: "May 24",
            distance: "118 km",
            elevation: "2,100 m",
            location: "Mexico City",
            description: "Six-week build focused on threshold durability, climbing torque, and long-ride specificity.",
            weeks: [
                PlanWeek(
                    weekNumber: 1,
                    phase: "Build",
                    title: "Load in",
                    totalHoursLow: 7,
                    totalHoursHigh: 9,
                    tssTarget: 420...520,
                    focus: "Threshold + torque climbing",
                    days: weekOneDays
                ),
                PlanWeek(
                    weekNumber: 2,
                    phase: "Build",
                    title: "Specificity",
                    totalHoursLow: 7,
                    totalHoursHigh: 8,
                    tssTarget: 390...470,
                    focus: "Race-like terrain",
                    days: weekTwoDays
                )
            ]
        )
    }

    private static func seededWorkouts(plan: TrainingPlan) -> [Workout] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return [
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -10, to: today) ?? today,
                durationMinutes: 92,
                avgPower: 212,
                maxPower: 588,
                normalizedPower: 228,
                tss: 96,
                distanceKm: 48.6,
                avgCadence: 87,
                avgHR: 146,
                maxHR: 171,
                avgSpeedKmh: 31.7,
                basePower: 180,
                powerVariance: 44,
                heartRateBase: 132,
                routeKind: .free,
                routeName: "Tempo Loop"
            ),
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -8, to: today) ?? today,
                durationMinutes: 64,
                avgPower: 235,
                maxPower: 690,
                normalizedPower: 249,
                tss: 88,
                distanceKm: 34.2,
                avgCadence: 91,
                avgHR: 151,
                maxHR: 176,
                avgSpeedKmh: 32.1,
                basePower: 195,
                powerVariance: 55,
                heartRateBase: 136,
                planDayID: "sim-week1-day2",
                planID: plan.id
            ),
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -6, to: today) ?? today,
                durationMinutes: 72,
                avgPower: 248,
                maxPower: 742,
                normalizedPower: 262,
                tss: 95,
                distanceKm: 0,
                avgCadence: 93,
                avgHR: 155,
                maxHR: 182,
                avgSpeedKmh: 0,
                basePower: 205,
                powerVariance: 65,
                heartRateBase: 140,
                planDayID: "sim-week1-day4",
                planID: plan.id
            ),
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -4, to: today) ?? today,
                durationMinutes: 84,
                avgPower: 228,
                maxPower: 612,
                normalizedPower: 241,
                tss: 92,
                distanceKm: 0,
                avgCadence: 86,
                avgHR: 148,
                maxHR: 173,
                avgSpeedKmh: 0,
                basePower: 190,
                powerVariance: 48,
                heartRateBase: 135,
                planDayID: "sim-week1-day6",
                planID: plan.id
            ),
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -2, to: today) ?? today,
                durationMinutes: 141,
                avgPower: 201,
                maxPower: 524,
                normalizedPower: 214,
                tss: 118,
                distanceKm: 74.3,
                avgCadence: 84,
                avgHR: 143,
                maxHR: 166,
                avgSpeedKmh: 31.4,
                basePower: 170,
                powerVariance: 38,
                heartRateBase: 130,
                routeKind: .gpx,
                routeName: "Sierra Loop"
            ),
            makeWorkout(
                startDate: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                durationMinutes: 57,
                avgPower: 176,
                maxPower: 461,
                normalizedPower: 184,
                tss: 51,
                distanceKm: 28.7,
                avgCadence: 83,
                avgHR: 138,
                maxHR: 161,
                avgSpeedKmh: 30.2,
                basePower: 155,
                powerVariance: 30,
                heartRateBase: 126,
                imported: true
            )
        ]
    }

    private static func makeWorkout(
        startDate: Date,
        durationMinutes: Int,
        avgPower: Double,
        maxPower: Int,
        normalizedPower: Double,
        tss: Double,
        distanceKm: Double,
        avgCadence: Double,
        avgHR: Double,
        maxHR: Int,
        avgSpeedKmh: Double,
        basePower: Int,
        powerVariance: Int,
        heartRateBase: Int,
        planDayID: String? = nil,
        planID: String? = nil,
        routeKind: SavedRouteKind? = nil,
        routeName: String? = nil,
        imported: Bool = false
    ) -> Workout {
        let workout = Workout(startDate: startDate, planDayID: planDayID, planID: planID)
        workout.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        workout.duration = TimeInterval(durationMinutes * 60)
        workout.distance = distanceKm * 1000
        workout.avgPower = avgPower
        workout.maxPower = maxPower
        workout.avgCadence = avgCadence
        workout.avgSpeed = avgSpeedKmh
        workout.avgHR = avgHR
        workout.maxHR = maxHR
        workout.normalizedPower = normalizedPower
        workout.tss = tss
        workout.intensityFactor = normalizedPower / 265
        workout.status = .completed
        workout.origin = imported ? .imported : .recorded
        workout.importFormat = imported ? .fit : nil
        workout.savedRouteKind = routeKind
        workout.savedRouteName = routeName
        workout.routeDestinationSummary = routeName
        workout.smartTitle = planDayID != nil ? "Executed as planned" : (imported ? "Imported endurance ride" : "Outside endurance")

        let samples = makeSamples(
            startDate: startDate,
            durationMinutes: durationMinutes,
            basePower: basePower,
            powerVariance: powerVariance,
            heartRateBase: heartRateBase,
            avgSpeedKmh: avgSpeedKmh
        )
        workout.samples = samples
        workout.sampleCount = samples.count
        for sample in samples {
            sample.workout = workout
        }

        return workout
    }

    private static func makeSamples(
        startDate: Date,
        durationMinutes: Int,
        basePower: Int,
        powerVariance: Int,
        heartRateBase: Int,
        avgSpeedKmh: Double
    ) -> [WorkoutSample] {
        let seconds = max(durationMinutes * 60, 1200)
        let sampleStep = 30
        return Swift.stride(from: 0, through: seconds, by: sampleStep).map { elapsed in
            let wave = sin(Double(elapsed) / 240)
            let surge = elapsed % 360 < 120 ? Double(powerVariance) * 0.6 : 0
            let power = max(95, Int(Double(basePower) + wave * Double(powerVariance) + surge))
            let cadence = max(68, Double(84 + Int(cos(Double(elapsed) / 160) * 8)))
            let heartRate = max(108, Int(Double(heartRateBase) + wave * 10 + surge * 0.08))
            let speed = avgSpeedKmh > 0 ? max(22, avgSpeedKmh + wave * 2.2) : max(28, 31 + wave * 1.4)
            return WorkoutSample(
                timestamp: startDate.addingTimeInterval(TimeInterval(elapsed)),
                elapsedSeconds: elapsed,
                power: power,
                cadence: cadence,
                speed: speed,
                heartRate: heartRate
            )
        }
    }

    private static func seededChatSessions() -> [ChatSession] {
        let primary = ChatSession(
            id: UUID(uuidString: "8FE37C94-5F7D-4D58-B4F8-19384A5B5F21") ?? UUID(),
            title: "Gran fondo build",
            createdAt: .now.addingTimeInterval(-3600 * 20),
            updatedAt: .now.addingTimeInterval(-900)
        )
        primary.messages = [
            persistedMessage(
                ChatMessage(
                    id: UUID(uuidString: "B4CBAA3A-8E60-4A39-9F3E-93A0B7A4C120") ?? UUID(),
                    role: .user,
                    content: "I’m targeting a climbing gran fondo in 6 weeks and can train 7 to 9 hours. Can you build me toward it?",
                    timestamp: .now.addingTimeInterval(-3600 * 19),
                    suggestedActions: [],
                    followUpQuestion: nil,
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: nil,
                    tags: [],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 1
                ),
                session: primary
            ),
            persistedMessage(
                ChatMessage(
                    id: UUID(uuidString: "086A2FC0-3D7D-40A0-8A4D-EA5C45B35C93") ?? UUID(),
                    role: .assistant,
                    content: "Yes. I’d bias this block toward threshold durability, seated climbing torque, and one long specificity ride each weekend. I’ve drafted a build that keeps Tuesday and Thursday as quality days, Saturday as the longest session, and Friday mostly easy so you arrive fresh for the weekend load.",
                    timestamp: .now.addingTimeInterval(-3600 * 18),
                    suggestedActions: [
                        SuggestedAction(label: "Show the plan", type: "open_plan"),
                        SuggestedAction(label: "Tune weekly hours", type: "ask_followup"),
                        SuggestedAction(label: "Add nutrition notes", type: "ask_followup")
                    ],
                    followUpQuestion: "What would you like to tune first?",
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: "training_advice",
                    tags: ["climbing", "threshold", "specificity"],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 0.96
                ),
                session: primary
            )
        ]

        let recovery = ChatSession(
            id: UUID(uuidString: "1A3B486D-0C44-4A2E-9867-52D8AE804B1E") ?? UUID(),
            title: "Recovery week check-in",
            createdAt: .now.addingTimeInterval(-3600 * 72),
            updatedAt: .now.addingTimeInterval(-3600 * 8)
        )
        recovery.messages = [
            persistedMessage(
                ChatMessage(
                    id: UUID(),
                    role: .user,
                    content: "My legs feel heavy after the VO2 day. Should I still do the long ride tomorrow?",
                    timestamp: .now.addingTimeInterval(-3600 * 9),
                    suggestedActions: [],
                    followUpQuestion: nil,
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: nil,
                    tags: [],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 1
                ),
                session: recovery
            ),
            persistedMessage(
                ChatMessage(
                    id: UUID(),
                    role: .assistant,
                    content: "Keep the ride, but trim the first hour to endurance and skip the late surge if your heart rate is drifting early. The goal is still time-in-zone, not forcing freshness you don’t have.",
                    timestamp: .now.addingTimeInterval(-3600 * 8),
                    suggestedActions: [
                        SuggestedAction(label: "Adjust tomorrow", type: "ask_followup"),
                        SuggestedAction(label: "Give me a recovery checklist", type: "ask_followup")
                    ],
                    followUpQuestion: nil,
                    followUpBlocks: [],
                    thinkingSteps: [],
                    category: "recovery",
                    tags: ["recovery", "load management"],
                    references: [],
                    usedWebSearch: false,
                    feedbackScore: nil,
                    confidence: 0.92
                ),
                session: recovery
            )
        ]

        return [primary, recovery]
    }

    private static func persistedMessage(_ message: ChatMessage, session: ChatSession) -> CoachChatMessage {
        let stored = CoachChatMessage.from(message)
        stored.session = session
        return stored
    }
}
#endif
