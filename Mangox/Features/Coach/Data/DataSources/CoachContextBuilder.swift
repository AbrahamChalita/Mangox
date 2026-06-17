// Features/Coach/Data/DataSources/CoachContextBuilder.swift
import CryptoKit
import Foundation
import FoundationModels
import SwiftData

/// Immutable scalar values read from MainActor-isolated sources (WHOOP, FitnessTracker, etc.)
/// so the heavy context build can run off the main thread.
struct CoachContextScalarSnapshot: Sendable {
    let ftp: Int
    let maxHR: Int
    let restingHR: Int
    let riderWeightKg: Double?
    let riderAge: Int?
    let recoveryStatusLabel: String
    let whoopLinked: Bool
    let whoopRecoveryPercent: Double?
    let whoopRestingHR: Int?
    let whoopHrvMs: Int?
    let whoopMaxHeartRate: Int?
    let whoopSleepPerformancePercent: Double?
    let whoopSleepHours: Double?
    let fitnessTrackerLoaded: Bool
    let currentCtl: Double?
    let currentAtl: Double?
    let currentTsb: Double?
    let pmcTrendSummary: String?
}

/// Off-main-thread builder for coach context, snapshots, and encrypted payloads.
/// All methods are non-isolated so they can run inside detached tasks; the caller is
/// responsible for providing a fresh SwiftData ModelContext created on that task.
enum CoachContextBuilder {

    // MARK: - User context

    nonisolated static func buildUserContext(
        snapshot: CoachContextScalarSnapshot,
        modelContext: ModelContext
    ) -> UserContext {
        let ftp = snapshot.ftp
        let maxHR = snapshot.maxHR
        let restingHR = snapshot.restingHR

        // Recent workouts — last 30 days
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
        let workoutDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startDate >= thirtyDaysAgo }
        )
        let recentCount = (try? modelContext.fetchCount(workoutDescriptor)) ?? 0

        // Active plan
        let progressDescriptor = FetchDescriptor<TrainingPlanProgress>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let progresses = (try? modelContext.fetch(progressDescriptor)) ?? []
        let activeProgress = progresses.first

        let weekRange = TrainingPlanCompliance.currentWeekRange()

        var planName: String? = nil
        var planProgressStr: String? = nil
        var planSource: String? = nil
        var adaptiveErgPercent = 100
        var planSemanticsHint: String?
        if let p = activeProgress,
            let plan = PlanLibrary.resolvePlan(planID: p.planID, modelContext: modelContext)
        {
            planName = plan.name
            planSource = "ai"
            let totalDays = plan.allDays.filter {
                switch $0.dayType {
                case .workout, .ftpTest, .optionalWorkout, .commute: return true
                default: return false
                }
            }.count
            planProgressStr = "\(p.completedCount) of \(totalDays) workouts done"
            adaptiveErgPercent = Int((p.adaptiveLoadMultiplier * 100).rounded())

            var sawOptional = false
            var sawCommute = false
            for day in plan.allDays {
                let d = p.calendarDate(for: day)
                guard d >= weekRange.start, d < weekRange.end else { continue }
                if day.dayType == .optionalWorkout { sawOptional = true }
                if day.dayType == .commute { sawCommute = true }
            }
            if sawOptional || sawCommute {
                planSemanticsHint =
                    "This calendar week includes optional and/or commute days. Optional days are flexible volume; starred key days are priority quality sessions unless the day is explicitly optional. Commute days should stay easy."
            }
        }

        let weekStart = weekRange.start
        let weekEnd = weekRange.end
        let weekWorkouts = (try? modelContext.fetch(
            FetchDescriptor<Workout>(
                predicate: #Predicate<Workout> {
                    $0.startDate >= weekStart && $0.startDate < weekEnd
                }
            )
        )) ?? []
        let weekActualTss = Int(
            weekWorkouts
                .filter { $0.status == .completed && $0.isValid }
                .reduce(0.0) { $0 + $1.tss }
                .rounded()
        )

        // FTP history — last 3 test results
        let ftpHistory = FTPTestHistory.load()
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map { "\(Int($0.estimatedFTP))W" }
            .joined(separator: " → ")

        // Last completed ride — most recent completed workout
        let lastRideDescriptor = FetchDescriptor<Workout>(
            predicate: #Predicate<Workout> { $0.statusRaw == "completed" },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let lastRides = (try? modelContext.fetch(lastRideDescriptor)) ?? []
        let lastRide = lastRides.first
        let recentRideDigest = lastRides
            .filter(\.isValid)
            .prefix(5)
            .map { ride in
                var parts: [String] = [
                    "\(Int(ride.duration / 60))min",
                    String(format: "%.1fkm", ride.distance / 1000),
                ]
                if ride.avgPower > 0 {
                    parts.append("\(Int(ride.avgPower))W avg")
                    parts.append("TSS \(Int(ride.tss.rounded()))")
                }
                if ride.avgHR > 0 {
                    parts.append("\(Int(ride.avgHR)) bpm")
                }
                if !ride.notes.isEmpty {
                    parts.append("notes: \(ride.notes.prefix(40))")
                }
                let dateString = ride.startDate.formatted(.dateTime.year().month(.abbreviated).day())
                return "\(dateString): \(parts.joined(separator: " · "))"
            }
            .joined(separator: "\n")

        var lastRideContext: LastRideContext?
        if let ride = lastRide {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let dateStr = formatter.localizedString(for: ride.startDate, relativeTo: .now)
            let powerOK = ride.maxPower > 0 || ride.avgPower > 0
            var summaryParts: [String] = [
                "\(Int(ride.duration / 60))min",
                String(format: "%.1fkm", ride.distance / 1000),
            ]
            if powerOK {
                summaryParts.append(contentsOf: [
                    "\(Int(ride.avgPower))W avg",
                    "NP \(Int(ride.normalizedPower))W",
                    "TSS \(Int(ride.tss))",
                ])
            } else {
                summaryParts.append("no power data — NP/TSS not power-based")
                if ride.displayAverageSpeedKmh > 0.5 {
                    summaryParts.append(
                        String(format: "%.1f km/h avg", ride.displayAverageSpeedKmh))
                }
            }
            if ride.avgHR > 0 {
                summaryParts.append("\(Int(ride.avgHR)) bpm avg HR")
            }
            if ride.elevationGain > 1 {
                summaryParts.append(String(format: "%.0f m elev", ride.elevationGain))
            }
            let aerobicDecoupling = AerobicDecouplingAnalytics.compute(from: ride)
            if let aerobicDecoupling {
                summaryParts.append(aerobicDecoupling.plainLanguageSummary)
            }

            lastRideContext = LastRideContext(
                date: dateStr,
                durationMinutes: Int(ride.duration / 60),
                distanceKm: ride.distance / 1000,
                avgPower: ride.avgPower,
                maxPower: ride.maxPower,
                avgHR: ride.avgHR,
                avgSpeed: ride.avgSpeed,
                elevationGain: ride.elevationGain,
                normalizedPower: ride.normalizedPower,
                tss: ride.tss,
                intensityFactor: ride.intensityFactor,
                summary: summaryParts.joined(separator: " · "),
                powerDataAvailable: powerOK,
                aerobicDecouplingPercent: aerobicDecoupling?.decouplingPercent,
                aerobicDecouplingStatus: aerobicDecoupling?.status.rawValue
            )
        }

        let riderWeight = snapshot.riderWeightKg

        let decouplingSamples: [AerobicDecouplingTrend.RideSample] = lastRides
            .filter(\.isValid)
            .prefix(12)
            .reversed()
            .compactMap { ride in
                guard let result = AerobicDecouplingAnalytics.compute(from: ride),
                      result.status != .insufficientData
                else { return nil }
                return AerobicDecouplingTrend.RideSample(
                    date: ride.startDate,
                    decouplingPercent: result.decouplingPercent,
                    status: result.status
                )
            }
        let decouplingTrend = AerobicDecouplingTrend.analyze(rides: decouplingSamples)
        let aerobicDecouplingTrendSummary =
            decouplingTrend.direction == .insufficientData
            ? nil
            : decouplingTrend.plainLanguageSummary

        let powerCurveCandidates = WorkoutMetricsSnapshot.powerCurveCandidates(
            from: lastRides.filter(\.isValid),
            rangeDays: PowerCurveSummary.defaultRangeDays
        )
        let powerCurvePoints = PowerCurveAnalytics.compute(
            from: powerCurveCandidates.map(\.sortedPowers)
        )
        let powerCurveSummaryText = powerCurvePoints.isEmpty
            ? nil
            : PowerCurveSummary.format(
                points: powerCurvePoints,
                ftp: ftp,
                rangeDays: PowerCurveSummary.defaultRangeDays
            )

        let criticalPowerSummaryText = CriticalPowerModel.fit(from: powerCurvePoints).map(\.plainLanguageSummary)

        return UserContext(
            ftp: ftp,
            maxHR: maxHR,
            restingHR: restingHR,
            recentWorkoutsCount: recentCount,
            activePlanName: planName,
            activePlanProgress: planProgressStr,
            activePlanSource: planSource,
            weekActualTss: weekActualTss,
            adaptiveErgPercent: adaptiveErgPercent,
            ftpHistory: ftpHistory.isEmpty ? nil : ftpHistory,
            lastRide: lastRideContext,
            seasonGoalSummary: nil,
            planKeyDaySemanticsHint: planSemanticsHint,
            recentRideDigest: recentRideDigest.isEmpty ? nil : recentRideDigest,
            lastRideAerobicDecoupling: lastRideContext.flatMap { context in
                guard let percent = context.aerobicDecouplingPercent,
                      let status = context.aerobicDecouplingStatus
                else { return nil }
                return String(format: "%.1f%% %@", percent, status)
            },
            riderWeightKg: riderWeight,
            riderAge: snapshot.riderAge,
            recoveryStatusLabel: snapshot.recoveryStatusLabel,
            fitnessTrackerLoaded: snapshot.fitnessTrackerLoaded,
            whoopLinked: snapshot.whoopLinked,
            whoopRecoveryPercent: snapshot.whoopRecoveryPercent,
            whoopRestingHR: snapshot.whoopRestingHR,
            whoopHrvMs: snapshot.whoopHrvMs,
            whoopMaxHeartRate: snapshot.whoopMaxHeartRate,
            whoopSleepPerformancePercent: snapshot.whoopSleepPerformancePercent,
            whoopSleepHours: snapshot.whoopSleepHours,
            currentCtl: snapshot.currentCtl,
            currentAtl: snapshot.currentAtl,
            currentTsb: snapshot.currentTsb,
            pmcTrendSummary: snapshot.pmcTrendSummary,
            aerobicDecouplingTrend: aerobicDecouplingTrendSummary,
            powerCurveSummary: powerCurveSummaryText,
            criticalPowerSummary: criticalPowerSummaryText
        )
    }

    // MARK: - Fact sheets / snapshot

    nonisolated static func factSheetTextFull(userContext ctx: UserContext) -> String {
        var lines: [String] = []
        lines.append(
            "Rider: FTP \(ctx.ftp)W, max HR \(ctx.maxHR), resting HR \(ctx.restingHR).")
        if let w = ctx.riderWeightKg, w > 0 {
            lines.append(String(format: "Weight: %.1f kg.", w))
        }
        if let age = ctx.riderAge, age > 0 {
            lines.append("Age: \(age) years.")
        }
        lines.append("Completed workouts (last 30d): \(ctx.recentWorkoutsCount).")
        lines.append("This calendar week TSS (completed valid rides): \(ctx.weekActualTss).")
        if ctx.whoopLinked, let pct = ctx.whoopRecoveryPercent {
            let rhr = ctx.whoopRestingHR.map { "\($0) bpm" } ?? "n/a"
            let hrv = ctx.whoopHrvMs.map { "\($0) ms" } ?? "n/a"
            let mhr = ctx.whoopMaxHeartRate.map { "\($0) bpm" } ?? "n/a"
            lines.append(
                "WHOOP recovery \(Int(pct))% (RHR \(rhr), HRV \(hrv), profile max HR \(mhr)). Readiness label: \(ctx.recoveryStatusLabel)."
            )
        } else {
            lines.append("Recovery / readiness (from recent rides): \(ctx.recoveryStatusLabel).")
        }
        if ctx.whoopLinked {
            lines.append(
                "Note: WHOOP’s public API does not include VO₂ max; use Apple Health in Mangox for VO₂ if available."
            )
        }
        if let hist = ctx.ftpHistory, !hist.isEmpty {
            lines.append("Recent FTP test trend (newest first): \(hist).")
        }
        if let plan = ctx.activePlanName {
            var p = "Active plan: \(plan)."
            if let prog = ctx.activePlanProgress { p += " Progress: \(prog)." }
            if let src = ctx.activePlanSource { p += " Source: \(src)." }
            p += " Adaptive ERG scale: \(ctx.adaptiveErgPercent)%."
            lines.append(p)
        } else {
            lines.append("No active plan in app.")
        }
        if let hint = ctx.planKeyDaySemanticsHint {
            lines.append("Plan week note: \(hint)")
        }
        if let goal = ctx.seasonGoalSummary, !goal.isEmpty {
            lines.append("Season goal: \(goal)")
        }

        if ctx.fitnessTrackerLoaded {
            lines.append(String(format: "Current training load: CTL %.1f (fitness), ATL %.1f (fatigue), TSB %+.1f (form).", ctx.currentCtl ?? 0, ctx.currentAtl ?? 0, ctx.currentTsb ?? 0))
            if let trend = ctx.pmcTrendSummary {
                lines.append(trend)
            }
        }

        if let decouplingTrend = ctx.aerobicDecouplingTrend, !decouplingTrend.isEmpty {
            lines.append("Decoupling trend: \(decouplingTrend)")
        }
        if let curve = ctx.powerCurveSummary, !curve.isEmpty {
            lines.append(curve)
        }
        if let cp = ctx.criticalPowerSummary, !cp.isEmpty {
            lines.append("Critical power: \(cp)")
        }

        if let ride = ctx.lastRide {
            lines.append("Last completed ride (\(ride.date)): \(ride.summary).")
        } else {
            lines.append("No completed ride on file.")
        }
        if let digest = ctx.recentRideDigest, !digest.isEmpty {
            lines.append("Recent ride history:\n\(digest)")
        }
        let joined = lines.joined(separator: "\n")
        if joined.count > 2800 {
            return String(joined.prefix(2800)) + "\n…"
        }
        return joined
    }

    nonisolated static func factSheetTextCompact(userContext ctx: UserContext) -> String {
        var lines: [String] = []
        lines.append(
            "Rider: FTP \(ctx.ftp)W, max HR \(ctx.maxHR), resting HR \(ctx.restingHR).")
        if ctx.whoopLinked, let pct = ctx.whoopRecoveryPercent {
            lines.append(
                "Week TSS: \(ctx.weekActualTss). WHOOP recovery \(Int(pct))%. Readiness: \(ctx.recoveryStatusLabel)."
            )
        } else {
            lines.append(
                "Week TSS: \(ctx.weekActualTss). Workouts (30d): \(ctx.recentWorkoutsCount). Recovery: \(ctx.recoveryStatusLabel)."
            )
        }
        if let hist = ctx.ftpHistory, !hist.isEmpty {
            lines.append("FTP tests: \(hist)")
        }
        if let plan = ctx.activePlanName {
            lines.append(
                "Plan: \(plan). \(ctx.activePlanProgress ?? "") ERG \(ctx.adaptiveErgPercent)%.")
        } else {
            lines.append("No active plan.")
        }

        if ctx.fitnessTrackerLoaded {
            lines.append(String(format: "Load: CTL %.0f / ATL %.0f / TSB %+.0f", ctx.currentCtl ?? 0, ctx.currentAtl ?? 0, ctx.currentTsb ?? 0))
            if let trend = ctx.pmcTrendSummary {
                lines.append("PMC: \(trend)")
            }
        }
        if let decouplingTrend = ctx.aerobicDecouplingTrend, !decouplingTrend.isEmpty {
            lines.append("Decoupling: \(decouplingTrend)")
        }

        if let ride = ctx.lastRide {
            lines.append("Last ride (\(ride.date)): \(ride.summary)")
        } else {
            lines.append("No last ride.")
        }
        if let digest = ctx.recentRideDigest, !digest.isEmpty {
            let firstLine = digest.split(separator: "\n").prefix(2).joined(separator: " | ")
            if !firstLine.isEmpty {
                lines.append("Recent rides: \(firstLine)")
            }
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func trainingSnapshot(
        userContext: UserContext,
        usePrivateCloudCompute: Bool
    ) async -> String {
        let full = factSheetTextFull(userContext: userContext)
        let compact = factSheetTextCompact(userContext: userContext)
        let snapshotTokenBudget = MangoxPCCSupport.snapshotTokenBudget(
            usePrivateCloudCompute: usePrivateCloudCompute
        )
        let model = SystemLanguageModel.default
        do {
            let fullTok = try await model.tokenCount(for: full)
            if fullTok <= snapshotTokenBudget {
                MangoxFoundationModelsSupport.logSnapshotSelection(
                    fullChosen: true, tokenEstimate: fullTok)
                return full
            }
            let compactTok = try await model.tokenCount(for: compact)
            MangoxFoundationModelsSupport.logSnapshotSelection(
                fullChosen: false, tokenEstimate: compactTok)
            return compact
        } catch {
            let charBudget = usePrivateCloudCompute ? 10_000 : 2400
            return full.count > charBudget ? compact : full
        }
    }

    // MARK: - Encryption

    nonisolated static func encryptUserContext(
        context: UserContext,
        key: SymmetricKey?
    ) -> String? {
        guard let key,
            let json = try? JSONEncoder().encode(context)
        else { return nil }
        guard let sealed = try? AES.GCM.seal(json, using: key),
            let combined = sealed.combined
        else { return nil }
        return combined.base64EncodedString()
    }
}
